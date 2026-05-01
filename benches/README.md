# Performance Benchmarks

This directory contains performance benchmarks for the dagger-zig SDK.

## Running Benchmarks

### Local Development

```bash
# Run all benchmarks
zig build bench

# Run specific benchmark
zig build bench --container-ops

# With Dagger engine (for real operation benchmarks)
dagger run zig build bench
```

### CI

Benchmarks run automatically on every PR and release via `.github/workflows/benchmark.yml`.

Results are tracked in `gh-pages` branch for trend analysis.

## Benchmark Categories

| Category        | File                  | Description                                |
| --------------- | --------------------- | ------------------------------------------ |
| Container Ops   | `container_ops.zig`   | Image pulls, file operations, exec latency |
| Module Dispatch | `module_dispatch.zig` | Comptime reflection, function routing      |
| Serialization   | `serialization.zig`   | GraphQL query building, JSON parsing       |
| Memory          | `memory.zig`          | Allocator performance, heap usage          |

## Metrics

All benchmarks report:

- **iterations**: Number of samples collected
- **min/max**: Fastest and slowest execution
- **avg**: Mean execution time
- **p95/p99**: 95th and 99th percentiles (latency-sensitive)
- **throughput**: Operations per second (where applicable)

## Interpreting Results

### Target Performance (v0.1.0)

| Operation           | Target Latency | Notes                |
| ------------------- | -------------- | -------------------- |
| Container.from()    | < 500ms        | Image already cached |
| File.contents()     | < 50ms         | Small files (< 1MB)  |
| Directory.entries() | < 100ms        | Standard directories |
| Container.exec()    | < 200ms        | Simple commands      |
| Module dispatch     | < 1μs          | Comptime overhead    |

### Regression Detection

CI compares benchmarks against `main` branch:

- **PASS**: Within 10% of baseline
- **WARN**: 10-25% slower (flagged for review)
- **FAIL**: > 25% slower (blocks merge)

## Profiling

```bash
# CPU profiling
zig build bench -- -p cpu

# Memory profiling
zig build bench -- -p heap

# Export flamegraph
zig build bench -- -f flamegraph.svg
```

## Adding New Benchmarks

1. Create new file in `benches/` directory
2. Implement benchmark functions using `BenchResult` struct
3. Register in `bench_runner.zig`
4. Update this README

Example:

```zig
const std = @import("std");
const dagger = @import("dagger_sdk");

fn myBenchmark(allocator: std.mem.Allocator, ctx: *dagger.Context) !BenchResult {
    var samples = try allocator.alloc(u64, 100);
    defer allocator.free(samples);

    for (0..100) |i| {
        const start = std.time.nanoTimestamp();
        // ... benchmark code ...
        const end = std.time.nanoTimestamp();
        samples[i] = @intCast(end - start);
    }

    return BenchResult.fromSamples("my.benchmark", samples);
}
```
