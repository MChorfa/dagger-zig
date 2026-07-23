const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const dagger_sdk = b.createModule(.{
        .root_source_file = b.path("../../sdk/lib/src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    // The orchestration submodules live in sibling directories outside this
    // module's root, so Zig file imports cannot reach them. Wire each as a
    // named module (sharing the single dagger_sdk instance so SDK types unify).
    const security_mod = b.createModule(.{
        .root_source_file = b.path("../security/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{.{ .name = "dagger_sdk", .module = dagger_sdk }},
    });
    const build_mod = b.createModule(.{
        .root_source_file = b.path("../build/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{.{ .name = "dagger_sdk", .module = dagger_sdk }},
    });
    const test_mod = b.createModule(.{
        .root_source_file = b.path("../test/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{.{ .name = "dagger_sdk", .module = dagger_sdk }},
    });
    const compliance_mod = b.createModule(.{
        .root_source_file = b.path("../compliance/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{.{ .name = "dagger_sdk", .module = dagger_sdk }},
    });
    const docs_mod = b.createModule(.{
        .root_source_file = b.path("../docs/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{.{ .name = "dagger_sdk", .module = dagger_sdk }},
    });

    const full_ci_mod = b.createModule(.{
        .root_source_file = b.path("main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "dagger_sdk", .module = dagger_sdk },
            .{ .name = "ci_security", .module = security_mod },
            .{ .name = "ci_build", .module = build_mod },
            .{ .name = "ci_test", .module = test_mod },
            .{ .name = "ci_compliance", .module = compliance_mod },
            .{ .name = "ci_docs", .module = docs_mod },
        },
    });

    const full_ci_exe = b.addExecutable(.{
        .name = "module",
        .root_module = full_ci_mod,
    });
    const install = b.addInstallArtifact(full_ci_exe, .{});
    const step = b.step("module-runtime", "Install the full CI module runtime");
    step.dependOn(&install.step);
}
