const std = @import("std");
const dagger = @import("dagger_sdk");

/// Test module: conformance tests, benchmarks with caching
pub const Test = struct {
    /// nativeZigBuild runs Zig native tests with layer caching
    /// Implements Layer Caching: zig build artifacts cached between runs
    pub fn nativeZigBuild(
        ctx: *dagger.Context,
        source: dagger.Directory,
    ) !dagger.File {
        var tester = try ctx.container();
        tester = try tester.from("docker.io/library/zig:0.16");
        tester = try tester.withMountedCache("/root/.cache/zig", try ctx.cacheVolume("zig-build-cache"));
        tester = try tester.withDirectory("/src", source);
        tester = try tester.withWorkdir("/src");

        // Deterministic build: sorted flags ensure consistent checksums
        tester = try tester.withExec(&.{
            "zig",
            "build",
            "test-integration",
            "-Doptimize=ReleaseSafe",
        });

        return tester.file("/src/zig-out/test.log");
    }

    /// benchmark runs perf benchmarks with caching
    pub fn benchmark(
        ctx: *dagger.Context,
        source: dagger.Directory,
    ) !dagger.Directory {
        var bencher = try ctx.container();
        bencher = try bencher.from("docker.io/library/zig:0.16");
        bencher = try bencher.withMountedCache("/root/.cache/zig", try ctx.cacheVolume("zig-build-cache"));
        bencher = try bencher.withDirectory("/src", source);
        bencher = try bencher.withWorkdir("/src");

        bencher = try bencher.withExec(&.{
            "zig",
            "build",
            "benches",
            "-Doptimize=ReleaseFast",
        });

        return bencher.directory("/src/zig-out/benches");
    }

    /// runAll orchestrates tests and benchmarks in parallel
    /// Implements Parallel Execution: independent test suites run concurrently
    pub fn runAll(
        ctx: *dagger.Context,
        source: dagger.Directory,
    ) !dagger.Directory {
        var results = try ctx.container();
        results = try results.from("alpine:latest");

        const test_output = try nativeZigBuild(ctx, source);
        const bench_output = try benchmark(ctx, source);

        results = try results.withFile("/test-output.log", test_output);
        results = try results.withDirectory("/benchmarks", bench_output);

        return results.directory("/");
    }
};
