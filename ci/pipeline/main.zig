const std = @import("std");
const dagger = @import("dagger_sdk");

// Import all submodules. They live in sibling directories and are wired as
// named modules in build.zig (file imports cannot cross the module root).
const Security = @import("ci_security").Security;
const Build = @import("ci_build").Build;
const Test = @import("ci_test").Test;
const Compliance = @import("ci_compliance").Compliance;
const Docs = @import("ci_docs").Docs;

/// Main CI/CD pipeline: orchestrates all workflow stages
/// Integrates security scanning, multi-arch builds, testing, compliance, and documentation
pub const Pipeline = struct {
    /// security runs all security scanners in parallel
    /// Technique: Parallel Execution (Volume Caching for scanner databases)
    pub fn security(
        _: *const Pipeline,
        ctx: *dagger.Context,
        source: dagger.Directory,
    ) !dagger.Directory {
        return Security.runAll(ctx, source);
    }

    /// build orchestrates multi-arch compilation with caching
    /// Technique: Two-Phase Mounting (go.mod/go.sum cached separately)
    /// Technique: Layer Caching (build artifacts reused across runs)
    /// Technique: Function Call Caching (identical inputs return cached outputs)
    pub fn build(
        _: *const Pipeline,
        ctx: *dagger.Context,
        source: dagger.Directory,
        container_tag: []const u8,
    ) !dagger.Directory {
        return Build.buildAndSign(ctx, source, container_tag, null);
    }

    /// test runs conformance tests and benchmarks
    /// Technique: Parallel Execution (tests and benchmarks run independently)
    /// Technique: Layer Caching (zig build cache materialized once)
    /// Note: `test` is a Zig reserved keyword, so the function is declared via
    /// the `@"test"` escaped identifier. Dagger still exposes it as `test`.
    pub fn @"test"(
        _: *const Pipeline,
        ctx: *dagger.Context,
        source: dagger.Directory,
    ) !dagger.Directory {
        return Test.runAll(ctx, source);
    }

    /// compliance runs policy checks: scorecard, commitlint, markdown lint
    /// Technique: Volume Caching (npm cache persists across runs)
    pub fn compliance(
        _: *const Pipeline,
        ctx: *dagger.Context,
        source: dagger.Directory,
        repo_url: []const u8,
        branch: []const u8,
        is_fork: bool,
    ) !dagger.Directory {
        return Compliance.runAll(ctx, source, repo_url, branch, is_fork);
    }

    /// docs validates markdown and builds documentation site
    /// Technique: Volume Caching (cargo registry and git cache)
    pub fn docs(
        _: *const Pipeline,
        ctx: *dagger.Context,
        source: dagger.Directory,
    ) !dagger.Directory {
        return Docs.runAll(ctx, source);
    }

    /// run orchestrates the full CI/CD pipeline with all stages
    /// Order: lint → security scan → build → test → compliance → docs
    /// Parallel stages where possible via goroutines in orchestration layer
    pub fn run(
        self: *const Pipeline,
        ctx: *dagger.Context,
        source: dagger.Directory,
    ) !dagger.Directory {
        // 1. Security scanning
        const security_results = try self.security(ctx, source);

        // 2. Build and SBOM/provenance
        const build_results = try self.build(ctx, source, "v1.0.0");

        // 3. Testing and benchmarks
        const test_results = try self.@"test"(ctx, source);

        // 4. Compliance checks (scorecard, commitlint, markdown)
        const compliance_results = try self.compliance(
            ctx,
            source,
            "https://github.com/MChorfa/dagger-zig",
            "main",
            false, // not a fork
        );

        // 5. Documentation build
        const docs_results = try self.docs(ctx, source);

        // Aggregate all artifacts
        var artifacts = try ctx.container();
        artifacts = try artifacts.from("alpine:latest");

        artifacts = try artifacts.withDirectory("/security", security_results);
        artifacts = try artifacts.withDirectory("/build", build_results);
        artifacts = try artifacts.withDirectory("/test", test_results);
        artifacts = try artifacts.withDirectory("/compliance", compliance_results);
        artifacts = try artifacts.withDirectory("/docs", docs_results);

        return artifacts.directory("/");
    }
};

pub fn main(init: std.process.Init) !void {
    return dagger.module.serve(init, Pipeline{});
}
