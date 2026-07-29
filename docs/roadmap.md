# Roadmap

This page tracks what is shipped now, what is being hardened, and what stays
`deferred`. The path to `v1.0` is documented in [v1.0 Roadmap](v1.0-roadmap.md).

## v1.0 goal

`v1.0` means **Dagger Community SDK-ready**: a stable, documented, tested Zig SDK
that can be listed alongside the official Dagger SDKs. It does not require every
experimental feature to be complete. See [v1.0 Roadmap](v1.0-roadmap.md) for the
full plan and exit criteria.

## Shipped

- Synchronous Zig client for Dagger queries
- `Client.branch()` and `dagger.parallel` for safe fan-out
- Module authoring from Zig structs
- Tracing support via `dagger.tracing`
- Offline benchmarks and flamegraph support
- Tagged release provenance with SBOM and attestations

## Being Hardened

- Workflow simplification and CI reliability
- Docs consistency across landing pages and reference pages
- Security advisory backlog and dependency updates
- Better local verification for contributors
- Windows runtime path parity (currently builds, but some engine/session paths are less exercised)

## Deferred

- Native SPIFFE Workload API (shellout backend is the supported experimental path)
- C ABI promotion (`zig build c-lib`)
- Per-module and broader codegen ergonomics work

## How to Read This

- If it is in `README.md` and the docs hub, it should already work.
- If it is in this page under "Being Hardened", expect follow-up work.
- If it is under "Deferred", do not rely on it for production planning yet.
- If you are tracking the `v1.0` release, read [v1.0 Roadmap](v1.0-roadmap.md).

## Related Pages

- [v1.0 Roadmap](v1.0-roadmap.md)
- [Getting Started](getting-started.md)
- [Examples](examples.md)
- [Build Guide](build.md)
- [Compliance](compliance.md)
- [Release Checklist](RELEASE_CHECKLIST.md)
