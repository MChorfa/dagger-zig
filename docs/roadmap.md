# Roadmap

This page tracks what is shipped now, what is being hardened, and what stays
deferred.

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

## Deferred

- Full Windows support
- Native SPIFFE Workload API
- C ABI promotion
- Broader codegen and ergonomics work

## How to Read This

- If it is in `README.md` and the docs hub, it should already work.
- If it is in this page under "Being Hardened", expect follow-up work.
- If it is under "Deferred", do not rely on it for production planning yet.

## Related Pages

- [Getting Started](getting-started.md)
- [Examples](examples.md)
- [Build Guide](build.md)
- [Compliance](compliance.md)
- [Release Checklist](RELEASE_CHECKLIST.md)
