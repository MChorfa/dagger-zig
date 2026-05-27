# dagger-zig — Architecture

This document explains _why_ the SDK is shaped the way it is. For the _what_,
see the inline doc comments in each source file.

## The four codegen types

Per the upstream `dagger-codegen` skill, "codegen" means four different things
in Dagger. dagger-zig handles them as follows:

| Type                  | What it produces                                                | dagger-zig status                                                                                                                      |
| --------------------- | --------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| 1. In-module bindings | `internal/dagger/dagger.gen.*` for a module to call `dag.*`     | **v0.1: stub** — re-exports `dagger_sdk`. Real codegen in v0.1.1 once per-module schema restriction lands.                             |
| 2. Runtime dispatch   | `invoke()` that routes incoming calls to user fns               | **v0.1: done via comptime.** `dispatch.build(M)` returns a comptime table; specialized invoker shims per method. Offline E2E verified. |
| 3. SDK library        | The shipped `dagger` package itself                             | **v0.1: hand-written in `gen_sample.zig`, with a codegen emitter for later**                                                           |
| 4. Generated clients  | Standalone `Connect()` + `Close()` + types for regular programs | **v0.1: partial** — `connect()` + `close()` work, types are hand-written                                                               |

The Type 2 decision was **comptime registration** — no macros, no source
parsing. The user writes a plain struct:

```zig
const MyModule = struct {
    pub fn build(self: *const MyModule, ctx: *Context, src: Directory) !Container { ... }
};
pub fn main(init: std.process.Init) !void {
    return dagger.module.serve(init, MyModule{});
}
```

At comptime, `dispatch.build(MyModule)` walks `@typeInfo(MyModule).@"struct".decls`,
filters to eligible methods (`pub fn (*const Self, *Context, ...)`), and
generates one specialized invoker shim per method. The shims know how to
deserialize exactly the arg types that method takes — no runtime type
inspection, no registration boilerplate.

See `src/module/dispatch.zig` + `src/module/typedef.zig` + `tests/module_e2e.zig`.

## The handshake

Three strategies, tried in order:

```
┌──────────────────────────────────────────────┐
│ 1. DAGGER_SESSION_PORT + DAGGER_SESSION_TOKEN│  ← inside a module runtime
└──────────────────────────────────────────────┘
                │ found? use as-is, no subprocess
                ▼
┌──────────────────────────────────────────────┐
│ 2. _EXPERIMENTAL_DAGGER_CLI_BIN              │  ← dev override
└──────────────────────────────────────────────┘
                │ found? spawn that binary
                ▼
┌──────────────────────────────────────────────┐
│ 3. `dagger` on PATH                          │  ← the common case
└──────────────────────────────────────────────┘
                │ spawn it
                ▼
      dagger session [--workdir …] [--project …] \
          --label dagger.io/sdk.name:zig \
          --label dagger.io/sdk.version:0.1.0
                │
                ▼
      reads ONE line from stdout:
      {"port":44273,"session_token":"…"}
                │
                ▼
      background thread drains stdout/stderr for the rest of the session
```

The Rust SDK has a 4th strategy: download the CLI from `dl.dagger.io`. We
don't. Rationale documented in the README — supply-chain-purity trumps
convenience in MChorfa/CortAIx's target deployments.

## The query builder

All API calls lower to GraphQL queries of the shape:

```
query{A{B(arg:"v"){C{D}}}}
```

where each nesting level corresponds to one field selection in the user's
chained call. We model this as an immutable singly-linked list:

```
Selection { name, alias, args, prev } ──prev──▶ … ──prev──▶ Selection.root
                                                                   (name=null)
```

Every mutating method allocates a new `Selection` in a client-owned arena.
`build()` walks `prev` pointers to a flat list, then joins them with `{`
and closes with the appropriate number of `}`. The arena is freed when the
client closes.

### Why not refcounting?

