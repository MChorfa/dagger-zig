//! Container operation benchmarks
//!
//! Measures performance of core container operations:
//! - Image pulls
//! - File operations
//! - Exec latency
//! - Cache effectiveness

const std = @import("std");
const dagger = @import("dagger_sdk");

const BenchResult = struct {
    name: []const u8,
    iterations: usize,
    total_ns: u64,
    min_ns: u64,
    max_ns: u64,
    avg_ns: u64,
    p95_ns: u64,
    p99_ns: u64,

    fn fromSamples(name: []const u8, samples: []const u64) BenchResult {
        std.sort.pdq(u64, samples, {}, std.sort.asc(u64));

        var total: u64 = 0;
        var min: u64 = std.math.maxInt(u64);
        var max: u64 = 0;

        for (samples) |s| {
            total += s;
            if (s < min) min = s;
            if (s > max) max = s;
        }

        const n = samples.len;
        const p95_idx = @divFloor(n * 95, 100);
        const p99_idx = @divFloor(n * 99, 100);

        return .{
            .name = name,
            .iterations = n,
            .total_ns = total,
            .min_ns = min,
            .max_ns = max,
            .avg_ns = @divFloor(total, n),
            .p95_ns = samples[p95_idx],
            .p99_ns = samples[p99_idx],
        };
    }
};

// Benchmark: Container creation from image
fn benchContainerFrom(allocator: std.mem.Allocator, ctx: *dagger.Context) !BenchResult {
    const iterations = 10;
    var samples = try allocator.alloc(u64, iterations);
    defer allocator.free(samples);

    for (0..iterations) |i| {
        const start = std.time.nanoTimestamp();

        _ = try ctx.container().from("alpine:latest");

        const end = std.time.nanoTimestamp();
        samples[i] = @intCast(end - start);

        // Small delay between iterations
        std.time.sleep(100 * std.time.ns_per_ms);
    }

    return BenchResult.fromSamples("container.from(alpine:latest)", samples);
}

// Benchmark: File read operation
fn benchFileRead(allocator: std.mem.Allocator, ctx: *dagger.Context) !BenchResult {
    // Setup: Create a container with a file
    const container = try ctx.container()
        .from("alpine:latest")
        .withNewFile("/test.txt", "Hello, Benchmark!");

    const iterations = 50;
    var samples = try allocator.alloc(u64, iterations);
    defer allocator.free(samples);

    for (0..iterations) |i| {
        const start = std.time.nanoTimestamp();

        const file = try container.file("/test.txt");
        _ = try file.contents();

        const end = std.time.nanoTimestamp();
        samples[i] = @intCast(end - start);
    }

    return BenchResult.fromSamples("file.contents()", samples);
}

// Benchmark: Directory listing
fn benchDirectoryEntries(allocator: std.mem.Allocator, ctx: *dagger.Context) !BenchResult {
    const container = try ctx.container()
        .from("alpine:latest")
        .withExec(&.{ "apk", "add", "--no-cache", "busybox" });

    const iterations = 20;
    var samples = try allocator.alloc(u64, iterations);
    defer allocator.free(samples);

    for (0..iterations) |i| {
        const start = std.time.nanoTimestamp();

        const dir = try container.directory("/bin");
        _ = try dir.entries();

        const end = std.time.nanoTimestamp();
        samples[i] = @intCast(end - start);
    }

    return BenchResult.fromSamples("directory.entries()", samples);
}

// Benchmark: Command execution
fn benchExec(allocator: std.mem.Allocator, ctx: *dagger.Context) !BenchResult {
    const container = try ctx.container().from("alpine:latest");

    const iterations = 30;
    var samples = try allocator.alloc(u64, iterations);
    defer allocator.free(samples);

    for (0..iterations) |i| {
        const start = std.time.nanoTimestamp();

        _ = try container.withExec(&.{ "echo", "benchmark" }).stdout();

        const end = std.time.nanoTimestamp();
        samples[i] = @intCast(end - start);
    }

    return BenchResult.fromSamples("container.exec(echo)", samples);
}

// Benchmark: Cache effectiveness (second run should be faster)
fn benchCacheEffectiveness(allocator: std.mem.Allocator, ctx: *dagger.Context) !struct { cold: BenchResult, warm: BenchResult } {
    const iterations = 5;

    // Cold cache
    var cold_samples = try allocator.alloc(u64, iterations);
    defer allocator.free(cold_samples);

    for (0..iterations) |i| {
        const start = std.time.nanoTimestamp();

        // Force new container each time (cache miss)
        const container = try ctx.container()
            .from("alpine:latest")
            .withExec(&.{ "sh", "-c", "date +%s%N" });
        _ = try container.stdout();

        const end = std.time.nanoTimestamp();
        cold_samples[i] = @intCast(end - start);
    }

    // Warm cache - reuse same container reference
    const cached = try ctx.container()
        .from("alpine:latest")
        .withExec(&.{ "echo", "cached" });

    var warm_samples = try allocator.alloc(u64, iterations);
    defer allocator.free(warm_samples);

    for (0..iterations) |i| {
        const start = std.time.nanoTimestamp();
        _ = try cached.stdout();
        const end = std.time.nanoTimestamp();
        warm_samples[i] = @intCast(end - start);
    }

    return .{
        .cold = BenchResult.fromSamples("exec.cache.cold", cold_samples),
        .warm = BenchResult.fromSamples("exec.cache.warm", warm_samples),
    };
}

fn printResult(writer: anytype, result: BenchResult) !void {
    try writer.print(
        \\{s}
        \\  iterations: {d}
        \\  total: {d:.2}ms
        \\  min: {d:.2}ms, max: {d:.2}ms
        \\  avg: {d:.2}ms, p95: {d:.2}ms, p99: {d:.2}ms
        \\
    , .{
        result.name,
        result.iterations,
        @as(f64, @floatFromInt(result.total_ns)) / std.time.ns_per_ms,
        @as(f64, @floatFromInt(result.min_ns)) / std.time.ns_per_ms,
        @as(f64, @floatFromInt(result.max_ns)) / std.time.ns_per_ms,
        @as(f64, @floatFromInt(result.avg_ns)) / std.time.ns_per_ms,
        @as(f64, @floatFromInt(result.p95_ns)) / std.time.ns_per_ms,
        @as(f64, @floatFromInt(result.p99_ns)) / std.time.ns_per_ms,
    });
}

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    try stdout.print(
        \\=== Dagger-Zig Container Operations Benchmark ===
        \\
    , .{});

    // Note: These benchmarks require a running Dagger engine
    // For CI, we skip if not available

    // TODO: Initialize context - requires running Dagger engine
    // var ctx = try dagger.Context.init();
    // defer ctx.deinit();

    try stdout.print("Note: Full benchmarks require running Dagger engine\\n", .{});
    try stdout.print("Run with: dagger run zig build bench\\n\\n", .{});

    // Print benchmark structure
    try stdout.print("Planned benchmarks:\\n", .{});
    try stdout.print("  - container.from() - Image pull latency\\n", .{});
    try stdout.print("  - file.contents() - File read operations\\n", .{});
    try stdout.print("  - directory.entries() - Directory listing\\n", .{});
    try stdout.print("  - container.exec() - Command execution\\n", .{});
    try stdout.print("  - cache.effectiveness - Cold vs warm cache comparison\\n", .{});
}
