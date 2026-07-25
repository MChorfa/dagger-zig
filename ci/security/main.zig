const std = @import("std");
const dagger = @import("dagger_sdk");

/// Security scanning module: Semgrep SAST, GitLeaks, CodeQL, Grype, FOSSA
pub const Security = struct {
    pub fn semgrep(
        ctx: *dagger.Context,
        source: dagger.Directory,
    ) !dagger.Directory {
        var source_id = try source.id();
        defer source_id.deinit(ctx.allocator());

        var runner = try ctx.container();
        runner = try runner.from("semgrep/semgrep@sha256:207983631beecdbe7fa29196c7f4a7a5f29033933cdb76c687ce4a672e07618d", null);
        runner = try runner.withDirectory("/src", source_id.value, null, null, null, null, null, null);
        runner = try runner.withWorkdir("/src", null);

        // Volume cache for semgrep cache directory (mounted before the scan).
        var semgrep_cache = try ctx.dag().cacheVolume("semgrep-cache", null, null, null);
        var semgrep_cache_id = try semgrep_cache.id();
        defer semgrep_cache_id.deinit(ctx.allocator());
        runner = try runner.withMountedCache("/root/.semgrep-cache", semgrep_cache_id.value, null, null, null, null);

        // Capture SARIF; tolerate findings (non-zero exit) so the report is produced.
        runner = try runner.withExec(&.{
            "sh",
            "-c",
            "mkdir -p /results; semgrep scan --config=auto --config=p/security-audit --sarif --output=/results/semgrep.sarif || true",
        }, null, null, null, null, null, null, null, null, null, null);

        return runner.directory("/results", null);
    }

    pub fn gitleaks(
        ctx: *dagger.Context,
        source: dagger.Directory,
    ) !dagger.Directory {
        var source_id = try source.id();
        defer source_id.deinit(ctx.allocator());

        var runner = try ctx.container();
        runner = try runner.from("zricethezav/gitleaks@sha256:c00b6bd0aeb3071cbcb79009cb16a60dd9e0a7c60e2be9ab65d25e6bc8abbb7f", null);
        runner = try runner.withDirectory("/repo", source_id.value, null, null, null, null, null, null);
        runner = try runner.withWorkdir("/repo", null);

        // Scan files without requiring git history; tolerate findings so the
        // report is always produced.
        runner = try runner.withExec(&.{
            "sh",
            "-c",
            "mkdir -p /results; gitleaks detect --source . --no-git --report-path /results/gitleaks.json --verbose || true",
        }, null, null, null, null, null, null, null, null, null, null);

        return runner.directory("/results", null);
    }

    pub fn codeql(
        ctx: *dagger.Context,
        source: dagger.Directory,
    ) !dagger.Directory {
        var source_id = try source.id();
        defer source_id.deinit(ctx.allocator());

        var runner = try ctx.container();
        runner = try runner.from("ghcr.io/github/codeql-action/codeql:latest", null);
        runner = try runner.withDirectory("/src", source_id.value, null, null, null, null, null, null);
        runner = try runner.withWorkdir("/src", null);
        // Seed /results so the analyze step can write into it.
        runner = try runner.withNewFile("/results/.keep", "", null, null, null);
        runner = try runner.withExec(&.{
            "codeql",
            "database",
            "create",
            "--language=cpp,javascript",
            "/tmp/codeql-db",
        }, null, null, null, null, null, null, null, null, null, null);
        runner = try runner.withExec(&.{
            "codeql",
            "database",
            "analyze",
            "/tmp/codeql-db",
            "--format=sarif-latest",
            "--output=/results/codeql.sarif",
            "--queries=security-extended,security-and-quality",
        }, null, null, null, null, null, null, null, null, null, null);

        return runner.directory("/results", null);
    }

    pub fn grype(
        ctx: *dagger.Context,
        source: dagger.Directory,
    ) !dagger.Directory {
        var source_id = try source.id();
        defer source_id.deinit(ctx.allocator());

        var runner = try ctx.container();
        runner = try runner.from("anchore/grype@sha256:7a9fc7f89ccef78ae5a7691a115d3f0d41b1f319d589dd8cc1dcb9ab3f01dd28", null);
        runner = try runner.withDirectory("/src", source_id.value, null, null, null, null, null, null);
        runner = try runner.withWorkdir("/src", null);

        // Volume cache for grype database (mounted before the scan).
        var grype_cache = try ctx.dag().cacheVolume("grype-db", null, null, null);
        var grype_cache_id = try grype_cache.id();
        defer grype_cache_id.deinit(ctx.allocator());
        runner = try runner.withMountedCache("/root/.grype", grype_cache_id.value, null, null, null, null);

        // grype's image is distroless (no shell), so run it directly. Seed
        // /results so grype can write into it. Without --fail-on, grype exits 0
        // even when vulnerabilities are found, so no tolerance wrapper is needed.
        runner = try runner.withNewFile("/results/.keep", "", null, null, null);
        // The binary lives at the image root (scratch-based image, not on PATH).
        runner = try runner.withExec(&.{
            "/grype",
            "dir:/src",
            "--output",
            "sarif",
            "--file",
            "/results/grype.sarif",
        }, null, null, null, null, null, null, null, null, null, null);

        return runner.directory("/results", null);
    }

    pub fn runAll(
        ctx: *dagger.Context,
        source: dagger.Directory,
    ) !dagger.Directory {
        var results = try ctx.container();
        results = try results.from("alpine:latest", null);

        // Each scanner is an independent Dagger pipeline; the engine evaluates
        // these graph branches concurrently at execution time (no goroutines here).
        const semgrep_results = try semgrep(ctx, source);
        const gitleaks_results = try gitleaks(ctx, source);
        const grype_results = try grype(ctx, source);

        var semgrep_id = try semgrep_results.id();
        defer semgrep_id.deinit(ctx.allocator());
        var gitleaks_id = try gitleaks_results.id();
        defer gitleaks_id.deinit(ctx.allocator());
        var grype_id = try grype_results.id();
        defer grype_id.deinit(ctx.allocator());

        results = try results.withDirectory("/semgrep", semgrep_id.value, null, null, null, null, null, null);
        results = try results.withDirectory("/gitleaks", gitleaks_id.value, null, null, null, null, null, null);
        results = try results.withDirectory("/grype", grype_id.value, null, null, null, null, null, null);

        return results.directory("/", null);
    }
};
