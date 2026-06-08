<p align="center">
  <img src="assets/logo.svg" alt="dagger-zig logo" width="200" height="200">
</p>

# dagger-zig

[![Dagger](https://img.shields.io/badge/Powered%20by-Dagger-blue.svg)](https://dagger.io)
[![Zig Version](https://img.shields.io/badge/Zig-0.16-orange.svg)](https://ziglang.org)
[![CI](https://github.com/MChorfa/dagger-zig/actions/workflows/ci.yml/badge.svg)](https://github.com/MChorfa/dagger-zig/actions)
[![Security](https://github.com/MChorfa/dagger-zig/actions/workflows/security.yml/badge.svg)](https://github.com/MChorfa/dagger-zig/actions)
[![OpenSSF Scorecard](https://api.securityscorecards.dev/projects/github.com/MChorfa/dagger-zig/badge)](https://securityscorecards.dev/viewer/?uri=github.com/MChorfa/dagger-zig)
[![SLSA](https://img.shields.io/badge/SLSA-In%20Progress-yellow.svg)](https://slsa.dev)
[![Sigstore](https://img.shields.io/badge/Sigstore-signed-blue.svg)](https://sigstore.dev)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

A native Zig SDK for the [Dagger](https://dagger.io) programmable CI/CD engine.

> **📚 Looking for Dagger?** Visit [dagger.io](https://dagger.io) • [Docs](https://docs.dagger.io) • [GitHub](https://github.com/dagger/dagger)
> **Status:** v0.2.1. POSIX-only synchronous client SDK with module authoring and tracing.  
> **Security Hardened:** OpenSSF Scorecard, SLSA provenance, Sigstore signing

Zero external dependencies. Zig stdlib only. Authored against Zig 0.16.0.

## What works in v0.2.1

- **Client API.** Synchronous Dagger API for Linux/macOS: containers, directories, files,
  secrets, cache volumes, services, git repositories. Chain methods
  the way you would in any other SDK.
- **Distributed Tracing.** OpenTelemetry-compatible tracing via `dagger.tracing`.
  Exports spans in a custom JSON shape compatible with OpenTelemetry tooling.
  OTLP export to Jaeger/Zipkin collectors is deferred to v0.3.0.
- **CLI session lifecycle.** Resolves via three-tier handshake: env vars
  from `dagger run --` → `_EXPERIMENTAL_DAGGER_CLI_BIN` path → `dagger`
  on `$PATH`. Never auto-downloads the CLI.
- **Module authoring.** Write a Zig struct, give it methods, expose to
  Dagger with `dagger.module.serve(init, MyModule{})`. Comptime
  reflection maps Zig types to Dagger `TypeDef` values automatically;
  unmappable signatures fail at `zig build`, not at engine-dispatch.
- **SPIFFE/SPIRE workload identity (experimental).** Enable with
  `-Dspiffe-experimental`. `ShelloutSource` backend (via `spire-agent api fetch`)
  is the working backend; `NativeWorkloadAPISource` ships as a type-complete
  skeleton for v0.3.0.
- **Self-hosting CI.** This repo's own CI pipeline is in `ci/main.zig` —
  a Zig Dagger module that uses dagger-zig to build dagger-zig.

## What's explicitly deferred to v0.3.0

- **Async patterns.** `dagger.async` (`QueryGroup`, `QueryBatch`, `withRetry`) — disabled in
  v0.2.1 to prevent `error.NotImplemented` failures. Coming in v0.3.0.
- **Windows support.** Socket operations return `error.NotSupported` on Windows in v0.2.1.
  Full Windows support planned for v0.3.0.
- **C ABI.** `zig build c-lib` is disabled in v0.2.1 (compilation issues with Zig 0.16).
  Will be re-enabled in v0.3.0.
- Native SPIFFE Workload API (pure Zig HTTP/2 + gRPC + protobuf).
- Vault cert-auth for `spiffe_integration.spiffeRegistryAuth`. Shares TLS
  layer with native SPIFFE, so they land together.
- Shellout X.509 PEM parser (currently the shellout backend runs
  `spire-agent` successfully but the DER parser is stubbed).
- Real per-module codegen (generated `dagger.gen.zig` containing only
  user-dep types, not the full schema).

## Quick start

```zig
const std = @import("std");
const dagger = @import("dagger_sdk");

pub fn main() !void {
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var io_impl: std.Io.Threaded = .init_single_threaded;
    const io = io_impl.io();

    var client = try dagger.connect(gpa, io, .{});
    defer client.close();

    const ctr  = try client.dag().container();
    const ctr1 = try ctr.from("alpine:latest");
    const ctr2 = try ctr1.withExec(&.{ "echo", "hello from zig" });

    const out = try ctr2.stdout();
    defer gpa.free(out);
    std.debug.print("{s}", .{out});
}
```

Run under a Dagger session:

```bash
dagger run -- zig build run-first-pipeline
```

## Authoring a Dagger module in Zig

```zig
const std = @import("std");
const dagger = @import("dagger_sdk");

const MyModule = struct {
    pub fn build(
        self: *const MyModule,
        ctx: *dagger.module.Context,
        source: dagger.Directory,
    ) !dagger.Container {
        _ = self;
        return ctx.dag().container()
            .from("golang:1.23-alpine")
            .withDirectory("/src", source)
            .withWorkdir("/src")
            .withExec(&.{ "go", "build", "./..." });
    }

    pub fn @"test"(
        self: *const MyModule,
        ctx: *dagger.module.Context,
        source: dagger.Directory,
    ) ![]const u8 {
        _ = self;
        const ctr = try ctx.dag().container()
            .from("golang:1.23-alpine")
            .withDirectory("/src", source)
            .withWorkdir("/src")
            .withExec(&.{ "go", "test", "./..." });
        return ctr.stdout();
    }
};

pub fn main(init: std.process.Init) !void {
    return dagger.module.serve(init, MyModule{});
}
```

Your `dagger.json`:

```json
{
  "name": "my-pipeline",
  "sdk": "github.com/MChorfa/dagger-zig/sdk@v0.2.1",
  "source": "."
}
```

Then:

```bash
dagger develop              # runs codegen, emits internal/dagger/dagger.gen.zig
dagger call build --arg-0 .
dagger call test --arg-0 . | less
```

## Parallel pipelines

Zig 0.16's `std.Io` interface is threaded everywhere. `Io.Group` runs
concurrent pipelines that genuinely share caches:

```zig
const group = try io.group();
const f1 = try io.async(buildPlatform, .{ &client, io, "linux/amd64" });
const f2 = try io.async(buildPlatform, .{ &client, io, "linux/arm64" });
const f3 = try io.async(buildPlatform, .{ &client, io, "darwin/arm64" });
try group.join(.{ f1, f2, f3 });
```

See `examples/parallel/main.zig` for the full example.

## C and Python

```bash
zig build c-lib              # → zig-out/lib/libdagger.{a,so}
zig build run-hello-c        # → builds and runs the C example
```

```python
import cffi
ffi = cffi.FFI()
# See examples/c-client/hello.py for full bindings.
```

## SPIFFE (Experimental)

SPIFFE support is experimental and disabled by default. Build with:

```bash
zig build -Dspiffe-experimental
```

```zig
const spiffe = dagger.spiffe;

var shell = try spiffe.ShelloutSource.init(gpa, io, .{
    .expected_trust_domain = "MChorfa.internal",  // hard-fail if agent lies
}, null);
defer shell.deinit();

const src = shell.source();
var svid = try src.fetchX509SVID(gpa);
defer svid.deinit();
```

For registry auth (mount a short-lived credential into a Container):

```zig
const integ = dagger.spiffe_integration;  // opt-in: adds Dagger dep

const authed = try integ.spiffeRegistryAuth(ctr, &client, src, .{
    .registry = "registry.internal",
    .vault_addr = "https://vault.internal",
    .vault_role = "dagger-zig-ci",
});
```

## Build targets

```shell
zig build                    build the library module
zig build -Dspiffe-experimental   enable experimental SPIFFE support
zig build test               offline unit tests (all subsystems)
zig build test-module        offline module-runtime comptime E2E
zig build test-integration   live-engine tests (run under `dagger run --`)
zig build codegen            regenerate src/gen.zig from engine schema
zig build c-lib              build libdagger{.a,.so,.dylib} + headers
zig build run-first-pipeline  example: alpine echo hello
zig build run-build-app      example: cache volume chain
zig build run-parallel       example: Io.Group concurrent pipelines
zig build run-hello-c        example: C client via FFI
```

## Repository layout

```shell
src/
├── root.zig            Public surface — dagger.connect, Client, types
├── querybuilder.zig    Lazy Selection chain → GraphQL serializer
├── gen_sample.zig      Hand-written API (Container/Directory/File/Secret/…)
├── module_api.zig      Engine APIs used only by the module runtime
├── errors.zig          Four error sets
├── c_api.zig           C FFI layer
├── async.zig           Concurrent operations and QueryGroup
├── tracing.zig         OpenTelemetry-compatible tracing
├── platform.zig        Platform abstractions (sockets, async I/O)
├── core/               connect_params, config, graphql_client, cli_session
├── module/             Module authoring (typedef, dispatch, serde, server)
└── spiffe/             SPIFFE ID parsing, SVID types, Workload API client
codegen/                Introspection-based bindings emitter
ci/                     Self-hosting CI module (Zig Dagger module)
sdk/                    Module SDK interface (Go shim — the bootstrap layer)
examples/               first-pipeline, build-app, parallel, c-client
tests/                  integration (live engine) + module_e2e (offline)
docs/                   Comprehensive documentation (see docs/README.md)
```

## Design choices and why

**Zero external Zig dependencies.** If the Zig stdlib covers it, we use
the stdlib. HTTP, JSON, subprocess, TLS, sockets — all stdlib. Keeps
air-gap deployments trivial and breaks exactly once per Zig release
(at the language level, which we'd hit anyway).

**Zig 0.16 minimum.** We could have shipped on 0.15.1 and avoided the
0.16 migration, but `std.Io.async` + `Io.Group` make concurrent
pipelines idiomatic. Worth the bump.

**Arena-scoped selection chains.** Every `Selection` node lives in the
client's arena. Freed wholesale on `client.close()`. No Arc, no
refcounting, no "who frees what?" debates. The tradeoff: you can't
hand a `Container` to a thread that outlives the client. That's
rarely what you want anyway — handles represent engine state.

**`self: *const Self` for module methods.** Mutation during dispatch is
almost always a bug. Immutable receivers also let the dispatcher
safely parallelise. If you need mutation, wrap state in a pointer
field.

**Meta-SDK in Go.** The `sdk/` directory is written in Go because it's
the bootstrap layer — the code the engine loads to make Zig modules
possible in the first place. Writing it in Zig would be a
chicken-and-egg problem. Everything ABOVE the bootstrap (library, CI,
user modules) is Zig. See `sdk/main.go` for the ~200-line shim and
`sdk/runtime/README.md` for the container contract.

## Development & CI Testing

### Local Development

```bash
# Build and test
make build      # Build the SDK
make test       # Run all tests
make lint       # Check formatting
make bench      # Run benchmarks

# Format code
make fmt
```

### Local CI Testing (with act)

Test GitHub Actions workflows locally before pushing:

```bash
# Setup
brew install act                    # macOS
cp .env.local.example .env.local    # Configure environment

# Test workflows locally
make ci-local           # Run CI workflow
make security-local     # Run security scanning
make multi-arch-local   # Test cross-compilation
make workflow-lint      # Validate syntax
```

See [`docs/local-ci-testing.md`](docs/local-ci-testing.md) for detailed setup.

## Documentation

All documentation is in [`docs/`](docs/).

| Document                                             | Purpose                                     |
| ---------------------------------------------------- | ------------------------------------------- |
| [`docs/README.md`](docs/README.md)                   | Documentation index and quick reference     |
| [`docs/getting-started.md`](docs/getting-started.md) | Your first dagger-zig project               |
| [`docs/async-patterns.md`](docs/async-patterns.md)   | Concurrent operations guide (v0.3.0)        |
| [`docs/tracing.md`](docs/tracing.md)                 | Distributed tracing guide                   |
| [`docs/architecture.md`](docs/architecture.md)       | Design rationale and internal mechanics     |
| [`docs/roadmap.md`](docs/roadmap.md)                 | Version planning and feature timeline       |
| [`docs/spiffe.md`](docs/spiffe.md)                   | SPIFFE workload identity (experimental)     |
| [`SECURITY.md`](SECURITY.md)                         | Security policy and vulnerability reporting |
| [`docs/compliance.md`](docs/compliance.md)           | SOC2/ISO27001 compliance mappings           |

## CI Setup Required

⚠️ **Before CI will pass**, you need to configure these secrets in GitHub:

- `DAGGER_CLOUD_TOKEN` — Optional, for Dagger Cloud tracing
- `FOSSA_API_KEY` — For license scanning (optional)
- `GITLEAKS_LICENSE` — For secret scanning (optional)

The workflows will run but some jobs may skip if secrets are missing.

## Dagger Integration

This SDK is a **Community SDK** for [Dagger](https://dagger.io). It follows the official Dagger SDK patterns
and integrates with the Dagger Engine.

### Dagger Resources

- 🌐 **Website**: [dagger.io](https://dagger.io)
- 📚 **Documentation**: [docs.dagger.io](https://docs.dagger.io)
- 💻 **GitHub**: [github.com/dagger/dagger](https://github.com/dagger/dagger)
- 🎓 **SDKs**: [docs.dagger.io/sdk](https://docs.dagger.io/sdk)
- 💬 **Discord**: [discord.gg/dagger](https://discord.gg/dagger)
- 🐦 **Twitter**: [@dagger_io](https://twitter.com/dagger_io)

### Official Dagger SDKs

- [Go SDK](https://github.com/dagger/dagger/tree/main/sdk/go)
- [Python SDK](https://github.com/dagger/dagger/tree/main/sdk/python)
- [TypeScript SDK](https://github.com/dagger/dagger/tree/main/sdk/typescript)
- [Rust SDK](https://github.com/kpenfound/dagger-rust-sdk)

This Zig SDK aims to be proposed as an official community SDK once it reaches v1.0.

## License

Apache-2.0. See `LICENSE`.
