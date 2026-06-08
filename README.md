<p align="center">
  <img src="assets/logo.svg" alt="dagger-zig logo" width="180" height="180">
</p>

# dagger-zig

[![Release](https://img.shields.io/github/v/release/MChorfa/dagger-zig?sort=semver)](https://github.com/MChorfa/dagger-zig/releases)
[![Powered by Dagger](https://img.shields.io/badge/Powered%20by-Dagger-131226.svg)](https://dagger.io)
[![Zig](https://img.shields.io/badge/Zig-0.16-f7a41d.svg)](https://ziglang.org)
[![CI](https://github.com/MChorfa/dagger-zig/actions/workflows/ci.yml/badge.svg)](https://github.com/MChorfa/dagger-zig/actions/workflows/ci.yml)
[![OpenSSF Scorecard](https://api.securityscorecards.dev/projects/github.com/MChorfa/dagger-zig/badge)](https://securityscorecards.dev/viewer/?uri=github.com/MChorfa/dagger-zig)
[![SLSA Build L3](https://img.shields.io/badge/SLSA-Build%20L3-2ea44f.svg)](https://slsa.dev)
[![Sigstore](https://img.shields.io/badge/Sigstore-signed-2ea44f.svg)](https://sigstore.dev)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

A native Zig SDK for the [Dagger](https://dagger.io) programmable CI/CD engine — **zero external dependencies**, Zig stdlib only, built against Zig 0.16.

> **Status — v0.3.1.** Synchronous client, module authoring, and tracing on Linux/macOS. Windows and broader async are planned ([what works](#what-works)).
>
> **Dogfooded.** dagger-zig builds, tests, and releases *itself* — the CI pipeline in [`ci/`](ci/) is a Dagger module written in Zig with this very SDK.
>
> **Supply chain.** Tagged releases ship SBOMs (CycloneDX + SPDX), keyless [Sigstore](https://sigstore.dev) signatures, and [SLSA](https://slsa.dev) Build **Level 3** provenance. This is an open-source SDK, **not a certified product** — see [docs/compliance.md](docs/compliance.md).

## What works

- **Client API** — synchronous Dagger API for Linux/macOS: containers, directories, files, secrets, cache volumes, services, git. Chained the way you'd expect from any SDK.
- **Module authoring** — write a Zig struct with methods, expose it with `dagger.module.serve(...)`. Comptime reflection maps Zig types to Dagger `TypeDef`s; unmappable signatures fail at `zig build`, not at engine dispatch.
- **Tracing** — OpenTelemetry-compatible spans via `dagger.tracing`.
- **CLI session lifecycle** — three-tier handshake (`dagger run --` env → `_EXPERIMENTAL_DAGGER_CLI_BIN` → `dagger` on `$PATH`). Never auto-downloads the CLI.
- **SPIFFE/SPIRE (experimental)** — build with `-Dspiffe-experimental`; the `spire-agent` shellout backend works, the native Workload API is a typed skeleton. See [docs/spiffe.md](docs/spiffe.md).
- **Self-hosting CI** — the full pipeline (build, test, scan, docs, release) is a Zig Dagger module.

## Planned

Async patterns (`dagger.async`), full Windows support, the C ABI (`zig build c-lib`), the native SPIFFE Workload API, and per-module codegen are typed or skeletoned but currently disabled to avoid `error.NotImplemented` paths. See [docs/roadmap.md](docs/roadmap.md).

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

    const out = try client.dag().container()
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
};

pub fn main(init: std.process.Init) !void {
    return dagger.module.serve(init, MyModule{});
}
```

```json
{
  "name": "my-pipeline",
  "sdk": "github.com/MChorfa/dagger-zig/sdk@v0.3.1",
  "source": "."
}
```

```bash
dagger develop                 # codegen → internal/dagger/dagger.gen.zig
dagger call build --arg-0 .
```

More examples: [parallel pipelines](examples/parallel/main.zig) (`Io.Group`), the [C/Python FFI](examples/c-client/), and [SPIFFE registry auth](docs/spiffe.md).

## Verifying a release

Every tagged release is signed and carries SLSA Build L3 provenance:

```bash
scripts/release-verify.sh v0.3.1     # slsa-verifier + gh attestation + cosign, all tarballs
```

The individual `slsa-verifier` / `gh attestation verify` / `cosign verify-blob` commands are in [docs/compliance.md](docs/compliance.md).

## Build targets

```shell
zig build                          build the library module
zig build -Dspiffe-experimental    enable experimental SPIFFE support
zig build test                     offline unit tests (all subsystems)
zig build test-integration         live-engine tests (under `dagger run --`)
zig build codegen                  regenerate src/gen.zig from engine schema
zig build run-first-pipeline       example: alpine echo hello
zig build run-parallel             example: Io.Group concurrent pipelines
```

## Repository layout

```shell
src/        Public surface, query builder, types, tracing, async, C FFI, module/, spiffe/
ci/         Self-hosting CI — a Zig Dagger module that builds dagger-zig with dagger-zig
sdk/        Module SDK interface (Go shim — the bootstrap layer)
codegen/    Introspection-based bindings emitter
examples/   first-pipeline, build-app, parallel, c-client
tests/      integration (live engine) + module_e2e (offline)
docs/       Documentation (see docs/README.md)
scripts/    Local CI + release verification helpers
```

## Design notes

- **Zero external Zig dependencies** — stdlib only (HTTP, JSON, TLS, sockets, subprocess). Air-gap deployments stay trivial.
- **Arena-scoped selection chains** — every handle lives in the client's arena, freed wholesale on `client.close()`. No refcounting; handles don't outlive the client.
- **Immutable module receivers** (`self: *const Self`) — mutation during dispatch is almost always a bug, and immutability lets the dispatcher parallelize safely.
- **Go bootstrap** — `sdk/` is a ~200-line Go shim, the chicken-and-egg layer the engine loads to make Zig modules possible. Everything above it (library, CI, user modules) is Zig.

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

## Contributing & local CI

```bash
make build && make test            # build + run tests
make fmt && make lint              # format + lint
```

Test the GitHub Actions workflows locally with [`act`](https://github.com/nektos/act) — see [docs/local-ci-testing.md](docs/local-ci-testing.md). Optional CI secrets (`DAGGER_CLOUD_TOKEN`, `FOSSA_API_KEY`, `GITLEAKS_LICENSE`) let extra jobs run; they skip cleanly if unset.

## About

A community SDK for [Dagger](https://dagger.io), following the official SDK patterns and engine contract. The goal is to propose it as an official community SDK at v1.0.
Dagger: [website](https://dagger.io) · [docs](https://docs.dagger.io) · [SDKs](https://docs.dagger.io/sdk) · [Discord](https://discord.gg/dagger).

## License

Apache-2.0 — see [LICENSE](LICENSE).
