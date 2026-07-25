const std = @import("std");
const dagger = @import("dagger_sdk");

pub const HermeticBuilder = struct {
    pub const BuildConfig = struct {
        target: []const u8,
        optimize: []const u8 = "ReleaseSafe",
    };

    pub fn build(
        self: *const HermeticBuilder,
        ctx: *dagger.Context,
        source: dagger.Directory,
        config: BuildConfig,
    ) !dagger.Container {
        _ = self;
        const alpine_digest = "alpine:3.19@sha256:c5b1261d6d3e43071626931fc004f70149bae1552ea0340ca1c5f0f0a3b5b6a6";

        var source_id = try source.id();
        defer source_id.deinit(ctx.allocator());

        var builder = try ctx.container();
        builder = try builder.from(alpine_digest, null);
        builder = try builder.withExec(&.{ "apk", "add", "--no-cache", "zig=0.16.0-r0", "git" }, null, null, null, null, null, null, null, null, null, null);
        builder = try builder.withDirectory("/src", source_id.value, null, null, null, null, null, null);
        builder = try builder.withWorkdir("/src", null);
        builder = try builder.withEnvVariable("SOURCE_DATE_EPOCH", "1700000000", null);
        builder = try builder.withEnvVariable("ZIG_LOCAL_CACHE_DIR", "/tmp/zig-cache", null);
        builder = try builder.withEnvVariable("ZIG_GLOBAL_CACHE_DIR", "/tmp/zig-global-cache", null);
        const target_arg = try std.fmt.allocPrint(ctx.allocator(), "-Dtarget={s}", .{config.target});
        const optimize_arg = try std.fmt.allocPrint(ctx.allocator(), "-Doptimize={s}", .{config.optimize});
        builder = try builder.withExec(&.{
            "zig",        "build",
            target_arg,   optimize_arg,
        }, null, null, null, null, null, null, null, null, null, null);
        return builder;
    }

    pub fn buildMultiTarget(
        self: *const HermeticBuilder,
        ctx: *dagger.Context,
        source: dagger.Directory,
    ) !dagger.Directory {
        const targets = [_][]const u8{
            "x86_64-linux-gnu",
            "aarch64-linux-gnu",
            "x86_64-macos-none",
            "aarch64-macos-none",
        };

        var artifacts = try ctx.directory();

        for (targets) |target| {
            const built = try self.build(ctx, source, .{ .target = target });
            const lib_path = try std.fmt.allocPrint(ctx.allocator(), "/src/zig-out/lib/", .{});
            const target_dir = try std.fmt.allocPrint(ctx.allocator(), "{s}/", .{target});

            const built_dir = try built.directory(lib_path, null);
            var built_dir_id = try built_dir.id();
            defer built_dir_id.deinit(ctx.allocator());
            artifacts = try artifacts.withDirectory(target_dir, built_dir_id.value, null, null, null, null, null);
        }

        return artifacts;
    }
};

pub fn main(init: std.process.Init) !void {
    return dagger.module.serve(init, HermeticBuilder{});
}
