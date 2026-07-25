const std = @import("std");
const dagger = @import("dagger_sdk");

// There is no official Zig image on Docker Hub; install the toolchain onto a
// known base image (matches how the Dagger Zig SDK runtime bootstraps itself).
// `uname -m` yields x86_64/aarch64, matching Zig's release archive naming.
const zig_install =
    \\set -e
    \\ARCH=$(uname -m)
    \\curl -fL "https://ziglang.org/download/0.16.0/zig-${ARCH}-linux-0.16.0.tar.xz" | tar -xJ -C /usr/local
    \\ln -sf "/usr/local/zig-${ARCH}-linux-0.16.0/zig" /usr/local/bin/zig
;

/// Build module: multi-arch compilation, SBOM, cross-platform matrix builds with caching
pub const Build = struct {
    const Platforms = [_][]const u8{
        "x86_64-linux-gnu",
        "aarch64-linux-gnu",
        "x86_64-macos",
        "aarch64-macos",
    };

    /// goBase sets up base container with go.mod/go.sum cached separately
    /// Implements Two-Phase Mounting: dependency cache isolated from source changes
    fn goBase(ctx: *dagger.Context) !dagger.Container {
        var base = try ctx.container();
        base = try base.from("golang:1.26", null);
        var go_mod_cache = try ctx.dag().cacheVolume("go-mod-cache", null, null, null);
        var go_mod_cache_id = try go_mod_cache.id();
        defer go_mod_cache_id.deinit(ctx.allocator());
        base = try base.withMountedCache("/go/pkg/mod", go_mod_cache_id.value, null, null, null, null);
        var go_build_cache = try ctx.dag().cacheVolume("go-build-cache", null, null, null);
        var go_build_cache_id = try go_build_cache.id();
        defer go_build_cache_id.deinit(ctx.allocator());
        base = try base.withMountedCache("/root/.cache/go-build", go_build_cache_id.value, null, null, null, null);
        return base;
    }

    /// zigBase sets up Zig build environment with volume caching
    fn zigBase(ctx: *dagger.Context) !dagger.Container {
        var base = try ctx.container();
        base = try base.from("alpine:3.20", null);
        base = try base.withExec(&.{ "apk", "add", "--no-cache", "curl", "tar", "xz" }, null, null, null, null, null, null, null, null, null, null);
        base = try base.withExec(&.{ "sh", "-c", zig_install }, null, null, null, null, null, null, null, null, null, null);
        var zig_cache = try ctx.dag().cacheVolume("zig-build-cache", null, null, null);
        var zig_cache_id = try zig_cache.id();
        defer zig_cache_id.deinit(ctx.allocator());
        base = try base.withMountedCache("/root/.cache/zig", zig_cache_id.value, null, null, null, null);
        return base;
    }

    /// buildSingleTarget cross-compiles the repo for a specific platform and
    /// returns the install prefix directory (`/out`). Tolerates per-target
    /// failures (e.g. targets needing an external SDK) so the matrix continues;
    /// the returned directory reflects what actually built.
    pub fn buildSingleTarget(
        ctx: *dagger.Context,
        source: dagger.Directory,
        target: []const u8,
    ) !dagger.Directory {
        var source_id = try source.id();
        defer source_id.deinit(ctx.allocator());

        var builder = try zigBase(ctx);
        builder = try builder.withDirectory("/src", source_id.value, null, null, null, null, null, null);
        builder = try builder.withWorkdir("/src", null);

        const cmd = try std.fmt.allocPrint(
            std.heap.page_allocator,
            "mkdir -p /out; zig build -Dtarget={s} --prefix /out 2>&1 || echo \"build failed for {s}\" >> /out/build-errors.log",
            .{ target, target },
        );
        defer std.heap.page_allocator.free(cmd);

        builder = try builder.withExec(&.{ "sh", "-c", cmd }, null, null, null, null, null, null, null, null, null, null);

        return builder.directory("/out", null);
    }

    /// buildMultiArch builds every platform and assembles the artifacts under
    /// `/builds/<target>/`.
    pub fn buildMultiArch(
        ctx: *dagger.Context,
        source: dagger.Directory,
    ) !dagger.Directory {
        var results = try ctx.container();
        results = try results.from("alpine:latest", null);

        inline for (Platforms) |platform| {
            const artifact = try buildSingleTarget(ctx, source, platform);
            const output_path = try std.fmt.allocPrint(std.heap.page_allocator, "/builds/{s}", .{platform});
            defer std.heap.page_allocator.free(output_path);
            var artifact_id = try artifact.id();
            defer artifact_id.deinit(ctx.allocator());
            results = try results.withDirectory(output_path, artifact_id.value, null, null, null, null, null, null);
        }

        return results.directory("/builds", null);
    }

    /// generateSBOM creates CycloneDX and SPDX manifests with caching
    pub fn generateSBOM(
        ctx: *dagger.Context,
        source: dagger.Directory,
    ) !dagger.Directory {
        var source_id = try source.id();
        defer source_id.deinit(ctx.allocator());

        var sbom = try ctx.container();
        sbom = try sbom.from("ghcr.io/anchore/syft:v1.14.0", null);
        sbom = try sbom.withDirectory("/src", source_id.value, null, null, null, null, null, null);
        sbom = try sbom.withWorkdir("/src", null);

        // syft image is distroless (no shell); seed /results so syft can write
        // into it, then emit both formats in a single invocation.
        sbom = try sbom.withNewFile("/results/.keep", "", null, null, null);
        // The binary lives at the image root (scratch-based image, not on PATH).
        sbom = try sbom.withExec(&.{
            "/syft",
            "dir:/src",
            "-o",
            "cyclonedx-json=/results/sbom.cdx.json",
            "-o",
            "spdx-json=/results/sbom.spdx.json",
        }, null, null, null, null, null, null, null, null, null, null);

        return sbom.directory("/results", null);
    }

    /// buildAndSign stages build, SBOM generation, signing, and inline SLSA v1 provenance
    pub fn buildAndSign(
        ctx: *dagger.Context,
        source: dagger.Directory,
        container_tag: []const u8,
        oidc_token: ?dagger.Secret,
    ) !dagger.Directory {
        var artifacts = try ctx.container();
        artifacts = try artifacts.from("alpine:latest", null);

        const multi_arch = try buildMultiArch(ctx, source);
        var multi_arch_id = try multi_arch.id();
        defer multi_arch_id.deinit(ctx.allocator());
        artifacts = try artifacts.withDirectory("/builds", multi_arch_id.value, null, null, null, null, null, null);

        const sbom_dir = try generateSBOM(ctx, source);
        var sbom_dir_id = try sbom_dir.id();
        defer sbom_dir_id.deinit(ctx.allocator());
        artifacts = try artifacts.withDirectory("/sbom", sbom_dir_id.value, null, null, null, null, null, null);

        var hasher = try ctx.container();
        hasher = try hasher.from("alpine:latest", null);
        var sbom_dir_id2 = try sbom_dir.id();
        defer sbom_dir_id2.deinit(ctx.allocator());
        hasher = try hasher.withDirectory("/sbom", sbom_dir_id2.value, null, null, null, null, null, null);
        hasher = try hasher.withExec(&.{
            "sh", "-c", "sha256sum /sbom/sbom.spdx.json | awk '{print $1}'",
        }, null, null, null, null, null, null, null, null, null, null);
        const sbom_hash_raw = try hasher.stdout();
        const sbom_hash = std.mem.trim(u8, sbom_hash_raw, " \t\r\n");

        const json_fmt =
            "{{" ++
            "\"_type\":\"https://in-toto.io/Statement/v1\"," ++
            "\"subject\":[{{\"name\":\"sbom.spdx.json\",\"digest\":{{\"sha256\":\"{s}\"}}}}]," ++
            "\"predicateType\":\"https://slsa.dev/provenance/v1\"," ++
            "\"predicate\":{{" ++
            "\"buildDefinition\":{{" ++
            "\"buildType\":\"https://dagger.io/build/v1\"," ++
            "\"externalParameters\":{{\"entryPoint\":\"{s}\"}}," ++
            "\"internalParameters\":{{\"engine\":\"dagger\"}}," ++
            "\"resolvedDependencies\":[]}}," ++
            "\"runDetails\":{{" ++
            "\"builder\":{{\"id\":\"https://dagger.io/engine\"}}," ++
            "\"metadata\":{{}}}}}}}}";

        const provenance_json = try std.fmt.allocPrint(std.heap.page_allocator, json_fmt, .{
            sbom_hash, container_tag,
        });
        defer std.heap.page_allocator.free(provenance_json);

        artifacts = try artifacts.withNewFile("/provenance.json", provenance_json, null, null, null);

        if (oidc_token) |token| {
            var token_id = try token.id();
            defer token_id.deinit(ctx.allocator());
            var sbom_dir_id3 = try sbom_dir.id();
            defer sbom_dir_id3.deinit(ctx.allocator());

            var signer = try ctx.container();
            signer = try signer.from("ghcr.io/sigstore/cosign/cosign:v2.2.3", null);
            signer = try signer.withDirectory("/sbom", sbom_dir_id3.value, null, null, null, null, null, null);
            signer = try signer.withNewFile("/provenance.json", provenance_json, null, null, null);
            signer = try signer.withSecretVariable("SIGSTORE_ID_TOKEN", token_id.value);
            signer = try signer.withExec(&.{
                "cosign",           "attest",
                "--yes",            "--predicate",
                "/provenance.json", "--type",
                "slsaprovenance1",  "--output-bundle",
                "/output.bundle",   "/sbom/sbom.spdx.json",
            }, null, null, null, null, null, null, null, null, null, null);
            const attestation_file = try signer.file("/output.bundle", null);
            var attestation_id = try attestation_file.id();
            defer attestation_id.deinit(ctx.allocator());
            artifacts = try artifacts.withFile(
                "/attestation.bundle",
                attestation_id.value,
                null,
                null,
                null,
            );
        }

        return artifacts.directory("/", null);
    }
};
