# Build Targets

## Library

```shell
zig build                    # build the library module
```

## Testing

```shell
zig build test               # offline unit tests (all subsystems)
zig build test-module        # offline module-runtime comptime E2E
zig build test-integration   # live engine tests
```

## C Library

```shell
zig build c-lib              # libdagger.{a,so,dylib} + headers
zig build c_smoke            # C client against live engine
```

## Cross Compilation

```shell
zig build matrix             # cross-compile (5 targets)
```

## Supply Chain

```shell
zig build sbom               # CycloneDX via syft
zig build slsa               # SLSA v1.0 provenance
```

## CI Pipeline

```shell
zig build ci                 # full pipeline (lint->test->c_lib->c_smoke)
```

Or with Dagger:

```shell
dagger call -m ./ci/full full-pipeline --arg-0 .
```

## Development

```shell
zig build run-first-pipeline     # run basic example
zig build run-parallel             # run parallel build example
zig build codegen                # regenerate API from schema
```
