const dagger = @import("dagger_sdk");

pub const MarkdownLinter = struct {
    pub fn lint(
        self: *const MarkdownLinter,
        ctx: *dagger.Context,
        source: dagger.Directory,
    ) !dagger.File {
        _ = self;

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

    pub fn checkFormat(
        self: *const MarkdownLinter,
        ctx: *dagger.Context,
        source: dagger.Directory,
    ) !dagger.File {
        _ = self;

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

    pub fn fullCheck(
        self: *const MarkdownLinter,
        ctx: *dagger.Context,
        source: dagger.Directory,
    ) !dagger.Directory {
        const lint_output = try self.lint(ctx, source);
        const format_output = try self.checkFormat(ctx, source);

        var reports = try ctx.container();
        reports = try reports.from("alpine:latest", null);
        reports = try reports.withFile("/markdown-lint.txt", lint_output);
        reports = try reports.withFile("/prettier-check.txt", format_output);

        return reports.directory("/");
    }
};
