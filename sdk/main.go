// Package main implements the Dagger Module SDK interface for Zig.
//
// # What this is
//
// When a user writes this in their dagger.json:
//
//	{
//	  "name": "my-pipeline",
//	  "sdk": "github.com/MChorfa/dagger-zig/sdk@v0.3.5",
//	  "source": "."
//	}
//
// the Dagger engine clones dagger-zig@v0.3.5, goes into the `sdk/`
// directory, and invokes this module. This module implements two
// functions the engine expects from any Module SDK:
//
//   - ModuleRuntime(modSource, introspectionJson) → Container
//     Returns a container that, when run, IS the user's Dagger module.
//     The engine spawns this container whenever `dagger call` dispatches a
//     function on the user's module.
//
//   - Codegen(modSource, introspectionJson) → GeneratedCode
//     Returns the changeset that `dagger develop` applies to the user's
//     source: build.zig, build.zig.zon, and internal/dagger/dagger.gen.zig.
//
// # Why Go and not Zig?
//
// This is the bootstrap layer: the code the engine loads to make Zig
// modules POSSIBLE. Writing it in Zig would be a chicken-and-egg problem —
// the engine can't load a Zig Module SDK before a Zig Module SDK exists.
//
// Analogy: Cargo is written in Rust, but Cargo's installer (the thing that
// puts Cargo on your machine) is a shell script. Same pattern.
//
// Everything ABOVE this layer (the SDK library, the CI pipeline, users'
// modules) is 100% Zig. This file is ~200 lines of shim.
package main

import (
	"context"
	"fmt"

	zigcodegen "dagger/dagger-zig-sdk/codegen"
	"dagger/dagger-zig-sdk/internal/dagger"
	runtimeutil "dagger/dagger-zig-sdk/runtimeutil"
)

// The Zig toolchain version. Pinned — bumping it is a coordinated release
// because every module built by this SDK inherits the Zig version.
//
// We install from the official ziglang.org tarball rather than a Docker
// image because no multi-arch (amd64 + arm64) Zig 0.16 image exists on
// Docker Hub as of 2026-07. The tarball approach works on both x86_64
// and aarch64 Linux runners.
const zigVersion = "0.16.0"

// Paths inside the runtime container.
const (
	userSrcPath   = "/user-module" // user's module source (workdir)
	sdkLibPath    = "/sdk-lib"     // vendored dagger_sdk Zig library
	schemaPath    = "/schema.json" // introspection JSON (mounted if provided)
	sdkLibLinkDir = ".dagger-sdk-lib" // relative symlink name inside build dir
)

type DaggerZigSdk struct{}

