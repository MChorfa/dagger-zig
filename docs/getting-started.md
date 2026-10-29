# Getting Started

This guide uses the published v0.4.0 SDK with Zig 0.16 or 0.17 and Dagger
v0.21.9. A live Dagger engine is required to run the pipeline, but compilation
can run offline once dependencies are cached.

## 1. Add the SDK

Create a project and let Zig calculate and record the dependency hash:

```bash
mkdir my-pipeline
cd my-pipeline
zig init
zig fetch --save=dagger_sdk https://github.com/MChorfa/dagger-zig/archive/refs/tags/v0.4.0.tar.gz
```

Keep the generated fingerprint and paths in `build.zig.zon`. The top-level
`.version` describes **your package** (for example, `0.1.0`), independently of
the SDK release. Commit the URL and hash emitted by `zig fetch`; do not copy a
placeholder hash. `build.zig.zon` uses Zig Object Notation, not JSON.

The published v0.4.0 archive still declares internal package version `0.3.5`,
so its computed hash begins with `dagger_sdk-0.3.5-`. Keep that hash unchanged;
it identifies the archive contents, not the release tag. Metadata corrections
in newer commits do not rewrite the published archive.

Replace `build.zig` with:

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const sdk = b.dependency("dagger_sdk", .{
        .target = target,
        .optimize = optimize,
    });
    const exe = b.addExecutable(.{
        .name = "my-pipeline",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{.{ .name = "dagger_sdk", .module = sdk.module("dagger_sdk") }},
        }),
    });
    b.installArtifact(exe);
    const run = b.addRunArtifact(exe);
    b.step("run", "Run the pipeline").dependOn(&run.step);
}
```

## 2. Open a client

Replace `src/main.zig` with:

```zig
const std = @import("std");
const dagger = @import("dagger_sdk");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var client = try dagger.connect(gpa, io, .{});
    defer client.close();

    // Unwrap each fallible builder call before selecting the next method.
    const ctr = try client.dag().container(null);
    const alpine = try ctr.from("alpine:latest", null);
    const exec = try alpine.withExec(&.{ "echo", "hello from zig" }, null, null, null, null, null, null, null, null, null, null);
    const out = try exec.stdout();
    defer gpa.free(out);

    std.debug.print("{s}", .{out});
}
```

## 3. Build and run

```bash
zig build
dagger run -- zig build run
```

To run the equivalent example directly from a dagger-zig repository checkout:

```bash
dagger run -- zig build run-first-pipeline
```

## What to read next

- [Examples](examples.md) for more pipeline patterns
- [Module Authoring](module-authoring.md) for turning Zig structs into Dagger modules
- [Async Patterns](async-patterns.md) for concurrent fan-out
