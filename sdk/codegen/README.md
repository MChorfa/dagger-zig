# dagger-zig codegen

This directory is the **per-module codegen layer** — the part that emits
`internal/dagger/dagger.gen.zig` when a user runs `dagger develop` on
their Zig module.

## Current state (v0.1)

Minimal. The `Codegen` function in `sdk/main.go` writes a Zig 0.16-safe
re-export shim:

```zig
const sdk = @import("dagger_sdk");

pub const module = sdk.module;
pub const Container = sdk.Container;
pub const Directory = sdk.Directory;
pub const connect = sdk.connect;
```

That's enough because dagger-zig's generated API surface is currently
hand-written in `src/gen_sample.zig`. When users author a module, their
`build.zig.zon` pulls in dagger-zig as a dep, and `@import("dagger_sdk")`
gives them the whole client. No per-user-module code generation yet.

We use explicit aliases instead of `usingnamespace` because Zig 0.16 removed
that syntax.

## v0.1.1 plan

Real codegen: when the engine supplies introspection JSON for the user's
module dependencies, emit typed bindings specific to those dependencies.

The emitter is the existing `codegen/src/emit.zig` tool at the repo root
(the one that emits `src/gen.zig` from the full schema). For per-user
codegen, we run that same tool with a restricted schema (only the types
the user's deps export).

Pipeline:

```
user runs `dagger develop`
  → engine calls sdk.Codegen(modSource, introspectionJson)
    → sdk/main.go reads introspectionJson
      → sdk/main.go invokes dagger-codegen (our existing Zig binary)
        with the JSON as stdin, --mode=module
        → emits dagger.gen.zig containing only user-dep types
    → sdk/main.go returns that file as part of the GeneratedCode changeset
```

This is the same architecture Go SDK uses, ported to Zig.

## Why this layer exists separately from `codegen/` at the repo root

`codegen/` at the repo root emits `src/gen.zig` for dagger-zig ITSELF —
the full Dagger schema as a Zig API. That's what `zig build codegen`
updates.

`sdk/codegen/` (this directory) is the per-user-module codegen — the
thing that runs when someone ELSE'S module uses dagger-zig as its SDK.
It will (in v0.1.1) shell out to the `codegen/` tool with module-scoped
input.

Two codegen stages, one shared emitter. Clean.
