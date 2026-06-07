const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const spiffe_options = b.addOptions();
    spiffe_options.addOption(bool, "spiffe_enabled", false);

    const dagger_sdk = b.createModule(.{
        .root_source_file = b.path("../src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    dagger_sdk.addOptions("spiffe_options", spiffe_options);

    const ci_mod = b.createModule(.{
        .root_source_file = b.path("full_main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{.{ .name = "dagger_sdk", .module = dagger_sdk }},
    });

    const ci_exe = b.addExecutable(.{
        .name = "module",
        .root_module = ci_mod,
    });
    const install = b.addInstallArtifact(ci_exe, .{});
    const step = b.step("module-runtime", "Install the ci proof module runtime");
    step.dependOn(&install.step);
}
