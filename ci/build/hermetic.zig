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

        var builder = try ctx.container();
        builder = try builder.from(alpine_digest);
        builder = try builder.withExec(&.{ "apk", "add", "--no-cache", "zig=0.16.0-r0", "git" });
        builder = try builder.withDirectory("/src", source);
        builder = try builder.withWorkdir("/src");
        builder = try builder.withEnvVariable("SOURCE_DATE_EPOCH", "1700000000");
        builder = try builder.withEnvVariable("ZIG_LOCAL_CACHE_DIR", "/tmp/zig-cache");
        builder = try builder.withEnvVariable("ZIG_GLOBAL_CACHE_DIR", "/tmp/zig-global-cache");
        builder = try builder.withExec(&.{
            "zig",                        "build",
            "-Dtarget=" ++ config.target, "-Doptimize=" ++ config.optimize,
        });
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

            artifacts = try artifacts.withDirectory(target_dir, try built.directory(lib_path));
        }

        return artifacts;
    }
};

pub fn main(init: std.process.Init) !void {
    return dagger.module.serve(init, HermeticBuilder{});
}
