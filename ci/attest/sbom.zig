const std = @import("std");
const dagger = @import("dagger_sdk");

pub const SbomGenerator = struct {
    pub fn cyclonedx(
        self: *const SbomGenerator,
        ctx: *dagger.Context,
        source: dagger.Directory,
    ) !dagger.File {
        _ = self;
        var source_id = try source.id();
        defer source_id.deinit(ctx.allocator());

        var scanner = try ctx.container();
        scanner = try scanner.from("ghcr.io/anchore/syft:v1.14.0", null);
        scanner = try scanner.withDirectory("/src", source_id.value, null, null, null, null, null, null);
        scanner = try scanner.withNewFile("/results/.keep", "", null, null, null);
        scanner = try scanner.withExec(&.{
            "/syft", "dir:/src", "-o", "cyclonedx-json=/results/sbom.cdx.json",
        }, null, null, null, null, null, null, null, null, null, null);
        return scanner.file("/results/sbom.cdx.json", null);
    }

    pub fn spdx(
        self: *const SbomGenerator,
        ctx: *dagger.Context,
        source: dagger.Directory,
    ) !dagger.File {
        _ = self;
        var source_id = try source.id();
        defer source_id.deinit(ctx.allocator());

        var scanner = try ctx.container();
        scanner = try scanner.from("ghcr.io/anchore/syft:v1.14.0", null);
        scanner = try scanner.withDirectory("/src", source_id.value, null, null, null, null, null, null);
        scanner = try scanner.withNewFile("/results/.keep", "", null, null, null);
        scanner = try scanner.withExec(&.{
            "/syft", "dir:/src", "-o", "spdx-json=/results/sbom.spdx.json",
        }, null, null, null, null, null, null, null, null, null, null);
        return scanner.file("/results/sbom.spdx.json", null);
    }
};

pub fn main(init: std.process.Init) !void {
    return dagger.module.serve(init, SbomGenerator{});
}
