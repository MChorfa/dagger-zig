const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const dagger_sdk = b.createModule(.{
        .root_source_file = b.path("../../src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const full_ci_mod = b.createModule(.{
        .root_source_file = b.path("main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{.{ .name = "dagger_sdk", .module = dagger_sdk }},
    });

    const full_ci_exe = b.addExecutable(.{
        .name = "module",
        .root_module = full_ci_mod,
    });
    const install = b.addInstallArtifact(full_ci_exe, .{});
    const step = b.step("module-runtime", "Install the full CI module runtime");
    step.dependOn(&install.step);
}
