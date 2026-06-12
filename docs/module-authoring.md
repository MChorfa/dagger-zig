# Module Authoring

Write Dagger modules in Zig with comptime type reflection.

## Shape

A module is a Zig struct with methods that follow the expected dispatch shape:

- first argument: `self: *const Self` or `self: *Self`
- second argument: `ctx: *dagger.module.Context`
- optional user arguments after that

The dispatcher ignores `init`, `deinit`, and `default`, and only exposes
eligible methods as module functions.

## Minimal Module

```zig
const std = @import("std");
const dagger = @import("dagger_sdk");

const MyModule = struct {
    tenant: []const u8 = "default",

    pub fn build(
        self: *const MyModule,
        ctx: *dagger.module.Context,
        source: dagger.Directory,
    ) !dagger.Container {
        _ = self;
        return try ctx.dag().container()
            .from("golang:1.23-alpine")
            .withDirectory("/src", source)
            .withWorkdir("/src")
            .withExec(&.{ "go", "build", "./..." });
    }
};

pub fn main(init: std.process.Init) !void {
    return dagger.module.serve(init, MyModule{ .tenant = "acme" });
}
```

## Dispatch Model

`src/module/dispatch.zig` builds a table of:

- method name
- function signature metadata
- generated invoker shim

That shim handles JSON argument deserialization, invokes the Zig method, and
serializes the return value back to the engine.

## Type Mapping

`src/module/typedef.zig` maps Zig types to Dagger type definitions.

Supported categories include:

- `void`
- booleans
- integers
- `[]const u8`
- slices and arrays
- optionals
- Dagger handle types such as `Container`, `Directory`, `File`, `Secret`, and `CacheVolume`
- user structs and enums
- `anyerror!T` payloads

If the type cannot be mapped, the build fails at comptime.

## Context

`dagger.module.Context` gives module methods access to:

- `ctx.dag()` for building Dagger queries
- the module arena and allocator
- optional SPIFFE workload identity access when SPIFFE is enabled

## Serving

`dagger.module.serve(init, module_instance)` binds the module to the Dagger
engine and runs the request loop.

## Practical Rules

- Keep module receivers immutable unless mutation is genuinely required.
- Prefer plain values and Dagger handles over custom marshalling layers.
- Put all runtime plumbing in the module, not in user-facing helpers.
- Let comptime fail early when a method signature does not fit the contract.

## Related Pages

- [Architecture](architecture.md)
- [Query Builder](query-builder.md)
- [API Reference](api-reference.md)
