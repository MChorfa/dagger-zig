//! Markdown linting and formatting for documentation
//!
//! This module provides Dagger-native markdown linting using markdownlint-cli2
//! and prettier for auto-formatting.

const std = @import("std");
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
        const ctr = try ctx.container()
            .from("node:20-alpine")
            .withExec(&.{ "npm", "install", "-g", "markdownlint-cli2" })
            .withDirectory("/src", source)
            .withWorkdir("/src")
            .withExec(&.{ 
                "markdownlint-cli2", 
                "**/*.md",
                "--config", ".markdownlint.yaml"
            });
        
        // Return the stdout as a file for reporting
        return try ctr.stdout();
    }
    
    /// Format all markdown files using prettier
    pub fn format(
        self: *const MarkdownLinter,
        ctx: *dagger.Context,
        source: dagger.Directory,
    ) !dagger.Directory {
        _ = self;
        
        // Run prettier in a container
        const ctr = try ctx.container()
            .from("node:20-alpine")
            .withExec(&.{ "npm", "install", "-g", "prettier" })
            .withDirectory("/src", source)
            .withWorkdir("/src")
            .withExec(&.{ 
                "prettier", 
                "--write",
                "**/*.md"
            });
        
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
        const ctr = try ctx.container()
            .from("node:20-alpine")
            .withExec(&.{ "npm", "install", "-g", "prettier" })
            .withDirectory("/src", source)
            .withWorkdir("/src")
            .withExec(&.{ 
                "prettier", 
                "--check",
                "**/*.md"
            });
        
        return try ctr.stdout();
    }
    
    /// Run both lint and format check, returning combined report
    pub fn fullCheck(
        self: *const MarkdownLinter,
        ctx: *dagger.Context,
        source: dagger.Directory,
    ) !dagger.Directory {
        _ = self;
        
        // Create lint report
        const lint_output = try self.lint(ctx, source);
        
        // Create format check report
        const format_output = try self.checkFormat(ctx, source);
        
        // Combine reports into a directory
        var reports = try ctx.directory();
        reports = try reports.withFile("markdown-lint.txt", lint_output);
        reports = try reports.withFile("prettier-check.txt", format_output);
        
        return reports;
    }
};
