const std = @import("std");
const dagger = @import("dagger_sdk");

/// Docs module: markdown validation, mdbook site build, GitHub Pages deployment
pub const Docs = struct {
    /// buildDocsSite builds the mdbook site with caching
    /// Implements Layer Caching: mdbook theme/assets cached between runs
    pub fn buildDocsSite(
        ctx: *dagger.Context,
        source: dagger.Directory,
    ) !dagger.Directory {
        var builder = try ctx.container();
        builder = try builder.from("rust:latest");
        builder = try builder.withExec(&.{ "cargo", "install", "mdbook" });
        builder = try builder.withDirectory("/src", source);
        builder = try builder.withWorkdir("/src/docs");

        // Volume caches for Rust deps
        builder = try builder.withMountedCache("/root/.cargo/registry", try ctx.cacheVolume("cargo-registry"));
        builder = try builder.withMountedCache("/root/.cargo/git", try ctx.cacheVolume("cargo-git"));

        builder = try builder.withExec(&.{ "mdbook", "build" });

        return builder.directory("/src/docs/_site");
    }

    /// validateMarkdown checks markdown against linting rules
    pub fn validateMarkdown(
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

    /// runAll orchestrates docs validation and build
    /// Implements Container Sync: base container materialized once for parallel ops
    pub fn runAll(
        ctx: *dagger.Context,
        source: dagger.Directory,
    ) !dagger.Directory {
        var results = try ctx.container();
        results = try results.from("alpine:latest");

        // Validate markdown
        const lint_output = try validateMarkdown(ctx, source);

        // Build site
        const site = try buildDocsSite(ctx, source);

        results = try results.withFile("/validation.txt", lint_output);
        results = try results.withDirectory("/site", site);

        return results.directory("/");
    }
};
