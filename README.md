<p align="center">
  <img src="assets/logo.svg" alt="dagger-zig logo" width="160" height="160">
</p>

<h1 align="center">dagger-zig</h1>

<p align="center">
  <strong>A native Zig SDK for the <a href="https://dagger.io">Dagger</a> programmable CI/CD engine.</strong>
</p>

<p align="center">
  <a href="https://github.com/MChorfa/dagger-zig/releases"><img src="https://img.shields.io/github/v/release/MChorfa/dagger-zig?sort=semver" alt="Release"></a>
  <a href="https://dagger.io"><img src="https://img.shields.io/badge/Powered%20by-Dagger-131226.svg" alt="Powered by Dagger"></a>
  <a href="https://ziglang.org"><img src="https://img.shields.io/badge/Zig-0.16-f7a41d.svg" alt="Zig"></a>
  <a href="https://github.com/MChorfa/dagger-zig/actions/workflows/ci.yml"><img src="https://github.com/MChorfa/dagger-zig/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <br>
  <a href="https://securityscorecards.dev/viewer/?uri=github.com/MChorfa/dagger-zig"><img src="https://api.securityscorecards.dev/projects/github.com/MChorfa/dagger-zig/badge" alt="OpenSSF Scorecard"></a>
  <a href="https://slsa.dev"><img src="https://img.shields.io/badge/SLSA-Build%20L3-2ea44f.svg" alt="SLSA Build L3"></a>
  <a href="https://sigstore.dev"><img src="https://img.shields.io/badge/Sigstore-signed-2ea44f.svg" alt="Sigstore"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-Apache%202.0-blue.svg" alt="License"></a>
</p>

---

The SDK is **Zig stdlib only**, built against Zig 0.16. It gives you a synchronous Dagger client, module authoring with comptime type reflection, and concurrent fan-out via `std.Io.Group` + `Client.branch()`.

| | |
| --- | --- |
| **Status** | v0.3.5 — POSIX-ready, self-hosting CI, release provenance |
| **Self-hosting** | The pipeline in [`ci/`](ci/) is a Zig Dagger module built with this SDK |
| **Supply chain** | SBOMs, Sigstore signatures, SLSA Build L3 provenance — see [docs/compliance.md](docs/compliance.md) |

## Quick start

Run a container in ~30 lines:

```zig
const std = @import("std");
const dagger = @import("dagger_sdk");

pub fn main() !void {
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var io_impl: std.Io.Threaded = .init(gpa, .{});
    defer io_impl.deinit();
    const io = io_impl.io();

    var client = try dagger.connect(gpa, io, .{});
    defer client.close();

    const out = try client.dag()
        .container()
        .from("alpine:latest")
        .withExec(&.{ "echo", "hello from zig" })
        .stdout();
    defer gpa.free(out);

    std.debug.print("{s}", .{out});
}
```

```bash
dagger run -- zig build run-first-pipeline
```

## What works

| Feature | What you get |
| --- | --- |
| **Client API** | Synchronous Dagger API for Linux/macOS: containers, directories, files, secrets, cache volumes, services, git |
| **Module authoring** | Expose a Zig struct with `dagger.module.serve(...)`. Comptime reflection maps types to Dagger `TypeDef`s; unmappable signatures fail at `zig build` |
| **Concurrent fan-out** | `dagger.parallel` over `std.Io.Group` with `Client.branch()` per task. See [examples/parallel](examples/parallel/main.zig) |
| **Tracing** | OpenTelemetry-compatible spans via `dagger.tracing` |
| **CLI lifecycle** | Three-tier handshake: `dagger run --` env → `_EXPERIMENTAL_DAGGER_CLI_BIN` → `dagger` on `$PATH`. No auto-downloads |
| **SPIFFE/SPIRE** | Experimental shellout backend; build with `-Dspiffe-experimental`. See [docs/spiffe.md](docs/spiffe.md) |
| **Self-hosting CI** | Build, test, scan, docs, and release pipeline as a Zig Dagger module |

## Planned

