//! Offline micro-benchmarks for dagger-zig hot paths that need no live engine:
//! GraphQL query construction (Selection chain -> string) and input string
//! serialization.
//!
//!   zig build bench
//!
//! Engine-dependent benchmarks (container pulls, exec latency) require a
//! running Dagger engine and are not implemented yet. Built-in flamegraph
//! output is intentionally not provided — capture a CPU profile with an
//! external sampling profiler instead, e.g. `samply record -- zig build bench`.
const std = @import("std");
const dagger = @import("dagger_sdk");
const qb = dagger.querybuilder;

const ITERATIONS: usize = 100_000;

const Stats = struct { min_ns: u64, avg_ns: u64, p95_ns: u64, p99_ns: u64, max_ns: u64 };

fn stats(samples: []u64) Stats {
    std.mem.sort(u64, samples, {}, std.sort.asc(u64));
    var sum: u128 = 0;
    for (samples) |s| sum += s;
    return .{
        .min_ns = samples[0],
        .avg_ns = @intCast(sum / samples.len),
        .p95_ns = samples[(samples.len * 95) / 100],
        .p99_ns = samples[(samples.len * 99) / 100],
        .max_ns = samples[samples.len - 1],
    };
}

fn us(ns: u64) f64 {
    return @as(f64, @floatFromInt(ns)) / std.time.ns_per_us;
}

fn report(name: []const u8, s: Stats) void {
    std.debug.print(
        "  {s:<24} min {d:>7.3}  avg {d:>7.3}  p95 {d:>7.3}  p99 {d:>7.3}  max {d:>7.3}  (us)\n",
        .{ name, us(s.min_ns), us(s.avg_ns), us(s.p95_ns), us(s.p99_ns), us(s.max_ns) },
    );
}

// `.awake` is the monotonic clock (excludes time the system is suspended):
// Linux CLOCK_MONOTONIC, macOS CLOCK_UPTIME_RAW. Correct choice for measuring
// elapsed CPU work — `.real` (wall clock) can jump under NTP adjustment.
fn nowNs(io: std.Io) u64 {
    return @intCast(std.Io.Clock.now(.awake, io).toNanoseconds());
}

fn benchQueryBuild(io: std.Io, gpa: std.mem.Allocator, samples: []u64) !void {
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    for (samples) |*slot| {
        _ = arena_state.reset(.retain_capacity);
        const arena = arena_state.allocator();
        const start = nowNs(io);
        const s1 = try qb.Selection.root.select(arena, "container");
        const s2 = try s1.argStr(arena, "address", "alpine:latest");
        const s3 = try s2.select(arena, "withExec");
        const s4 = try s3.select(arena, "stdout");
        const out = try s4.build(arena);
        std.mem.doNotOptimizeAway(out);
        slot.* = nowNs(io) - start;
    }
}

fn benchSerialize(io: std.Io, gpa: std.mem.Allocator, samples: []u64) !void {
    const input = "a value with \"quotes\", \\backslashes\\ and \nnewlines";
    for (samples) |*slot| {
        const start = nowNs(io);
        const out = try qb.serializeString(gpa, input);
        std.mem.doNotOptimizeAway(out);
        slot.* = nowNs(io) - start;
        gpa.free(out);
    }
}

pub fn main() !void {
    const gpa = std.heap.page_allocator;

    // Zig 0.16 routes clock access through the std.Io interface; a
    // single-threaded threaded backend is all an offline benchmark needs.
    var io_impl: std.Io.Threaded = .init_single_threaded;
    const io = io_impl.io();

    std.debug.print("=== dagger-zig offline benchmarks ({d} iterations) ===\n", .{ITERATIONS});

    const samples = try gpa.alloc(u64, ITERATIONS);
    defer gpa.free(samples);

    try benchQueryBuild(io, gpa, samples);
    report("query build (4-deep)", stats(samples));

    try benchSerialize(io, gpa, samples);
    report("serializeString", stats(samples));
}
