const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const dagger_dep = b.dependency("dagger_sdk", .{
        .target = target,
        .optimize = optimize,
    });

    const module_mod = b.createModule(.{
        .root_source_file = b.path("main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{.{ .name = "dagger_sdk", .module = dagger_dep.module("dagger_sdk") }},
    });

    const exe = b.addExecutable(.{
        .name = "module",
        .root_module = module_mod,
    });
    b.installArtifact(exe);
}