Refcounting in Zig is possible (`std.atomic.Value(usize)` + a `Drop` pattern)
but invasive. Since a selection chain can't outlive the session it belongs
to, arena-per-session is strictly simpler and has the same observable
semantics. The one cost: two clients running in the same process don't share
selection memory. That's fine — they shouldn't anyway (each holds its own
GraphQL connection).

### Why pre-serialize args instead of holding them as typed values?

The Rust SDK holds `serde_json::Value` for each arg and serializes lazily
in `build()`. We serialize eagerly in `.arg()` / `.argStr()` and store the
resulting string literal.

Pros:

- Simpler types — `Arg { name, value_literal }` is all we need.
- No generic serialization infrastructure.

Cons:

- An arg is materialized even if the chain is never built (rare in practice).
- Lazy args (for IDs that require awaiting) need a separate `LazyArg` union
  member — we have this in `ArgValue`.

Net: eager is the right call for Zig, where stored polymorphic values would
require type erasure that's annoying without `Arc<dyn Any>`.

## Memory ownership map

Who owns what:

| Memory                                                               | Owner                      | Freed on                                    |
| -------------------------------------------------------------------- | -------------------------- | ------------------------------------------- |
| `Selection` nodes                                                    | `client.arena`             | `client.close()`                            |
| Selection-internal strings (names, aliases, arg names, arg literals) | `client.arena`             | `client.close()`                            |
| Query result bodies (from `gql.query()`)                             | Caller (returned to user)  | Caller's allocator                          |
| `ContainerID`/`DirectoryID`/etc.                                     | Caller                     | `.deinit(allocator)`                        |
| HTTP auth header, endpoint URL                                       | `GraphQLClient`            | `gql.deinit()`                              |
| `DomainError`                                                        | `GraphQLClient.last_error` | Overwritten on next query or `gql.deinit()` |

Rule of thumb: if it crossed the GraphQL boundary _in_ (an arg), the arena
owns it. If it crossed _out_ (a scalar result), the user owns it and must
free.

## Error model

Four error sets, separated by concern:

- `BuildError` — client-side (alloc, serialize, invalid input).
- `QueryError` — wire-level (transport, HTTP status, GraphQL envelope, domain error).
- `ConnectError` — bring-up (subprocess, handshake, env).
- `DomainError` (struct, not error set) — carries the GraphQL error message so the caller can `switch` on the error then inspect `client.gql.last_error`.

All public functions return one of the `std.mem.Allocator.Error`-inclusive
error sets. We deliberately don't unify into one mega-error-set — callers
matching on `error.TransportFailed` shouldn't also need to handle
`error.UserCallbackFailed`.

## Performance notes

- **Cold start:** `dagger session` spawn + handshake is ~200–400ms. Identical
  to every other SDK. Zig's process spawn has no measurable overhead here.
- **Per-query:** one HTTP POST per terminal op. localhost keep-alive keeps
  this ~sub-ms of overhead on top of the engine's own processing.
- **Selection building:** O(n) in chain length, arena-allocated, no syscalls.
- **Memory per pipeline:** typically <100 KiB for the selection chain. The
  engine does all the heavy lifting; we're just routing GraphQL.

## Comparison to Rust SDK

| Area                           | Rust SDK                       | dagger-zig        |
| ------------------------------ | ------------------------------ | ----------------- |
| Concurrency                    | async/Tokio                    | sync              |
| Selection sharing              | `Arc<Selection>`               | arena-scoped      |
| Arg storage                    | `HashMap<String, LazyResolve>` | immutable `[]Arg` |
| Binary size (stripped release) | ~4 MB                          | ~500 KB (target)  |
| Dependencies                   | 80+ transitive                 | 0                 |
| Module runtime                 | yes                            | **no (v0.2)**     |

The binary size gap is where Zig pays off for Dagger specifically: the
module runtime container is pulled for every `dagger call`. Smaller base
image = faster pipelines.
