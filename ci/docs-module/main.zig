const std = @import("std");
const dagger = @import("dagger_sdk");

const MarkdownLinter = @import("markdown.zig").MarkdownLinter;

pub const DocsPipeline = struct {
    pub fn lintDocs(
        self: *const DocsPipeline,
        ctx: *dagger.Context,
        source: dagger.Directory,
    ) !dagger.Directory {
        _ = self;
        const linter = MarkdownLinter{};
        return try linter.fullCheck(ctx, source);
    }

    pub fn buildDocs(
        self: *const DocsPipeline,
        ctx: *dagger.Context,
        source: dagger.Directory,
    ) !dagger.Directory {
        _ = self;

        var source_id = try source.id();
        defer source_id.deinit(ctx.allocator());

        var ctr = try ctx.container();
        ctr = try ctr.from("rust:slim", null);
        ctr = try ctr.withExec(&.{ "cargo", "install", "mdbook" }, null, null, null, null, null, null, null, null, null, null);
        ctr = try ctr.withDirectory("/src", source_id.value, null, null, null, null, null, null);
        ctr = try ctr.withWorkdir("/src", null);
        ctr = try ctr.withExec(&.{ "sh", "-c", "if [ ! -f docs/book.toml ]; then mdbook init docs --title 'dagger-zig Documentation'; fi" }, null, null, null, null, null, null, null, null, null, null);
        ctr = try ctr.withExec(&.{ "mdbook", "build", "docs", "--dest-dir", "_site" }, null, null, null, null, null, null, null, null, null, null);

        return ctr.directory("/src/docs/_site", null);
    }
};

pub fn main(init: std.process.Init) !void {
    return dagger.module.serve(init, DocsPipeline{});
}
