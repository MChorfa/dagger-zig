![dagger-zig logo](assets/logo.svg)

# dagger-zig

[![Release](https://img.shields.io/github/v/release/MChorfa/dagger-zig?sort=semver)](https://github.com/MChorfa/dagger-zig/releases)
[![Powered by Dagger](https://img.shields.io/badge/Powered%20by-Dagger-131226.svg)](https://dagger.io)
[![Zig](https://img.shields.io/badge/Zig-0.16-f7a41d.svg)](https://ziglang.org)
[![CI](https://github.com/MChorfa/dagger-zig/actions/workflows/ci.yml/badge.svg)](https://github.com/MChorfa/dagger-zig/actions/workflows/ci.yml)
[![OpenSSF Scorecard](https://api.securityscorecards.dev/projects/github.com/MChorfa/dagger-zig/badge)](https://securityscorecards.dev/viewer/?uri=github.com/MChorfa/dagger-zig)
[![SLSA Build L3](https://img.shields.io/badge/SLSA-Build%20L3-2ea44f.svg)](https://slsa.dev)
[![Sigstore](https://img.shields.io/badge/Sigstore-signed-2ea44f.svg)](https://sigstore.dev)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

A native Zig SDK for the [Dagger](https://dagger.io) engine. The code depends only on the Zig standard library and targets Zig 0.16.

The current release is v0.3.4. It provides a synchronous client for Linux and macOS, concurrent pipelines using `std.Io.Group` and `Client.branch`, module authoring, and tracing. Windows support is planned.

The project is self-hosting. The CI pipeline in [`ci/`](ci/) is a Dagger module written in Zig with this SDK.

Tagged releases publish CycloneDX and SPDX SBOMs, Sigstore signatures, and SLSA Build Level 3 provenance. See [docs/compliance.md](docs/compliance.md).

## Supported features

* Client API on Linux and macOS for containers, directories, files, secrets, cache volumes, services, and git operations.
* Module authoring with Zig structs. Expose structs with `dagger.module.serve`. Comptime reflection maps Zig types to Dagger `TypeDef` definitions, rejecting invalid signatures at compile time instead of runtime dispatch.
* Parallel pipeline execution using `dagger.parallel` map and forEach helpers over `std.Io.Group`. Each task receives an isolated `Client.branch`. See [examples/parallel](examples/parallel/main.zig).
* OpenTelemetry compatible spans via `dagger.tracing`.
* CLI session handshake resolving the active binary from the `dagger run` environment, `_EXPERIMENTAL_DAGGER_CLI_BIN`, or system path, without background downloads.
* SPIFFE and SPIRE workload identity under `-Dspiffe-experimental`, using the `spire-agent` backend. See [docs/spiffe.md](docs/spiffe.md).
* Self-hosting pipeline where building, testing, linting, and releases run as a native Zig Dagger module.

## Planned work

Windows support, the C ABI via `zig build c-lib`, the native SPIFFE Workload API, and per-module code generation remain under active development. See [docs/roadmap.md](docs/roadmap.md).

## Quick start

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

    // Builder calls return !T. Handles evaluate lazily when reading terminal output.
    const ctr = try client.dag().container(.{});
    const alpine = try ctr.from("alpine:latest");
    const exec = try alpine.withExec(&.{ "echo", "hello from zig" }, .{});
    const out = try exec.stdout();
    defer gpa.free(out);
    std.debug.print("{s}", .{out});
}
```

```bash
dagger run -- zig build run-first-pipeline
```

## Module authoring

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
        const ctr = try ctx.container(.{});
        const based = try ctr.from("golang:1.23-alpine");
        const sourced = try based.withDirectory("/src", source, .{});
        const workdir = try sourced.withWorkdir("/src", .{});
        return workdir.withExec(&.{ "go", "build", "./..." }, .{});
    }
};

pub fn main(init: std.process.Init) !void {
    return dagger.module.serve(init, MyModule{});
}
```

```json
{
  "name": "my-pipeline",
  "sdk": "github.com/MChorfa/dagger-zig/sdk@v0.3.4",
  "source": "."
}
```

```bash
dagger develop
dagger call build --source=.
```

Additional examples include [parallel pipelines](examples/parallel/main.zig) using `Io.Group`, [C and Python FFI](examples/c-client/), [SPIFFE registry authentication](docs/spiffe.md), and the [end-to-end module](examples/e2e-module/).

## Release verification

Tagged releases include cryptographic signatures and SLSA Build Level 3 provenance:

```bash
scripts/release-verify.sh v0.3.4
```

Detailed verification steps using `slsa-verifier`, `gh attestation verify`, and `cosign verify-blob` are documented in [docs/compliance.md](docs/compliance.md).

## Build targets

```shell
zig build                          Build the library module
zig build -Dspiffe-experimental    Enable experimental SPIFFE support
zig build test                     Run offline unit tests
zig build test-module              Verify module runtime comptime types
zig build test-suite               Run complete test suite across platforms
zig build test-integration         Run integration tests against live engine
zig build bench                    Run offline query and serialization benchmarks
zig build flamegraph               Generate CPU flamegraph SVG
zig build codegen                  Regenerate bindings from engine schema
zig build run-first-pipeline       Run first container pipeline example
zig build run-parallel             Run concurrent pipeline example
```

## Repository layout

```shell
src/        Query builder, core types, tracing, parallel engine, module runtime, SPIFFE
ci/         Self-hosting CI pipeline implemented as a Zig Dagger module
sdk/        Bootstrap layer for engine communication
codegen/    Introspection bindings generator
examples/   Runnable pipeline examples
tests/      Integration tests and offline unit tests
docs/       Technical guides and specifications
scripts/    Release verification and testing scripts
```

## Architecture decisions

```mermaid
flowchart TD
    subgraph Engine["Dagger engine"]
        GraphQL["GraphQL session and container runtime"]
    end

    subgraph Bootstrap["Bootstrap layer"]
        GoEntry["Go shim sdk/main.go"]
    end

    subgraph SDK["Zig SDK runtime"]
        ModuleDispatch["Comptime module reflection"]
        QueryArena["Arena query builder"]
        ParallelPool["Parallel executor std.Io.Group"]
    end

    subgraph User["Workloads"]
        Pipelines["Container pipelines"]
        Modules["Custom modules"]
    end

    GraphQL --> GoEntry
    GoEntry --> ModuleDispatch
    ModuleDispatch --> QueryArena
    Pipelines --> QueryArena
    Modules --> ModuleDispatch
    ParallelPool --> QueryArena
    QueryArena --> GraphQL
```

* Standard library only. The SDK avoids third-party Zig packages and uses standard library HTTP, JSON, TLS, sockets, and subprocess facilities. This simplifies air-gapped deployments.
* Arena allocation for query chains. Handles allocate within the client arena and release when calling `client.close`. This eliminates reference counting overhead.
* Constant module receivers. Module functions accept `self: *const Self`. Disallowing state mutation during dispatch guarantees safe parallel invocation across concurrent engine requests.
* Go bootstrap shim. The `sdk/` directory contains a minimal Go shim required by the Dagger engine to launch external language modules. All library internals, pipelines, and user code execute entirely in Zig.

## Documentation

Comprehensive guides are in [`docs/`](docs/):

| Document | Purpose |
| --- | --- |
| [getting-started](docs/getting-started.md) | First project walkthrough |
| [module-authoring](docs/module-authoring.md) | Module development instructions |
| [architecture](docs/architecture.md) | Design rationale and internals |
| [tracing](docs/tracing.md) | Distributed tracing configuration |
| [spiffe](docs/spiffe.md) | Workload identity setup |
| [compliance](docs/compliance.md) | Security controls and provenance |
| [roadmap](docs/roadmap.md) | Planned milestones |

## Contributing

```bash
make build && make test
make fmt && make lint
```

Test GitHub Actions workflows locally with [`act`](https://github.com/nektos/act). See [docs/local-ci-testing.md](docs/local-ci-testing.md). Workflows skip optional secrets when not provided.

## Project status

`dagger-zig` is a community SDK developed according to the Dagger engine protocol. Official Dagger resources are available at [dagger.io](https://dagger.io) and [docs.dagger.io](https://docs.dagger.io).

## License

Apache 2.0. See [LICENSE](LICENSE).
