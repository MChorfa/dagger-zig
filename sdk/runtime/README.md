# dagger-zig module runtime container

This directory documents the **runtime container** that `sdk/main.go`'s
`ModuleRuntime` function returns — the container the Dagger engine
actually spawns for every `dagger call` against a Zig-authored module.

## Contract

The runtime container MUST:

1. Contain a Zig toolchain (or the user's pre-built module binary).
2. Have the user's module source mounted at `/user-module`.
3. Have dagger-zig mounted at `/sdk-lib`, so the user's `build.zig.zon`
   can resolve `@import("dagger_sdk")`.
4. Build the user's module on container start (or use a pre-built binary
   if available).
5. Have the module binary as its entrypoint.

## Why no Dockerfile in here?

Because the runtime is built programmatically by `sdk/main.go` using
Dagger's own container-builder API — there is no Dockerfile. That's the
whole point of Dagger: the container spec IS the Go code in `main.go`'s
`ModuleRuntime` function.

If you want to see what the runtime looks like, read `sdk/main.go`.

## Performance

Cold start (no cache): ~20s for `zig build` inside the runner.
Warm start (cached Zig cache volume): ~1s.

The `dagger-zig-build-v1` cache volume is shared across every Zig module
the engine has ever built, amortising the toolchain setup.

In v0.2 we'll publish pre-compiled module binaries as OCI artifacts to
skip the zig-build step entirely — that gets cold start under 1s.
