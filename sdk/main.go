// Package main implements the Dagger Module SDK interface for Zig.
//
// # What this is
//
// When a user writes this in their dagger.json:
//
//	{
//	  "name": "my-pipeline",
//	  "sdk": "github.com/MChorfa/dagger-zig/sdk@v0.4.0",
//	  "source": "."
//	}
//
// the Dagger engine clones dagger-zig@v0.4.0, goes into the `sdk/`
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
	"path/filepath"

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
	userSrcPath   = "/user-module"    // user's module source (workdir)
	sdkLibPath    = "/sdk-lib"        // vendored dagger_sdk Zig library
	schemaPath    = "/schema.json"    // introspection JSON (mounted if provided)
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

// InitModule scaffolds a new Zig module inside a workspace.
//
// Forward-compatibility hook for the workspace SDK contract (dagger/dagger
// main: core/sdk/module.go AsModuleInitializer). The engine discovers this
// function by name and calls it during `dagger module init <sdk>`; engines
// on the v0.21.x line never invoke it. Required shape:
//
//	initModule(ws: Workspace!, name: String!, path: String!, ...): Changeset!
//
// `name` is the module name and `path` the module's directory inside the
// workspace. The returned Changeset carries only the SDK-owned files; the
// engine merges it with its own manifest edits (dagger-module.toml is
// engine-owned and intentionally not written here).
//
// We do not implement `targetRuntime`: when absent, the engine records the
// SDK's own installed ref as [runtime] source, which is correct — this
// module is both the SDK and the runtime.
func (m *DaggerZigSdk) InitModule(
	ctx context.Context,
	ws *dagger.Workspace,
	name string,
	path string,
) (*dagger.Changeset, error) {
	before := ws.Directory(path)
	after := before.
		WithNewFile("main.zig", zigcodegen.UserModuleMainZig(name)).
		WithNewFile("build.zig", zigcodegen.UserModuleBuildZig()).
		WithNewFile("build.zig.zon", zigcodegen.UserModuleBuildZigZon()).
		WithNewFile("internal/dagger/dagger.gen.zig", zigcodegen.GeneratedModuleBindings())

	return after.Changes(before), nil
}

// InitClient scaffolds a Zig client for an installed module.
//
// Forward-compatibility hook for the workspace SDK contract (dagger/dagger
// main: core/sdk/module.go AsClientInitializer). The engine calls it during
// `dagger module client add`; engines on the v0.21.x line never invoke it.
// Required shape:
//
//	initClient(ws: Workspace!, path: String!, module: String!, ...): Changeset!
//
// `path` is the client output directory inside the workspace and `module`
// the name of the module the client targets. The emitted scaffold compiles
// the session layer only: Zig has no dynamic dispatch, so calling the
// target module's functions requires typed stubs that a future client
// generator will emit from the module's typedefs.
func (m *DaggerZigSdk) InitClient(
	ctx context.Context,
	ws *dagger.Workspace,
	path string,
	module string,
) (*dagger.Changeset, error) {
	before := ws.Directory(path)

	// Clients run on the host (`dagger run zig build run`), outside the
	// runtime container — so there is no /sdk-lib mount. Vendor the SDK
	// library into the client directory instead; build.zig.zon resolves
	// dagger_sdk from that path.
	sdkLibDir := dag.CurrentModule().Source().Directory("lib")

	after := before.
		WithNewFile("main.zig", zigcodegen.UserClientMainZig(module)).
		WithNewFile("build.zig", zigcodegen.UserClientBuildZig()).
		WithNewFile("build.zig.zon", zigcodegen.UserModuleBuildZigZon()).
		WithNewFile("internal/dagger/dagger.gen.zig", zigcodegen.GeneratedModuleBindings()).
		WithDirectory(sdkLibLinkDir, sdkLibDir)

	return after.Changes(before), nil
}

// Codegen returns the generated-code changeset that `dagger develop`
// applies to the user's source tree. We emit three files:
//
//   - build.zig      — wires dagger_sdk as a dependency and installs a
//     `module` executable via the `module-runtime` step.
//   - build.zig.zon  — declares the dagger_sdk path dependency pointing
//     at .dagger-sdk-lib (symlinked to /sdk-lib at
//     runtime by ModuleBuildScript).
//   - internal/dagger/dagger.gen.zig — re-export shim so users can also
//     `@import("dagger").Container` etc.
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

	// Resolve the source subpath so generated files land inside the
	// module's source directory, not at the context directory root.
	// When the module is nested (e.g. examples/e2e-module/ within a
	// repo), ContextDirectory() returns the repo root and we need to
	// prepend the subpath to each WithNewFile path.
	subpath, err := modSource.SourceSubpath(ctx)
	if err != nil {
		return nil, fmt.Errorf("resolve source subpath: %w", err)
	}

	buildZigPath := filepath.Join(subpath, "build.zig")
	buildZigZonPath := filepath.Join(subpath, "build.zig.zon")
	genZigPath := filepath.Join(subpath, "internal/dagger/dagger.gen.zig")

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
		WithNewFile(buildZigPath, zigcodegen.UserModuleBuildZig()).
		WithNewFile(buildZigZonPath, zigcodegen.UserModuleBuildZigZon()).
		WithNewFile(genZigPath, genZig)

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
