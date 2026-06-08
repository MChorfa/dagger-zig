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

        var ctr = try ctx.container();
        ctr = try ctr.from("rust:slim");
        ctr = try ctr.withExec(&.{ "cargo", "install", "mdbook" });
        ctr = try ctr.withDirectory("/src", source);
        ctr = try ctr.withWorkdir("/src");
        ctr = try ctr.withExec(&.{ "sh", "-c", "if [ ! -f docs/book.toml ]; then mdbook init docs --title 'dagger-zig Documentation'; fi" });
        ctr = try ctr.withExec(&.{ "mdbook", "build", "docs", "--dest-dir", "_site" });

        return ctr.directory("/src/docs/_site");
    }
};

pub fn main(init: std.process.Init) !void {
    return dagger.module.serve(init, DocsPipeline{});
}
