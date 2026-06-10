const std = @import("std");
const dagger = @import("dagger_sdk");

pub const SbomGenerator = struct {
    pub fn cyclonedx(
        self: *const SbomGenerator,
        ctx: *dagger.Context,
        source: dagger.Directory,
    ) !dagger.File {
        _ = self;
        var scanner = try ctx.container();
        scanner = try scanner.from("ghcr.io/anchore/syft:v1.14.0");
        scanner = try scanner.withDirectory("/src", source);
        scanner = try scanner.withNewFile("/results/.keep", "");
        scanner = try scanner.withExec(&.{
            "/syft", "dir:/src", "-o", "cyclonedx-json=/results/sbom.cdx.json",
        });
        return scanner.file("/results/sbom.cdx.json");
    }

    pub fn spdx(
        self: *const SbomGenerator,
        ctx: *dagger.Context,
        source: dagger.Directory,
    ) !dagger.File {
        _ = self;
        var scanner = try ctx.container();
        scanner = try scanner.from("ghcr.io/anchore/syft:v1.14.0");
        scanner = try scanner.withDirectory("/src", source);
        scanner = try scanner.withNewFile("/results/.keep", "");
        scanner = try scanner.withExec(&.{
            "/syft", "dir:/src", "-o", "spdx-json=/results/sbom.spdx.json",
        });
        return scanner.file("/results/sbom.spdx.json");
    }
};

pub fn main(init: std.process.Init) !void {
    return dagger.module.serve(init, SbomGenerator{});
}
