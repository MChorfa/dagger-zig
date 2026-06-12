# Query Builder

The query builder is the immutable selection chain in
[`src/querybuilder.zig`](../src/querybuilder.zig). It turns fluent SDK calls
into GraphQL literals.

## Core Type

The main type is `Selection`.

Start from `Selection.root`, then derive a new selection by calling:

- `select(arena, name)`
- `selectWithAlias(arena, alias, name)`
- `arg(arena, name, value)`
- `argStr(arena, name, value)`
- `build(allocator)`

## Basic Flow

```zig
const qb = dagger.querybuilder;

var arena = std.heap.ArenaAllocator.init(gpa);
defer arena.deinit();
const aa = arena.allocator();

const query = try qb.Selection.root
    .select(aa, "container")
    .argStr(aa, "from", "alpine:latest")
    .select(aa, "stdout")
    .build(gpa);
defer gpa.free(query);
```

The chain is immutable. Each method returns a new `Selection` node allocated in
the arena you pass in.

## Arguments

The builder emits GraphQL input literals, not JSON.

Supported forms include:

- strings
- integers
- floats
- booleans
- null
- lists
- objects
- enums

Use `argStr()` for the common string case. Use `arg()` when you already have a
pre-serialized literal or a lazy argument.

## Limits

The builder protects against runaway input:

- maximum selection depth
- maximum arguments per selection
- maximum serialized argument size

These checks fail early with `BuildError` values such as `SelectionTooDeep` or
`TooManyArguments`.

## Lazy Arguments

`LazyArg` is used when a value must be resolved later, usually after another
handle has been awaited into an ID. That keeps the selection chain small while
still letting the terminal build step materialize the final query.

## What It Is Not

It is not a general-purpose GraphQL client. It is an internal builder used by
the SDK to keep fluent calls deterministic and arena-backed.

## Related Pages

- [Architecture](architecture.md)
- [Client API](api-reference.md)
- [Error Handling](errors.md)
