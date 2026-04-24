const std = @import("std");
const dagger = @import("dagger_sdk");

pub const ProvenanceGenerator = struct {
    pub fn generate(
        self: *const ProvenanceGenerator,
        ctx: *dagger.Context,
        source: dagger.Directory,
        builder_id: []const u8,
        config_path: []const u8,
    ) !dagger.File {
        _ = self;
        const git_commit = try ctx
            .container()
            .from("alpine/git")
            .withDirectory("/src", source)
            .withWorkdir("/src")
            .withExec(&.{ "git", "rev-parse", "HEAD" })
            .stdout();

        const timestamp = try ctx
            .container()
            .from("alpine:latest")
            .withExec(&.{ "date", "-u", "+%Y-%m-%dT%H:%M:%SZ" })
            .stdout();

        const json_fmt = "{{" ++
            "\"_type\":\"https://in-toto.io/Statement/v0.1\"," ++
            "\"subject\":[{{\"name\":\"dagger-zig\",\"digest\":{{\"sha256\":\"PENDING\"}}}}]," ++
            "\"predicateType\":\"https://slsa.dev/provenance/v0.2\"," ++
            "\"predicate\":{{" ++
            "\"builder\":{{\"id\":\"{s}\"}}," ++
            "\"buildType\":\"https://dagger.io/build/v1\"," ++
            "\"invocation\":{{" ++
            "\"configSource\":{{" ++
            "\"uri\":\"https://gitlab.com/ckodex/dagger-zig\"," ++
            "\"digest\":{{\"sha1\":\"{s}\"}}," ++
            "\"entryPoint\":\"{s}\"}}}}," ++
            "\"metadata\":{{" ++
            "\"buildStartedOn\":\"{s}\"," ++
            "\"completeness\":{{" ++
            "\"parameters\":true," ++
            "\"environment\":true," ++
            "\"materials\":true}}," ++
            "\"reproducible\":true}}," ++
            "\"materials\":[]}}}}";

        const content = try std.fmt.allocPrint(ctx.allocator(), json_fmt, .{
            builder_id, git_commit, config_path, timestamp,
        });

        const container = try ctx
            .container()
            .from("alpine:latest")
            .withNewFile("/provenance.json", content);

        return container.file("/provenance.json");
    }
};

pub fn main(init: std.process.Init) !void {
    return dagger.module.serve(init, ProvenanceGenerator{});
}
