// Package main implements the Dagger Module SDK interface for Zig.
//
// # What this is
//
// When a user writes this in their dagger.json:
//
//	{
//	  "name": "my-pipeline",
//	  "sdk": "github.com/MChorfa/dagger-zig/sdk@v0.3.0",
//	  "source": "."
//	}
//
// the Dagger engine clones dagger-zig@v0.1.0, goes into the `sdk/`
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
//     source: the internal/dagger/dagger.gen.zig that lets them call
//     dag.Container() etc. from inside their module.
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

// The Zig toolchain image we use for every module build. Pinned — bumping
// it is a coordinated release because every module built by this SDK
// inherits the Zig version.
const zigImage = "kassany/ziglang:0.16.0"

// Path inside the runtime container where we stage user module source.
const userSrcPath = "/user-module"
const sdkLibPath = "/sdk-lib"
const schemaPath = "/schema.json"

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
	// Walk inputs:
	//   modSource.ContextDirectory() — user's module source, rooted at their repo
	//   modSource.SourceSubpath()    — the sub-dir inside that root
	userDir := modSource.ContextDirectory()
	subpath, err := modSource.SourceSubpath(ctx)
	if err != nil {
		return nil, fmt.Errorf("resolve source subpath: %w", err)
	}

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
			curl -L https://ziglang.org/download/0.16.0/zig-${ZIG_ARCH}-linux-0.16.0.tar.xz | tar -xJ -C /usr/local
			ln -s /usr/local/zig-${ZIG_ARCH}-linux-0.16.0/zig /usr/local/bin/zig
		`}).
		WithMountedCache("/root/.cache/zig", dag.CacheVolume("dagger-zig-build-v1")).
		WithDirectory(userSrcPath, userDir).
		WithMountedDirectory(sdkLibPath, dag.CurrentModule().Source()).
		WithWorkdir(userSrcPath)

	if introspectionJson != nil {
		ctr = ctr.WithMountedFile(schemaPath, introspectionJson)
	}

	// The user's module is an executable that imports `dagger_sdk` and
	// calls `dagger.module.serve(init, UserModule{})`. We generate a
	// minimal build.zig.zon if the user didn't provide one, then build.
	ctr = ctr.WithExec([]string{
		"sh", "-c",
		runtimeutil.ModuleBuildScript(userSrcPath, subpath),
	}).
		WithEntrypoint([]string{"/out/bin/module"})

	return ctr, nil
}

// Codegen returns the generated-code changeset that `dagger develop`
// applies to the user's source tree. For Zig, we emit
// `internal/dagger/dagger.gen.zig` with the typed client bindings.
//
// In v0.1 this is minimal — we copy a pre-generated stub. The real
// codegen (invoking our `dagger-codegen` binary against the introspection
// JSON) lands in v0.1.1, at which point Zig-native module authoring is
// as ergonomic as Go/TS.
func (m *DaggerZigSdk) Codegen(
	ctx context.Context,
	modSource *dagger.ModuleSource,
	introspectionJson *dagger.File,
) (*dagger.GeneratedCode, error) {
	_ = ctx
	_ = introspectionJson

	// For v0.1 we produce a fixed skeleton; the user's module then imports
	// `dagger_sdk` directly (which we mount into their container via
	// ModuleRuntime), so this generated file is small.
	userDir := modSource.ContextDirectory()

	withGen := userDir.
		WithNewFile("internal/dagger/dagger.gen.zig", zigcodegen.GeneratedModuleBindings())

	// GeneratedCode expects a Directory, not a Changeset (API changed after CLI v0.12.5)
	return dag.GeneratedCode(withGen).
		WithVCSGeneratedPaths([]string{"internal/dagger/dagger.gen.zig"}).
		WithVCSIgnoredPaths([]string{"zig-cache", "zig-out", ".zig-cache"}), nil
}
