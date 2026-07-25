const std = @import("std");
const dagger = @import("dagger_sdk");

pub const ProvenanceGenerator = struct {
    pub fn generate(
        self: *const ProvenanceGenerator,
        ctx: *dagger.Context,
        source: dagger.Directory,
        builder_id: []const u8,
        config_path: []const u8,
        subject_name: []const u8,
        manifest_sha256: []const u8,
    ) !dagger.File {
        _ = self;

        var git_runner = try ctx.container();
        git_runner = try git_runner.from("alpine/git");
        git_runner = try git_runner.withDirectory("/src", source);
        git_runner = try git_runner.withWorkdir("/src");
        git_runner = try git_runner.withExec(&.{
            "sh", "-c", "git rev-parse HEAD 2>/dev/null || echo unknown",
        });
        const git_commit_raw = try git_runner.stdout();
        const git_commit = std.mem.trim(u8, git_commit_raw, " \t\r\n");

        var ts_runner = try ctx.container();
        ts_runner = try ts_runner.from("alpine:latest", null);
        ts_runner = try ts_runner.withExec(&.{ "date", "-u", "+%Y-%m-%dT%H:%M:%SZ" });
        const timestamp_raw = try ts_runner.stdout();
        const timestamp = std.mem.trim(u8, timestamp_raw, " \t\r\n");

        const json_fmt =
            "{{" ++
            "\"_type\":\"https://in-toto.io/Statement/v1\"," ++
            "\"subject\":[{{\"name\":\"{s}\",\"digest\":{{\"sha256\":\"{s}\"}}}}]," ++
            "\"predicateType\":\"https://slsa.dev/provenance/v1\"," ++
            "\"predicate\":{{" ++
            "\"buildDefinition\":{{" ++
            "\"buildType\":\"https://dagger.io/build/v1\"," ++
            "\"externalParameters\":{{\"entryPoint\":\"{s}\"}}," ++
            "\"internalParameters\":{{\"engine\":\"dagger\"}}," ++
            "\"resolvedDependencies\":[{{\"uri\":\"https://gitlab.com/MChorfa/dagger-zig\",\"digest\":{{\"gitCommit\":\"{s}\"}}}}]}}," ++
            "\"runDetails\":{{" ++
            "\"builder\":{{\"id\":\"{s}\"}}," ++
            "\"metadata\":{{" ++
            "\"invocationId\":\"https://gitlab.com/MChorfa/dagger-zig\"," ++
            "\"startedOn\":\"{s}\"}}}}}}}}";

        const content = try std.fmt.allocPrint(ctx.allocator(), json_fmt, .{
            subject_name, manifest_sha256, config_path, git_commit, builder_id, timestamp,
        });

        var writer = try ctx.container();
        writer = try writer.from("alpine:latest", null);
        writer = try writer.withNewFile("/provenance.json", content);
        return writer.file("/provenance.json");
    }
};

pub fn main(init: std.process.Init) !void {
    return dagger.module.serve(init, ProvenanceGenerator{});
}
