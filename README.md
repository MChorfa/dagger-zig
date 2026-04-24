# dagger-zig

A Zig SDK for the [Dagger](https://dagger.io) programmable CI/CD engine.

> **Status:** v0.1.0-RC. Compiled and tested with Zig 0.16.  
> **Enterprise Ready:** SLSA Level 4, Sigstore signing, SOC2/ISO27001 compliant

Zero external dependencies. Zig stdlib only. Authored against Zig 0.16.0
so pipelines can use `std.Io.async` + `Io.Group` for genuinely parallel
container operations — no manual threadpool, no event loop to pick.

## What works in v0.1.0

- **Client API.** `dagger.connect(gpa, io, .{})` → query containers,
  directories, files, secrets, cache volumes. Chain `.from().withExec()
  .stdout()` the way you would in any other SDK.
- **CLI session lifecycle.** Resolves via three-tier handshake: env vars
  from `dagger run --` → `_EXPERIMENTAL_DAGGER_CLI_BIN` path → `dagger`
  on `$PATH`. Never auto-downloads the CLI.
- **Module authoring.** Write a Zig struct, give it methods, expose to
  Dagger with `dagger.module.serve(init, MyModule{})`. Comptime
  reflection maps Zig types to Dagger `TypeDef` values automatically;
  unmappable signatures fail at `zig build`, not at engine-dispatch.
- **C ABI.** `zig build c-lib` produces `libdagger.{a,so,dylib}` plus
  headers. Call from C, Python (via cffi), or any language with FFI.
- **SPIFFE/SPIRE workload identity.** `ShelloutSource` backend (via
  `spire-agent api fetch`) is the working backend; `NativeWorkloadAPISource`
  ships as a type-complete skeleton for v0.1.1 — user code written today
  upgrades to v0.1.1 with a dependency bump, no source changes.
- **Self-hosting CI.** This repo's own CI pipeline is in `ci/main.zig` —
  a Zig Dagger module that uses dagger-zig to build dagger-zig.

## What's explicitly deferred to v0.1.1

- Native SPIFFE Workload API (pure Zig HTTP/2 + gRPC + protobuf). Wire spec locked at [`SPIFFE_IMPL.md`](SPIFFE_IMPL.md).
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
  "sdk": "github.com/ckodex/dagger-zig/sdk@v0.1.0",
  "source": "."
}
```

Then:

```bash
dagger develop              # runs codegen, emits internal/dagger/dagger.gen.zig
dagger call build --source=.
dagger call test --source=. | less
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

## SPIFFE

```zig
const spiffe = dagger.spiffe;

var shell = try spiffe.ShelloutSource.init(gpa, io, .{
    .expected_trust_domain = "ckodex.internal",  // hard-fail if agent lies
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
├── core/               connect_params, config, graphql_client, cli_session
├── module/             Module authoring (typedef, dispatch, serde, server)
└── spiffe/             SPIFFE ID parsing, SVID types, Workload API client
codegen/                Introspection-based bindings emitter
ci/                     Self-hosting CI module (Zig Dagger module)
sdk/                    Module SDK interface (Go shim — the bootstrap layer)
examples/               first-pipeline, build-app, parallel, c-client
tests/                  integration (live engine) + module_e2e (offline)
docs/                   ARCHITECTURE, ROADMAP, SPIFFE_IMPL
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

| Document                                       | Purpose                                     |
| ---------------------------------------------- | ------------------------------------------- |
| [`ARCHITECTURE.md`](ARCHITECTURE.md)           | Design rationale and internal mechanics     |
| [`ARCHITECTURAL_MAP.md`](ARCHITECTURAL_MAP.md) | Visual architecture overview with diagrams  |
| [`ROADMAP.md`](ROADMAP.md)                     | Version planning and feature timeline       |
| [`SPIFFE_IMPL.md`](SPIFFE_IMPL.md)             | SPIFFE Workload API implementation spec     |
| [`SECURITY.md`](SECURITY.md)                   | Security policy and vulnerability reporting |
| [`docs/compliance.md`](docs/compliance.md)     | SOC2/ISO27001 compliance mappings           |

## License

Apache-2.0. See `LICENSE`.
