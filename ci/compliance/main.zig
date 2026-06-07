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
        if (skip_on_fork) {
            // Return empty report for forks
            var stub = try ctx.container();
            stub = try stub.from("alpine:latest");
            stub = try stub.withNewFile("/scorecard.json", "{\"skip_reason\":\"fork\"}");
            return stub.file("/scorecard.json");
        }

        var scorer = try ctx.container();
        scorer = try scorer.from("ghcr.io/ossf/scorecard:latest");

        // Volume cache for scorecard check cache
        scorer = try scorer.withMountedCache("/root/.scorecard", try ctx.cacheVolume("scorecard-cache"));

        scorer = try scorer.withExec(&.{
            "scorecard",
            "--repo",
            repo_url,
            "--branch",
            branch,
            "--format",
            "json",
            "--output",
            "/results/scorecard.json",
        });

        return scorer.file("/results/scorecard.json");
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
        linter = try linter.withNewFile("/.commitlintrc.json", "{\"extends\":[\"@commitlint/config-conventional\"]}");

        // Volume cache for npm packages
        linter = try linter.withMountedCache("/root/.npm", try ctx.cacheVolume("npm-cache"));

        linter = try linter.withExec(&.{
            "commitlint",
            "--from",
            "HEAD~10",
            "--to",
            "HEAD",
            "--print",
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
        linter = try linter.withMountedCache("/root/.npm", try ctx.cacheVolume("npm-cache"));

        linter = try linter.withExec(&.{
            "markdownlint",
            "docs/**/*.md",
            "--config",
            ".markdownlint.json",
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

        results = try results.withFile("/scorecard.json", scorecard_result);
        results = try results.withFile("/commitlint.txt", commitlint_result);
        results = try results.withFile("/markdown-lint.txt", markdown_result);

        return results.directory("/");
    }
};
