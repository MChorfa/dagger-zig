# Architecture

This page explains the shape of the SDK, not every implementation detail.

## The model

The SDK is built around a few simple ideas:

- `Client` owns a session, an arena, and the mutable state needed for queries.
- Each query is a chained selection that serializes to GraphQL at the edge.
- Modules are plain Zig structs with methods.
- Concurrent work is done by branching the client per task.

## Code generation categories

| Area | What it means | Current state |
| --- | --- | --- |
| Module bindings | Code a module imports to call `dag.*` | Hand-wired for now |
| Runtime dispatch | Routing from Dagger into Zig methods | Done with comptime tables |
| SDK surface | The public `dagger` package | Hand-written |
| Generated clients | Generic program clients and wrappers | Partial |

The important decision is the runtime dispatch path: it uses comptime
registration instead of macros or runtime reflection. A Zig struct like this:

```zig
const MyModule = struct {
    pub fn build(self: *const MyModule, ctx: *Context, src: Directory) !Container {
        _ = self;
        _ = ctx;
        _ = src;
        return undefined;
    }
};
```

is walked at comptime, filtered for eligible methods, and converted into one
specialized shim per callable method.

## Handshake

The client starts by checking, in order:

1. `DAGGER_SESSION_PORT` + `DAGGER_SESSION_TOKEN`
2. `_EXPERIMENTAL_DAGGER_CLI_BIN`
3. `dagger` on `PATH`

If a session is not already present, the CLI is spawned and the SDK reads the
handshake from stdout. That keeps the dependency boundary explicit and avoids
hidden downloads.

## Query building

Calls are lowered to GraphQL selections. Each chained method produces a new
selection node owned by the client arena.

That design keeps the ownership model simple:

| Memory | Owned by | Released when |
| --- | --- | --- |
| Selection chain | `client.arena` | `client.close()` |
| Query result bodies | Caller | The caller allocator |
| Transport state | `GraphQLClient` | `gql.deinit()` |

## Error model

The code keeps the major failure classes separated:

- `BuildError` for client-side serialization and allocation problems
- `QueryError` for transport and GraphQL envelope failures
- `ConnectError` for bring-up and handshake issues
- `DomainError` for server-reported message payloads

That makes error handling explicit without forcing everything into one giant
error set.

## Why the design looks this way

- predictable memory use matters more than generalized runtime magic
- compile-time validation catches shape mismatches early
- a branch-per-task model keeps fan-out safe
- the handshake stays simple and inspectable

## Comparison

| Area | Rust SDK | dagger-zig |
| --- | --- | --- |
| Concurrency | async/Tokio | sync |
| Selection sharing | shared reference counting | arena scoped |
| Dependencies | many | zero runtime deps |
| Dispatch | runtime-heavy | comptime-generated |
