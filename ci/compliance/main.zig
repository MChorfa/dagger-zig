const std = @import("std");
const dagger = @import("dagger_sdk");

/// Compliance module: OpenSSF Scorecard, commitlint, policy checks
pub const Compliance = struct {
    /// scorecard runs security posture analysis (skip on forks)
    pub fn scorecard(
        ctx: *dagger.Context,
        repo_url: []const u8,
        branch: []const u8,
        skip_on_fork: bool,
    ) !dagger.File {
        // Minimal valid SARIF 2.1.0 doc so upload-sarif accepts the fork-skip case
        const empty_sarif = "{\"version\":\"2.1.0\",\"$schema\":\"https://json.schemastore.org/sarif-2.1.0.json\",\"runs\":[]}";
        if (skip_on_fork) {
            // Return empty report for forks
            var stub = try ctx.container();
            stub = try stub.from("alpine:latest");
            stub = try stub.withNewFile("/scorecard.sarif", empty_sarif);
            return stub.file("/scorecard.sarif");
        }

        var scorer = try ctx.container();
        scorer = try scorer.from("ghcr.io/ossf/scorecard:latest");

        // Volume cache for scorecard check cache
        scorer = try scorer.withMountedCache("/root/.scorecard", try ctx.dag().cacheVolume("scorecard-cache"));

        // SARIF output so GitHub code-scanning (upload-sarif) can ingest results
        scorer = try scorer.withExec(&.{
            "scorecard",
            "--repo",
            repo_url,
            "--branch",
            branch,
            "--format",
            "sarif",
            "--output",
            "/results/scorecard.sarif",
        });

        return scorer.file("/results/scorecard.sarif");
    }

    /// commitlint validates commit messages in the source tree
    pub fn commitlint(
        ctx: *dagger.Context,
        source: dagger.Directory,
    ) !dagger.File {
        var linter = try ctx.container();
        linter = try linter.from("node:20-alpine");
        linter = try linter.withExec(&.{ "npm", "install", "-g", "commitlint@latest", "@commitlint/config-conventional" });
        linter = try linter.withDirectory("/src", source);
        linter = try linter.withWorkdir("/src");
        linter = try linter.withNewFile("/src/.commitlintrc.json", "{\"extends\":[\"@commitlint/config-conventional\"]}");

        // Volume cache for npm packages
        linter = try linter.withMountedCache("/root/.npm", try ctx.dag().cacheVolume("npm-cache"));

        // Capture the report to a file; tolerate non-zero exit (commit violations
        // and absent git history) so the artifact is always produced. Skips
        // cleanly when no .git is present in the source tree.
        linter = try linter.withExec(&.{
            "sh",
            "-c",
            "if [ -d .git ]; then commitlint --from HEAD~10 --to HEAD; else echo 'commitlint: no .git in source, skipped'; fi > /commitlint-output.txt 2>&1 || true",
        });

        return linter.file("/commitlint-output.txt");
    }

    /// markdown linting with cache
    pub fn markdownLint(
        ctx: *dagger.Context,
        source: dagger.Directory,
    ) !dagger.File {
        var linter = try ctx.container();
        linter = try linter.from("node:20-alpine");
        linter = try linter.withExec(&.{ "npm", "install", "-g", "markdownlint-cli" });
        linter = try linter.withDirectory("/src", source);
        linter = try linter.withWorkdir("/src");

        // Volume cache for npm
        linter = try linter.withMountedCache("/root/.npm", try ctx.dag().cacheVolume("npm-cache"));

        // Capture report; tolerate lint findings so the artifact is produced.
        linter = try linter.withExec(&.{
            "sh",
            "-c",
            "markdownlint 'docs/**/*.md' --config .markdownlint.yaml > /lint-output.txt 2>&1 || true",
        });

        return linter.file("/lint-output.txt");
    }

    /// runAll orchestrates all compliance checks
    pub fn runAll(
        ctx: *dagger.Context,
        source: dagger.Directory,
        repo_url: []const u8,
        branch: []const u8,
        is_fork: bool,
    ) !dagger.Directory {
        var results = try ctx.container();
        results = try results.from("alpine:latest");

        const scorecard_result = try scorecard(ctx, repo_url, branch, is_fork);
        const commitlint_result = try commitlint(ctx, source);
        const markdown_result = try markdownLint(ctx, source);

        results = try results.withFile("/scorecard.sarif", scorecard_result);
        results = try results.withFile("/commitlint.txt", commitlint_result);
        results = try results.withFile("/markdown-lint.txt", markdown_result);

        return results.directory("/");
    }
};