Windows support, the C ABI (`zig build c-lib`), the native SPIFFE Workload API, and per-module codegen are typed or skeletoned but disabled to avoid `error.NotImplemented` paths. See [docs/roadmap.md](docs/roadmap.md).

## Author a Dagger module in Zig

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
        return try ctx.container()
            .from("golang:1.23-alpine")
            .withDirectory("/src", source)
            .withWorkdir("/src")
            .withExec(&.{ "go", "build", "./..." });
    }
};

pub fn main(init: std.process.Init) !void {
    return dagger.module.serve(init, MyModule{});
}
```

```json
{
  "name": "my-pipeline",
  "sdk": "github.com/MChorfa/dagger-zig/sdk@v0.3.5",
  "source": "."
}
```

```bash
dagger develop                 # codegen → build.zig + build.zig.zon + internal/dagger/dagger.gen.zig
dagger call build --source=.
```

More examples: [parallel pipelines](examples/parallel/main.zig), [C/Python FFI](examples/c-client/), [SPIFFE registry auth](docs/spiffe.md), and the [e2e module](examples/e2e-module/).

## Build targets

| Command | Purpose |
| --- | --- |
| `zig build` | Build the library and module targets |
| `zig build -Dspiffe-experimental` | Enable experimental SPIFFE support |
| `zig build test` | Offline unit tests |
| `zig build test-module` | Module-runtime comptime plumbing check |
| `zig build test-suite` | Comprehensive suite (platform, telemetry, perf) |
| `zig build test-integration` | Live-engine tests (requires `dagger run --`) |
| `zig build bench` | Offline benchmarks (query builder, serialization) |
| `zig build flamegraph` | CPU flamegraph SVG via external profiler |
| `zig build codegen` | Regenerate `src/gen.zig` from engine schema |
| `zig build run-first-pipeline` | Example: alpine echo hello |
| `zig build run-parallel` | Example: Io.Group concurrent pipelines |

## Repository layout

```
src/        Public surface: query builder, types, tracing, parallel, C FFI, module/, spiffe/
ci/         Self-hosting CI — a Zig Dagger module
sdk/        Module SDK interface (Go bootstrap shim)
codegen/    Introspection-based bindings emitter
examples/   first-pipeline, build-app, parallel, c-client
tests/      integration (live engine) + module_e2e (offline)
docs/       Documentation (see docs/README.md)
scripts/    Local CI + release verification helpers
```

## Design notes

- **Zero external Zig dependencies** — stdlib only (HTTP, JSON, TLS, sockets, subprocess). Air-gap deployments stay trivial.
- **Arena-scoped selection chains** — every handle lives in the client's arena, freed wholesale on `client.close()`.
- **Immutable module receivers** (`self: *const Self`) — mutation during dispatch is almost always a bug; immutability lets the dispatcher parallelize safely.
- **Go bootstrap** — `sdk/` is the ~200-line engine-facing shim. Everything above it is Zig.

## Documentation

Full docs live in [`docs/`](docs/):

| Document | Purpose |
| --- | --- |
| [getting-started](docs/getting-started.md) | Your first dagger-zig project |
| [module-authoring](docs/module-authoring.md) | Build Dagger modules in Zig |
| [architecture](docs/architecture.md) | Design rationale and internals |
| [tracing](docs/tracing.md) | Distributed tracing |
| [spiffe](docs/spiffe.md) | Workload identity (experimental) |
| [compliance](docs/compliance.md) | Security practices (not a certification) |
| [roadmap](docs/roadmap.md) | What's planned |

## Verifying a release

Every tagged release carries SLSA Build L3 provenance:

```bash
scripts/release-verify.sh v0.3.5
```

Individual commands are in [docs/compliance.md](docs/compliance.md).

## Contributing

```bash
make build && make test            # build + run tests
make fmt && make lint              # format + lint
```

Test GitHub Actions workflows locally with [`act`](https://github.com/nektos/act) — see [docs/local-ci-testing.md](docs/local-ci-testing.md). Optional CI secrets skip cleanly when unset.

A community SDK for [Dagger](https://dagger.io), following the official SDK patterns and engine contract.

## License

Apache-2.0 — see [LICENSE](LICENSE).