// ModuleRuntime returns a container that runs the user's compiled module.
//
// Contract with the engine:
//   - When the engine spawns this container, it sets DAGGER_SESSION_PORT +
//     DAGGER_SESSION_TOKEN. Our entrypoint ignores them; the user's
//     compiled binary reads them via dagger.connect().
//   - Stdout of the entrypoint is the module's return payload.
//   - Exit code 0 means success; non-zero is dispatch failure.
func (m *DaggerZigSdk) ModuleRuntime(
	ctx context.Context,
	modSource *dagger.ModuleSource,
	introspectionJson *dagger.File,
) (*dagger.Container, error) {
	userDir := modSource.ContextDirectory()
	subpath, err := modSource.SourceSubpath(ctx)
	if err != nil {
		return nil, fmt.Errorf("resolve source subpath: %w", err)
	}

	// dag.CurrentModule().Source() is the SDK module's own source directory
	// (sdk/). The Zig library lives under sdk/lib/ — that's what we mount
	// so the user's build.zig.zon can resolve @import("dagger_sdk").
	sdkLibDir := dag.CurrentModule().Source().Directory("lib")

	ctr := dag.Container().
		From("alpine:3.20").
		WithExec([]string{"apk", "add", "--no-cache", "curl", "tar", "xz"}).
		WithExec([]string{"sh", "-c", `
			ARCH=$(uname -m)
			if [ "$ARCH" = "x86_64" ]; then
				ZIG_ARCH="x86_64"
			elif [ "$ARCH" = "aarch64" ]; then
				ZIG_ARCH="aarch64"
			else
				echo "Unsupported architecture: $ARCH" && exit 1
			fi
			curl -L https://ziglang.org/download/` + zigVersion + `/zig-${ZIG_ARCH}-linux-` + zigVersion + `.tar.xz | tar -xJ -C /usr/local
			ln -s /usr/local/zig-${ZIG_ARCH}-linux-` + zigVersion + `/zig /usr/local/bin/zig
		`}).
		WithMountedCache("/root/.cache/zig", dag.CacheVolume("dagger-zig-build-v2")).
		WithDirectory(userSrcPath, userDir).
		WithMountedDirectory(sdkLibPath, sdkLibDir).
		WithWorkdir(userSrcPath)

	if introspectionJson != nil {
		ctr = ctr.WithMountedFile(schemaPath, introspectionJson)
	}

	// The build script:
	//   1. Finds the build directory (source subpath or root).
	//   2. Symlinks /sdk-lib into the build dir as .dagger-sdk-lib so the
	//      generated build.zig.zon's relative .path = ".dagger-sdk-lib"
	//      resolves correctly regardless of the source subpath.
	//   3. Runs `zig build module-runtime` (or plain `zig build` fallback)
	//      with --prefix /out so the binary lands at /out/bin/module.
	ctr = ctr.WithExec([]string{
		"sh", "-c",
		runtimeutil.ModuleBuildScript(userSrcPath, subpath, sdkLibPath, sdkLibLinkDir),
	}).
		WithEntrypoint([]string{"/out/bin/module"})

	return ctr, nil
}

// Codegen returns the generated-code changeset that `dagger develop`
// applies to the user's source tree. We emit three files:
//
//   - build.zig      — wires dagger_sdk as a dependency and installs a
//                      `module` executable via the `module-runtime` step.
//   - build.zig.zon  — declares the dagger_sdk path dependency pointing
//                      at .dagger-sdk-lib (symlinked to /sdk-lib at
//                      runtime by ModuleBuildScript).
//   - internal/dagger/dagger.gen.zig — re-export shim so users can also
//                      `@import("dagger").Container` etc.
//
// If the user already has a build.zig or build.zig.zon, Codegen still
// overwrites them — the SDK owns the build graph. Users customise their
// module by editing main.zig, not the build files. (A future version can
// detect existing build files and merge.)
func (m *DaggerZigSdk) Codegen(
	ctx context.Context,
	modSource *dagger.ModuleSource,
	introspectionJson *dagger.File,
) (*dagger.GeneratedCode, error) {
	userDir := modSource.ContextDirectory()

	// Generate the dagger.gen.zig bindings from the introspection JSON.
	// If introspection is unavailable (e.g. offline), fall back to the
	// static stub so codegen still produces a valid changeset.
	genZig := zigcodegen.GeneratedModuleBindings()
	if introspectionJson != nil {
		content, err := introspectionJson.Contents(ctx)
		if err != nil {
			return nil, fmt.Errorf("read introspection: %w", err)
		}
		generated, err := zigcodegen.GenerateZigTypes([]byte(content))
		if err != nil {
			return nil, fmt.Errorf("generate zig types: %w", err)
		}
		genZig = generated
	}

	withGen := userDir.
		WithNewFile("build.zig", zigcodegen.UserModuleBuildZig()).
		WithNewFile("build.zig.zon", zigcodegen.UserModuleBuildZigZon()).
		WithNewFile("internal/dagger/dagger.gen.zig", genZig)

	return dag.GeneratedCode(withGen).
		WithVCSGeneratedPaths([]string{
			"build.zig",
			"build.zig.zon",
			"internal/dagger/dagger.gen.zig",
		}).
		WithVCSIgnoredPaths([]string{
			"zig-cache",
			"zig-out",
			".zig-cache",
			".dagger-sdk-lib",
		}), nil
}
