const std = @import("std");
const dagger = @import("dagger_sdk");

// No official Zig image exists on Docker Hub; install the toolchain on Alpine
// (same approach as the Dagger Zig SDK runtime). `uname -m` matches Zig's
// release archive arch naming (x86_64/aarch64).
const zig_install =
    \\set -e
    \\ARCH=$(uname -m)
    \\curl -fL "https://ziglang.org/download/0.16.0/zig-${ARCH}-linux-0.16.0.tar.xz" | tar -xJ -C /usr/local
    \\ln -sf "/usr/local/zig-${ARCH}-linux-0.16.0/zig" /usr/local/bin/zig
;

/// Test module: conformance tests, benchmarks with caching
pub const Test = struct {
    /// zigBase provisions Alpine + the Zig toolchain with a build cache mounted.
    fn zigBase(ctx: *dagger.Context) !dagger.Container {
        var base = try ctx.container();
        base = try base.from("alpine:3.20", null);
        base = try base.withExec(&.{ "apk", "add", "--no-cache", "curl", "tar", "xz" }, null, null, null, null, null, null, null, null, null, null);
        base = try base.withExec(&.{ "sh", "-c", zig_install }, null, null, null, null, null, null, null, null, null, null);
        var zig_cache = try ctx.dag().cacheVolume("zig-build-cache", null, null, null);
        var zig_cache_id = try zig_cache.id();
        defer zig_cache_id.deinit(ctx.allocator());
        base = try base.withMountedCache("/root/.cache/zig", zig_cache_id.value, null, null, null, null);
        return base;
    }
    /// nativeZigBuild runs Zig native tests with layer caching
    /// Implements Layer Caching: zig build artifacts cached between runs
    pub fn nativeZigBuild(
        ctx: *dagger.Context,
        source: dagger.Directory,
    ) !dagger.File {
        var source_id = try source.id();
        defer source_id.deinit(ctx.allocator());

        var tester = try zigBase(ctx);
        tester = try tester.withDirectory("/src", source_id.value, null, null, null, null, null, null);
        tester = try tester.withWorkdir("/src", null);

        // Run the offline unit tests (no Dagger engine exists inside this
        // container, so the live integration suite cannot run here). Capture
        // output to a log and echo it, but propagate the real exit code so a
        // genuine test failure fails the pipeline (no silent suppression).
        tester = try tester.withExec(&.{
            "sh",
            "-c",
            "mkdir -p /src/zig-out; zig build test -Doptimize=ReleaseSafe > /src/zig-out/test.log 2>&1; rc=$?; cat /src/zig-out/test.log; exit $rc",
        }, null, null, null, null, null, null, null, null, null, null);

        return tester.file("/src/zig-out/test.log", null);
    }

    /// benchmark runs the offline `zig build bench` step (query-builder and
    /// string serialization micro-benchmarks; no live engine required).
    pub fn benchmark(
        ctx: *dagger.Context,
        source: dagger.Directory,
    ) !dagger.Directory {
        var source_id = try source.id();
        defer source_id.deinit(ctx.allocator());

        var bencher = try zigBase(ctx);
        bencher = try bencher.withDirectory("/src", source_id.value, null, null, null, null, null, null);
        bencher = try bencher.withWorkdir("/src", null);

        // Capture output and tolerate failure so the returned directory always
        // exists even if the bench binary fails — the artifact upload is
        // best-effort, not a gate.
        bencher = try bencher.withExec(&.{
            "sh",
            "-c",
            "mkdir -p /src/zig-out/benches; zig build bench > /src/zig-out/benches/output.log 2>&1 || true",
        }, null, null, null, null, null, null, null, null, null, null);

        return bencher.directory("/src/zig-out/benches", null);
    }

    /// runAll orchestrates tests and benchmarks in parallel
    /// Implements Parallel Execution: independent test suites run concurrently
    pub fn runAll(
        ctx: *dagger.Context,
        source: dagger.Directory,
    ) !dagger.Directory {
        var results = try ctx.container();
        results = try results.from("alpine:latest", null);

        const test_output = try nativeZigBuild(ctx, source);
        const bench_output = try benchmark(ctx, source);

        var test_id = try test_output.id();
        defer test_id.deinit(ctx.allocator());
        var bench_dir_id = try bench_output.id();
        defer bench_dir_id.deinit(ctx.allocator());

        results = try results.withFile("/test-output.log", test_id.value, null, null, null);
        results = try results.withDirectory("/benchmarks", bench_dir_id.value, null, null, null, null, null, null);

        return results.directory("/", null);
    }
};
