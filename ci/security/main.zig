const std = @import("std");
const dagger = @import("dagger_sdk");

/// Security scanning module: Semgrep SAST, GitLeaks, CodeQL, Grype, FOSSA
pub const Security = struct {
    pub fn semgrep(
        ctx: *dagger.Context,
        source: dagger.Directory,
    ) !dagger.Directory {
        var runner = try ctx.container();
        runner = try runner.from("semgrep/semgrep:latest");
        runner = try runner.withDirectory("/src", source);
        runner = try runner.withWorkdir("/src");
        runner = try runner.withExec(&.{
            "semgrep",
            "scan",
            "--config=auto",
            "--config=p/security-audit",
            "--sarif",
            "--output=/results/semgrep.sarif",
        });

        // Volume cache for semgrep cache directory
        runner = try runner.withMountedCache("/root/.semgrep-cache", try ctx.cacheVolume("semgrep-cache"));

        return runner.directory("/results");
    }

    pub fn gitleaks(
        ctx: *dagger.Context,
        source: dagger.Directory,
    ) !dagger.Directory {
        var runner = try ctx.container();
        runner = try runner.from("zricethezav/gitleaks:latest");
        runner = try runner.withDirectory("/repo", source);
        runner = try runner.withWorkdir("/repo");
        runner = try runner.withExec(&.{
            "gitleaks",
            "detect",
            "--report-path",
            "/results/gitleaks.json",
            "--verbose",
        });

        return runner.directory("/results");
    }

    pub fn codeql(
        ctx: *dagger.Context,
        source: dagger.Directory,
    ) !dagger.Directory {
        var runner = try ctx.container();
        runner = try runner.from("ghcr.io/github/codeql-action/codeql:latest");
        runner = try runner.withDirectory("/src", source);
        runner = try runner.withWorkdir("/src");
        runner = try runner.withExec(&.{
            "codeql",
            "database",
            "create",
            "--language=cpp,javascript",
            "/tmp/codeql-db",
        });
        runner = try runner.withExec(&.{
            "codeql",
            "database",
            "analyze",
            "/tmp/codeql-db",
            "--format=sarif-latest",
            "--output=/results/codeql.sarif",
            "--queries=security-extended,security-and-quality",
        });

        return runner.directory("/results");
    }

    pub fn grype(
        ctx: *dagger.Context,
        source: dagger.Directory,
    ) !dagger.Directory {
        var runner = try ctx.container();
        runner = try runner.from("anchore/grype:latest");
        runner = try runner.withDirectory("/src", source);
        runner = try runner.withWorkdir("/src");
        runner = try runner.withExec(&.{
            "grype",
            ".",
            "--output",
            "sarif",
            "--file",
            "/results/grype.sarif",
            "--fail-on",
            "high",
        });

        // Volume cache for grype database
        runner = try runner.withMountedCache("/root/.grype", try ctx.cacheVolume("grype-db"));

        return runner.directory("/results");
    }

    pub fn runAll(
        ctx: *dagger.Context,
        source: dagger.Directory,
    ) !dagger.Directory {
        var results = try ctx.container();
        results = try results.from("alpine:latest");

        // Run all scanners in parallel (conceptually; actual parallelization via goroutines in Go wrapper)
        const semgrep_results = try semgrep(ctx, source);
        const gitleaks_results = try gitleaks(ctx, source);
        const grype_results = try grype(ctx, source);

        results = try results.withDirectory("/semgrep", semgrep_results);
        results = try results.withDirectory("/gitleaks", gitleaks_results);
        results = try results.withDirectory("/grype", grype_results);

        return results.directory("/");
    }
};
