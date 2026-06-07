# Module Authoring

Write Dagger modules in Zig with comptime type reflection.

## Basic Module

```zig
const std = @import("std");
const dagger = @import("dagger_sdk");

const MyModule = struct {
    pub fn build(
        self: *const MyModule,
        ctx: *dagger.module.Context,
        source: dagger.Directory,
    ) !dagger.Container {
        _ = self;
        return ctx.dag().container()
            .from("golang:1.23-alpine")
            .withDirectory("/src", source)
            .withWorkdir("/src")
            .withExec(&.{ "go", "build", "./..." });
    }

    pub fn @"test"(
        self: *const MyModule,
        ctx: *dagger.module.Context,
        source: dagger.Directory,
    ) ![]const u8 {
        _ = self;
        const ctr = try ctx.dag().container()
            .from("golang:1.23-alpine")
            .withDirectory("/src", source)
            .withWorkdir("/src")
            .withExec(&.{ "go", "test", "./..." });
        return ctr.stdout();
    }
};

pub fn main(init: std.process.Init) !void {
    return dagger.module.serve(init, MyModule{});
}
```

## Key Rules

### Immutable Receivers

Use `self: *const Self` for all module methods. Mutation during dispatch is a bug; immutable receivers let the dispatcher safely parallelize.

```zig
// Correct
pub fn build(self: *const MyModule, ...) !Container { ... }

// Wrong — breaks dispatcher invariants
pub fn build(self: *MyModule, ...) !Container { ... }
```

### Context Parameter

All exposed methods must take `ctx: *dagger.module.Context` as the second parameter. This provides access to `ctx.dag()` for creating new Dagger objects.

### Return Types

Return Dagger types (`Container`, `Directory`, `File`, `Secret`, `CacheVolume`) or primitive values (`[]const u8`, `bool`, `i32`, etc.).

## Comptime Registration

No macros needed. At compile time, `dispatch.build(MyModule)`:

1. Walks `@typeInfo(MyModule).Struct.decls`
2. Filters to eligible methods (`pub fn (*const Self, *Context, ...)`)
3. Generates specialized invoker shims per method
4. Maps Zig types to Dagger `TypeDef` automatically

Unmappable signatures fail at `zig build`, not at engine dispatch.

## Serving

`dagger.module.serve()` binds to stdin/stdout and processes JSON-RPC style protocol from the Dagger engine.

```zig
pub fn main(init: std.process.Init) !void {
    return dagger.module.serve(init, MyModule{});
}
```

## Development

Run your module:

```bash
dagger call build --arg-0 . --output=./output
```

## See Also

- [`src/module/dispatch.zig`](../src/module/dispatch.zig) — Dispatch implementation
- [`src/module/typedef.zig`](../src/module/typedef.zig) — Type mapping
- [`tests/module_e2e.zig`](../tests/module_e2e.zig) — End-to-end tests
