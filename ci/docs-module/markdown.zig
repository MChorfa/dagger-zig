const dagger = @import("dagger_sdk");

pub const MarkdownLinter = struct {
    pub fn lint(
        self: *const MarkdownLinter,
        ctx: *dagger.Context,
        source: dagger.Directory,
    ) !dagger.File {
        _ = self;

        var source_id = try source.id();
        defer source_id.deinit(ctx.allocator());

        var ctr = try ctx.container();
        ctr = try ctr.from("node:20-alpine", null);
        ctr = try ctr.withExec(&.{ "npm", "install", "-g", "markdownlint-cli2" }, null, null, null, null, null, null, null, null, null, null);
        ctr = try ctr.withDirectory("/src", source_id.value, null, null, null, null, null, null);
        ctr = try ctr.withWorkdir("/src", null);
        ctr = try ctr.withExec(&.{
            "sh",
            "-lc",
            "markdownlint-cli2 \"**/*.md\" --config .markdownlint.yaml > /tmp/markdown-lint.txt 2>&1; code=$?; echo \"exit_code=$code\" >> /tmp/markdown-lint.txt; exit 0",
        }, null, null, null, null, null, null, null, null, null, null);

        return try ctr.file("/tmp/markdown-lint.txt", null);
    }

    pub fn checkFormat(
        self: *const MarkdownLinter,
        ctx: *dagger.Context,
        source: dagger.Directory,
    ) !dagger.File {
        _ = self;

        var source_id = try source.id();
        defer source_id.deinit(ctx.allocator());

        var ctr = try ctx.container();
        ctr = try ctr.from("node:20-alpine", null);
        ctr = try ctr.withExec(&.{ "npm", "install", "-g", "prettier" }, null, null, null, null, null, null, null, null, null, null);
        ctr = try ctr.withDirectory("/src", source_id.value, null, null, null, null, null, null);
        ctr = try ctr.withWorkdir("/src", null);
        ctr = try ctr.withExec(&.{
            "sh",
            "-lc",
            "prettier --check \"**/*.md\" > /tmp/prettier-check.txt 2>&1; code=$?; echo \"exit_code=$code\" >> /tmp/prettier-check.txt; exit 0",
        }, null, null, null, null, null, null, null, null, null, null);

        return try ctr.file("/tmp/prettier-check.txt", null);
    }

    pub fn fullCheck(
        self: *const MarkdownLinter,
        ctx: *dagger.Context,
        source: dagger.Directory,
    ) !dagger.Directory {
        const lint_output = try self.lint(ctx, source);
        const format_output = try self.checkFormat(ctx, source);

        var lint_id = try lint_output.id();
        defer lint_id.deinit(ctx.allocator());
        var format_id = try format_output.id();
        defer format_id.deinit(ctx.allocator());

        var reports = try ctx.container();
        reports = try reports.from("alpine:latest", null);
        reports = try reports.withFile("/markdown-lint.txt", lint_id.value, null, null, null);
        reports = try reports.withFile("/prettier-check.txt", format_id.value, null, null, null);

        return reports.directory("/", null);
    }
};
