# Build Guide

The repo keeps build commands intentionally small and explicit. Use the slices
below instead of memorizing every target.

## Everyday commands

```shell
zig build                 # build the library/module targets
zig build test            # offline unit tests
zig build test-module     # module-runtime integration check
zig build codegen         # regenerate API from schema
```

## Runtime and examples

```shell
zig build run-first-pipeline
zig build run-parallel
zig build c_smoke
```

## Release and supply chain

```shell
zig build sbom
zig build slsa
scripts/release-verify.sh v0.3.5
```

The release flow produces SBOMs, GitHub attestations, SLSA provenance, and
cosign bundles at publish time. The build module can also emit provenance data
locally, but those artifacts are not what gets published to GitHub releases.

## Cross compilation

```shell
zig build matrix
```

## Dagger-backed CI

```shell
dagger call -m ./ci/pipeline run --arg-0 .
```

Use `make ci-local` or `make workflow-lint` when you want repo-preserved
operator flows instead of invoking the underlying command directly.
