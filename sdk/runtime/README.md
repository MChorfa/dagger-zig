# dagger-zig module runtime container

This directory documents the **runtime container** that `sdk/main.go`'s
`ModuleRuntime` function returns — the container the Dagger engine
actually spawns for every `dagger call` against a Zig-authored module.

## Contract

The runtime container MUST:

1. Contain a Zig toolchain (pinned `docker.io/ziglang/zig:0.16.0`).
2. Have the user's module source (with generated `build.zig` +
   `build.zig.zon` from `Codegen`) mounted at `/user-module`.
3. Have the dagger-zig SDK library mounted at `/sdk-lib`, so the build
   script can symlink it into the build directory as `.dagger-sdk-lib`
   and the user's `build.zig.zon` can resolve `@import("dagger_sdk")`.
4. Build the user's module via `zig build module-runtime --prefix /out`.
5. Have the module binary as its entrypoint (`/out/bin/module`).

## Why no Dockerfile in here?

Because the runtime is built programmatically by `sdk/main.go` using
Dagger's own container-builder API — there is no Dockerfile. That's the
whole point of Dagger: the container spec IS the Go code in `main.go`'s
`ModuleRuntime` function.

If you want to see what the runtime looks like, read `sdk/main.go`.

## How the SDK library reaches the container

The SDK module (`sdk/dagger.json`, `"source": "."`) ships the Zig library
under `sdk/lib/` (containing `build.zig`, `build.zig.zon`, and `src/`).
When the engine loads the SDK module, `dag.CurrentModule().Source()` is
the `sdk/` directory. `ModuleRuntime` extracts `.Directory("lib")` and
mounts it at `/sdk-lib`.

The build script (`runtimeutil.ModuleBuildScript`) then symlinks
`/sdk-lib` → `$build_dir/.dagger-sdk-lib` so the generated
`build.zig.zon`'s `.path = ".dagger-sdk-lib"` resolves correctly
regardless of the user's source subpath.

## Performance

Cold start (no cache): ~15s for `zig build` inside the runner (toolchain
is pre-baked into the image; no runtime download).

Warm start (cached Zig cache volume `dagger-zig-build-v2`): ~1s.
