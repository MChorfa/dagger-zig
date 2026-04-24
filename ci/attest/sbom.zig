const std = @import("std");
const dagger = @import("dagger_sdk");

pub const SbomGenerator = struct {
    pub fn cyclonedx(
        self: *const SbomGenerator,
        ctx: *dagger.Context,
        source: dagger.Directory,
    ) !dagger.File {
        _ = self;
        const scanner = try ctx
            .container()
            .from("anchore/syft:latest")
            .withDirectory("/src", source)
            .withWorkdir("/src")
            .withExec(&.{ "syft", "dir:/src", "-o", "cyclonedx-json=/sbom.cdx.json" });

        return try scanner.file("/sbom.cdx.json");
    }

    pub fn spdx(
        self: *const SbomGenerator,
        ctx: *dagger.Context,
        source: dagger.Directory,
    ) !dagger.File {
        _ = self;
        const scanner = try ctx
            .container()
            .from("anchore/syft:latest")
            .withDirectory("/src", source)
            .withWorkdir("/src")
            .withExec(&.{ "syft", "dir:/src", "-o", "spdx-json=/sbom.spdx.json" });

        return try scanner.file("/sbom.spdx.json");
    }
};

pub fn main(init: std.process.Init) !void {
    return dagger.module.serve(init, SbomGenerator{});
}
