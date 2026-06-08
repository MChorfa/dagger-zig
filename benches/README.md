# Benchmarks

Offline micro-benchmarks for dagger-zig hot paths that need no live engine.

```bash
zig build bench
```

The step builds in `ReleaseFast` and runs `benches/querybuilder.zig`, which times
two hot paths over 100,000 iterations each and reports min / avg / p95 / p99 / max
in microseconds:

| Benchmark              | What it measures                                                        |
| ---------------------- | ----------------------------------------------------------------------- |
| `query build (4-deep)` | Building a 4-level GraphQL selection chain and rendering it to a string |
| `serializeString`      | Escaping a string for inclusion in a GraphQL query                      |

Example output:

```
=== dagger-zig offline benchmarks (100000 iterations) ===
  query build (4-deep)     min   0.167  avg   0.322  p95   0.458  p99   0.500  max  20.625  (us)
  serializeString          min   0.791  avg   1.109  p95   1.791  p99   2.375  max 150.292  (us)
```

Numbers are machine-dependent; use them for relative comparison across commits on
the same host, not as absolute targets.

## CI

The `benchmark` function in `ci/test/main.zig` runs `zig build bench` inside the
Dagger pipeline and captures the output as an artifact (see
`.github/workflows/benchmark.yml`). It is informational — the run is not gated on
benchmark numbers, and no automatic regression threshold is enforced.

## Profiling

There is no built-in flamegraph or profiler flag. Capture a CPU profile with an
external sampling profiler against the built binary, e.g.:

```bash
zig build bench   # builds zig-out/bin/bench
samply record -- ./zig-out/bin/bench
```

## Not implemented

Engine-dependent benchmarks (image pulls, exec latency, file/directory operations)
require a running Dagger engine and are not implemented.
