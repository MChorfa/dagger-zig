//! Markdown linting and formatting for documentation
//!
//! This module provides Dagger-native markdown linting using markdownlint-cli2
//! and prettier for auto-formatting.

const dagger = @import("dagger_sdk");

pub const MarkdownLinter = struct {
    /// Lint all markdown files in the source directory
    pub fn lint(
        self: *const MarkdownLinter,
        ctx: *dagger.Context,
        source: dagger.Directory,
    ) !dagger.File {
        _ = self;

        // Run markdownlint-cli2 in a container
        var ctr = try ctx.container();
        ctr = try ctr.from("node:20-alpine");
        ctr = try ctr.withExec(&.{ "npm", "install", "-g", "markdownlint-cli2" });
        ctr = try ctr.withDirectory("/src", source);
        ctr = try ctr.withWorkdir("/src");
        ctr = try ctr.withExec(&.{
            "sh",
            "-lc",
            "markdownlint-cli2 \"**/*.md\" --config .markdownlint.yaml > /tmp/markdown-lint.txt 2>&1; code=$?; echo \"exit_code=$code\" >> /tmp/markdown-lint.txt; exit 0",
        });

        return try ctr.file("/tmp/markdown-lint.txt");
    }

    /// Format all markdown files using prettier
    pub fn format(
        self: *const MarkdownLinter,
        ctx: *dagger.Context,
        source: dagger.Directory,
    ) !dagger.Directory {
        _ = self;

        // Run prettier in a container
        var ctr = try ctx.container();
        ctr = try ctr.from("node:20-alpine");
        ctr = try ctr.withExec(&.{ "npm", "install", "-g", "prettier" });
        ctr = try ctr.withDirectory("/src", source);
        ctr = try ctr.withWorkdir("/src");
        ctr = try ctr.withExec(&.{ "prettier", "--write", "**/*.md" });

        // Return the formatted source directory
        return ctr.directory("/src");
    }

    /// Check if markdown files are properly formatted (no changes needed)
    pub fn checkFormat(
        self: *const MarkdownLinter,
        ctx: *dagger.Context,
        source: dagger.Directory,
    ) !dagger.File {
        _ = self;

        // Run prettier --check in a container
        var ctr = try ctx.container();
        ctr = try ctr.from("node:20-alpine");
        ctr = try ctr.withExec(&.{ "npm", "install", "-g", "prettier" });
        ctr = try ctr.withDirectory("/src", source);
        ctr = try ctr.withWorkdir("/src");
        ctr = try ctr.withExec(&.{
            "sh",
            "-lc",
            "prettier --check \"**/*.md\" > /tmp/prettier-check.txt 2>&1; code=$?; echo \"exit_code=$code\" >> /tmp/prettier-check.txt; exit 0",
        });

        return try ctr.file("/tmp/prettier-check.txt");
    }

    /// Run both lint and format check, returning combined report
    pub fn fullCheck(
        self: *const MarkdownLinter,
        ctx: *dagger.Context,
        source: dagger.Directory,
    ) !dagger.Directory {

        // Create lint report
        const lint_output = try self.lint(ctx, source);

        // Create format check report
        const format_output = try self.checkFormat(ctx, source);

        // Combine reports into a directory
        var reports = try ctx.container();
        reports = try reports.from("alpine:latest");
        reports = try reports.withFile("/markdown-lint.txt", lint_output);
        reports = try reports.withFile("/prettier-check.txt", format_output);

        return reports.directory("/");
    }
};
