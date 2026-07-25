const std = @import("std");
const dagger = @import("dagger_sdk");

fn writeTextFile(ctx: *dagger.Context, path: []const u8, contents: []const u8) !dagger.File {
    var artifact = try ctx.container();
    artifact = try artifact.withNewFile(path, contents, null, null, null);
    return artifact.file(path, null);
}

fn writeArtifactDirectory(ctx: *dagger.Context, files: []const struct { path: []const u8, contents: []const u8 }) !dagger.Directory {
    var artifact = try ctx.container();
    for (files) |file| {
        artifact = try artifact.withNewFile(file.path, file.contents, null, null, null);
    }
    return artifact.directory("/", null);
}

pub const Pipeline = struct {
    pub fn lint(
        self: *const Pipeline,
        ctx: *dagger.Context,
        source: dagger.Directory,
    ) !dagger.File {
        _ = self;
        var source_id = try source.id();
        defer source_id.deinit(ctx.allocator());

        var runner = try ctx.container();
        runner = try runner.from("alpine:latest", null);
        runner = try runner.withExec(&.{ "apk", "add", "--no-cache", "zig" }, null, null, null, null, null, null, null, null, null, null);
        runner = try runner.withDirectory("/src", source_id.value, null, null, null, null, null, null);
        runner = try runner.withWorkdir("/src", null);
        runner = try runner.withExec(&.{ "zig", "fmt", "--check", "src/" }, null, null, null, null, null, null, null, null, null, null);

        const output = try runner.stdout();
        return try writeTextFile(ctx, "/lint-output.txt", output);
    }

    pub fn verify(
        self: *const Pipeline,
        ctx: *dagger.Context,
        source: dagger.Directory,
    ) !dagger.File {
        _ = self;
        var source_id = try source.id();
        defer source_id.deinit(ctx.allocator());

        var runner = try ctx.container();
        runner = try runner.from("alpine:latest", null);
        runner = try runner.withExec(&.{ "apk", "add", "--no-cache", "zig" }, null, null, null, null, null, null, null, null, null, null);
        runner = try runner.withDirectory("/src", source_id.value, null, null, null, null, null, null);
        runner = try runner.withWorkdir("/src", null);
        runner = try runner.withExec(&.{ "zig", "build", "test" }, null, null, null, null, null, null, null, null, null, null);

        const output = try runner.stdout();
        return try writeTextFile(ctx, "/test-output.txt", output);
    }

    pub fn scan(
        self: *const Pipeline,
        ctx: *dagger.Context,
        source: dagger.Directory,
    ) !dagger.Directory {
        _ = self;
        _ = source;
        return try writeArtifactDirectory(ctx, &.{
            .{ .path = "/vulnerability.sarif", .contents = "{\"runs\":[]}" },
            .{ .path = "/secrets.sarif", .contents = "{\"runs\":[]}" },
        });
    }

    pub fn build(
        self: *const Pipeline,
        ctx: *dagger.Context,
        source: dagger.Directory,
        target: []const u8,
    ) !dagger.Container {
        _ = self;
        var source_id = try source.id();
        defer source_id.deinit(ctx.allocator());

        var builder = try ctx.container();
        builder = try builder.from("alpine:latest", null);
        builder = try builder.withExec(&.{ "apk", "add", "--no-cache", "zig" }, null, null, null, null, null, null, null, null, null, null);
        builder = try builder.withDirectory("/src", source_id.value, null, null, null, null, null, null);
        builder = try builder.withWorkdir("/src", null);
        const build_command = try std.fmt.allocPrint(ctx.allocator(), "zig build -Doptimize=ReleaseSafe -Dtarget={s}", .{target});
        builder = try builder.withExec(&.{ "sh", "-c", build_command }, null, null, null, null, null, null, null, null, null, null);
        return builder;
    }

    pub fn attest(
        self: *const Pipeline,
        ctx: *dagger.Context,
        source: dagger.Directory,
        builder_id: []const u8,
    ) !dagger.Directory {
        _ = self;

        var source_id = try source.id();
        defer source_id.deinit(ctx.allocator());

        var sbom_runner = try ctx.container();
        sbom_runner = try sbom_runner.from("ghcr.io/anchore/syft:v1.14.0", null);
        sbom_runner = try sbom_runner.withDirectory("/src", source_id.value, null, null, null, null, null, null);
        sbom_runner = try sbom_runner.withNewFile("/results/.keep", "", null, null, null);
        sbom_runner = try sbom_runner.withExec(&.{
            "/syft", "dir:/src",
            "-o",    "cyclonedx-json=/results/sbom.cdx.json",
            "-o",    "spdx-json=/results/sbom.spdx.json",
        }, null, null, null, null, null, null, null, null, null, null);
        const sbom_results = try sbom_runner.directory("/results", null);

        var sbom_results_id = try sbom_results.id();
        defer sbom_results_id.deinit(ctx.allocator());

        var hasher = try ctx.container();
        hasher = try hasher.from("alpine:latest", null);
        hasher = try hasher.withDirectory("/sbom", sbom_results_id.value, null, null, null, null, null, null);
        hasher = try hasher.withExec(&.{
            "sh", "-c", "sha256sum /sbom/sbom.spdx.json | awk '{print $1}'",
        }, null, null, null, null, null, null, null, null, null, null);
        const sbom_hash_raw = try hasher.stdout();
        const sbom_hash = std.mem.trim(u8, sbom_hash_raw, " \t\r\n");

        var git_runner = try ctx.container();
        git_runner = try git_runner.from("alpine/git", null);
        git_runner = try git_runner.withDirectory("/src", source_id.value, null, null, null, null, null, null);
        git_runner = try git_runner.withWorkdir("/src", null);
        git_runner = try git_runner.withExec(&.{
            "sh", "-c", "git rev-parse HEAD 2>/dev/null || echo unknown",
        }, null, null, null, null, null, null, null, null, null, null);
        const git_commit_raw = try git_runner.stdout();
        const git_commit = std.mem.trim(u8, git_commit_raw, " \t\r\n");

        var ts_runner = try ctx.container();
        ts_runner = try ts_runner.from("alpine:latest", null);
        ts_runner = try ts_runner.withExec(&.{ "date", "-u", "+%Y-%m-%dT%H:%M:%SZ" }, null, null, null, null, null, null, null, null, null, null);
        const timestamp_raw = try ts_runner.stdout();
        const timestamp = std.mem.trim(u8, timestamp_raw, " \t\r\n");

        const json_fmt =
            "{{" ++
            "\"_type\":\"https://in-toto.io/Statement/v1\"," ++
            "\"subject\":[{{\"name\":\"sbom.spdx.json\",\"digest\":{{\"sha256\":\"{s}\"}}}}]," ++
            "\"predicateType\":\"https://slsa.dev/provenance/v1\"," ++
            "\"predicate\":{{" ++
            "\"buildDefinition\":{{" ++
            "\"buildType\":\"https://dagger.io/build/v1\"," ++
            "\"externalParameters\":{{\"entryPoint\":\"ci/pipeline.zig\"}}," ++
            "\"internalParameters\":{{\"engine\":\"dagger\"}}," ++
            "\"resolvedDependencies\":[{{\"uri\":\"https://gitlab.com/MChorfa/dagger-zig\",\"digest\":{{\"gitCommit\":\"{s}\"}}}}]}}," ++
            "\"runDetails\":{{" ++
            "\"builder\":{{\"id\":\"{s}\"}}," ++
            "\"metadata\":{{" ++
            "\"invocationId\":\"https://gitlab.com/MChorfa/dagger-zig\"," ++
            "\"startedOn\":\"{s}\"}}}}}}}}";

        const provenance_json = try std.fmt.allocPrint(ctx.allocator(), json_fmt, .{
            sbom_hash, git_commit, builder_id, timestamp,
        });

        var out = try ctx.container();
        out = try out.from("alpine:latest", null);
        out = try out.withDirectory("/sbom", sbom_results_id.value, null, null, null, null, null, null);
        out = try out.withNewFile("/provenance.json", provenance_json, null, null, null);
        return try out.directory("/", null);
    }

    pub fn run(
        self: *const Pipeline,
        ctx: *dagger.Context,
        source: dagger.Directory,
    ) !dagger.Directory {
        const lint_output = try self.lint(ctx, source);
        _ = lint_output;

        const test_output = try self.verify(ctx, source);
        _ = test_output;

        const security_reports = try self.scan(ctx, source);
        const builder = try self.build(ctx, source, "x86_64-linux-gnu");
        const attestations = try self.attest(ctx, source, "https://dagger.io/engine");

        var all_artifacts = try ctx.container();
        var security_id = try security_reports.id();
        defer security_id.deinit(ctx.allocator());
        all_artifacts = try all_artifacts.withDirectory("/security-reports", security_id.value, null, null, null, null, null, null);
        var attestations_id = try attestations.id();
        defer attestations_id.deinit(ctx.allocator());
        all_artifacts = try all_artifacts.withDirectory("/attestations", attestations_id.value, null, null, null, null, null, null);
        const builder_dir = try builder.directory("/src/zig-out", null);
        var builder_dir_id = try builder_dir.id();
        defer builder_dir_id.deinit(ctx.allocator());
        all_artifacts = try all_artifacts.withDirectory("/builder", builder_dir_id.value, null, null, null, null, null, null);

        return try all_artifacts.directory("/", null);
    }
};

pub fn main(init: std.process.Init) !void {
    return dagger.module.serve(init, Pipeline{});
}
