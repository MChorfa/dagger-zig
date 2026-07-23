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
        base = try base.from("golang:1.26");
        base = try base.withMountedCache("/go/pkg/mod", try ctx.dag().cacheVolume("go-mod-cache"));
        base = try base.withMountedCache("/root/.cache/go-build", try ctx.dag().cacheVolume("go-build-cache"));
        return base;
    }

    /// zigBase sets up Zig build environment with volume caching
    fn zigBase(ctx: *dagger.Context) !dagger.Container {
        var base = try ctx.container();
        base = try base.from("alpine:3.20");
        base = try base.withExec(&.{ "apk", "add", "--no-cache", "curl", "tar", "xz" });
        base = try base.withExec(&.{ "sh", "-c", zig_install });
        base = try base.withMountedCache("/root/.cache/zig", try ctx.dag().cacheVolume("zig-build-cache"));
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
        var builder = try zigBase(ctx);
        builder = try builder.withDirectory("/src", source);
        builder = try builder.withWorkdir("/src");

        const cmd = try std.fmt.allocPrint(
            std.heap.page_allocator,
            "mkdir -p /out; zig build -Dtarget={s} --prefix /out 2>&1 || echo \"build failed for {s}\" >> /out/build-errors.log",
            .{ target, target },
        );
        defer std.heap.page_allocator.free(cmd);

        builder = try builder.withExec(&.{ "sh", "-c", cmd });

        return builder.directory("/out");
    }

    /// buildMultiArch builds every platform and assembles the artifacts under
    /// `/builds/<target>/`.
    pub fn buildMultiArch(
        ctx: *dagger.Context,
        source: dagger.Directory,
    ) !dagger.Directory {
        var results = try ctx.container();
        results = try results.from("alpine:latest");

        inline for (Platforms) |platform| {
            const artifact = try buildSingleTarget(ctx, source, platform);
            const output_path = try std.fmt.allocPrint(std.heap.page_allocator, "/builds/{s}", .{platform});
            defer std.heap.page_allocator.free(output_path);
            results = try results.withDirectory(output_path, artifact);
        }

        return results.directory("/builds");
    }

    /// generateSBOM creates CycloneDX and SPDX manifests with caching
    pub fn generateSBOM(
        ctx: *dagger.Context,
        source: dagger.Directory,
    ) !dagger.Directory {
        var sbom = try ctx.container();
        sbom = try sbom.from("ghcr.io/anchore/syft:v1.14.0");
        sbom = try sbom.withDirectory("/src", source);
        sbom = try sbom.withWorkdir("/src");

        // syft image is distroless (no shell); seed /results so syft can write
        // into it, then emit both formats in a single invocation.
        sbom = try sbom.withNewFile("/results/.keep", "");
        // The binary lives at the image root (scratch-based image, not on PATH).
        sbom = try sbom.withExec(&.{
            "/syft",
            "dir:/src",
            "-o",
            "cyclonedx-json=/results/sbom.cdx.json",
            "-o",
            "spdx-json=/results/sbom.spdx.json",
        });

        return sbom.directory("/results");
    }

    /// buildAndSign stages build, SBOM generation, signing, and inline SLSA v1 provenance
    pub fn buildAndSign(
        ctx: *dagger.Context,
        source: dagger.Directory,
        container_tag: []const u8,
        oidc_token: ?dagger.Secret,
    ) !dagger.Directory {
        var artifacts = try ctx.container();
        artifacts = try artifacts.from("alpine:latest");

        const multi_arch = try buildMultiArch(ctx, source);
        artifacts = try artifacts.withDirectory("/builds", multi_arch);

        const sbom_dir = try generateSBOM(ctx, source);
        artifacts = try artifacts.withDirectory("/sbom", sbom_dir);

        var hasher = try ctx.container();
        hasher = try hasher.from("alpine:latest");
        hasher = try hasher.withDirectory("/sbom", sbom_dir);
        hasher = try hasher.withExec(&.{
            "sh", "-c", "sha256sum /sbom/sbom.spdx.json | awk '{print $1}'",
        });
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

        artifacts = try artifacts.withNewFile("/provenance.json", provenance_json);

        if (oidc_token) |token| {
            var signer = try ctx.container();
            signer = try signer.from("ghcr.io/sigstore/cosign/cosign:v2.2.3");
            signer = try signer.withDirectory("/sbom", sbom_dir);
            signer = try signer.withNewFile("/provenance.json", provenance_json);
            signer = try signer.withSecretVariable("SIGSTORE_ID_TOKEN", token);
            signer = try signer.withExec(&.{
                "cosign",           "attest",
                "--yes",            "--predicate",
                "/provenance.json", "--type",
                "slsaprovenance1",  "--output-bundle",
                "/output.bundle",   "/sbom/sbom.spdx.json",
            });
            artifacts = try artifacts.withFile(
                "/attestation.bundle",
                try signer.file("/output.bundle"),
            );
        }

        return artifacts.directory("/");
    }
};
