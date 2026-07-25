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
        base = try base.from("alpine:3.20");
        base = try base.withExec(&.{ "apk", "add", "--no-cache", "curl", "tar", "xz" });
        base = try base.withExec(&.{ "sh", "-c", zig_install });
        base = try base.withMountedCache("/root/.cache/zig", try ctx.dag().cacheVolume("zig-build-cache"));
        return base;
    }
    /// nativeZigBuild runs Zig native tests with layer caching
    /// Implements Layer Caching: zig build artifacts cached between runs
    pub fn nativeZigBuild(
        ctx: *dagger.Context,
        source: dagger.Directory,
    ) !dagger.File {
        var tester = try zigBase(ctx);
        tester = try tester.withDirectory("/src", source);
        tester = try tester.withWorkdir("/src");

        // Run the offline unit tests (no Dagger engine exists inside this
        // container, so the live integration suite cannot run here). Capture
        // output to a log and echo it, but propagate the real exit code so a
        // genuine test failure fails the pipeline (no silent suppression).
        tester = try tester.withExec(&.{
            "sh",
            "-c",
            "mkdir -p /src/zig-out; zig build test -Doptimize=ReleaseSafe > /src/zig-out/test.log 2>&1; rc=$?; cat /src/zig-out/test.log; exit $rc",
        });

        return tester.file("/src/zig-out/test.log");
    }

    /// benchmark runs the offline `zig build bench` step (query-builder and
    /// string serialization micro-benchmarks; no live engine required).
    pub fn benchmark(
        ctx: *dagger.Context,
        source: dagger.Directory,
    ) !dagger.Directory {
        var bencher = try zigBase(ctx);
        bencher = try bencher.withDirectory("/src", source);
        bencher = try bencher.withWorkdir("/src");

        // Capture output and tolerate failure so the returned directory always
        // exists even if the bench binary fails — the artifact upload is
        // best-effort, not a gate.
        bencher = try bencher.withExec(&.{
            "sh",
            "-c",
            "mkdir -p /src/zig-out/benches; zig build bench > /src/zig-out/benches/output.log 2>&1 || true",
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
        results = try results.from("alpine:latest", null);

        const test_output = try nativeZigBuild(ctx, source);
        const bench_output = try benchmark(ctx, source);

        results = try results.withFile("/test-output.log", test_output);
        results = try results.withDirectory("/benchmarks", bench_output);

        return results.directory("/");
    }
};
