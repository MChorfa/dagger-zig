<p align="center">
  <img src="assets/logo.svg" alt="dagger-zig logo" width="160" height="160">
</p>

# dagger-zig Docs

A practical guide to the Zig SDK for the [Dagger](https://dagger.io) programmable CI/CD engine.

> **At a glance**
> - Zero external dependencies in the SDK itself
> - Zig 0.16 foundation
> - Synchronous client API with `std.Io.Group` fan-out
> - Offline benchmarks, release provenance, and SPIFFE support

> **Dagger links**
> [Website](https://dagger.io) · [Docs](https://docs.dagger.io) · [GitHub](https://github.com/dagger/dagger) · [Discord](https://discord.gg/dagger)

## Read This First

This docs set is arranged in the order most people need it:

| Path | Use it for |
| --- | --- |
| [Getting Started](getting-started.md) | First build, first client, local setup |
| [Examples](examples.md) | Copyable end-to-end snippets |
| [Build Guide](build.md) | Build flags, tests, and release commands |
| [Client API](api-reference.md) | Core SDK surface area |
| [Module Authoring](module-authoring.md) | Exposing Zig structs as Dagger modules |
| [Async Patterns](async-patterns.md) | Parallel fan-out with `std.Io.Group` and `Client.branch()` |
| [Compliance](compliance.md) | What the release pipeline actually ships |
| [Observability](observability.md) | Tracing, logs, metrics, and health checks |

## Design Principles

| Principle | Meaning |
| --- | --- |
| Small surface | Keep the public API synchronous and predictable |
| Explicit state | Branch per concurrent task instead of sharing mutable clients |
| Honest docs | Mark experimental and deferred pieces clearly |
| Build-proof releases | Separate build artifacts from release attestations |
| Local-first validation | Prefer offline checks and reproducible commands |

## What Is Stable

| Area | Status | Notes |
| --- | --- | --- |
| Client SDK | Ready | POSIX, synchronous, zero third-party runtime deps |
| Module authoring | Ready | Compile-time type mapping with early failures |
| Parallel fan-out | Ready | `dagger.parallel` + `Client.branch()` |
| Tracing | Ready | OpenTelemetry-compatible spans |
| Release provenance | Ready | SLSA L3 + GitHub attestation + cosign on tagged releases |

## What Is Experimental

| Area | Status | Notes |
| --- | --- | --- |
| SPIFFE/SPIRE | Experimental | Shellout backend works; native workload API remains a skeleton |
| Windows support | Planned | POSIX is the shipped baseline |
| C ABI | Planned | Not yet promoted to the primary path |

## Where To Go Next

1. [Getting Started](getting-started.md) if you want a first successful call.
2. [Examples](examples.md) if you want copyable patterns.
3. [Compliance](compliance.md) if you care about release provenance and signing.
4. [Roadmap](roadmap.md) if you want to see what is still deferred.
