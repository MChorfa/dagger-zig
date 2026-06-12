# Why Zig

This page is about trade-offs, not benchmarks.

## The short version

Zig gives the SDK:

- no garbage collector
- no managed runtime
- explicit allocation
- errors as part of the type system

Those are engineering properties, not automatic performance claims. If you care about startup, memory, or throughput for your own workload, measure them on your own runners.

## Why that matters here

The Dagger SDK is a client library that composes lots of short-lived queries. The design benefits from:

- predictable memory behavior
- compile-time validation of API shape
- low ceremony around cross-compilation
- a small, inspectable runtime footprint

Go remains a better fit when your team wants GC and broad ecosystem familiarity. Python remains a better fit when you want scripting speed and notebook-driven iteration.

## Concurrency Model

### Zig: `std.Io.Group`

```zig
// Fan out one task per item using a group. Each task gets its own branch.
var group: std.Io.Group = .init;
defer group.cancel(io);
for (clients, outputs) |*c, *out| {
    group.async(io, fetch, .{ io, c, out });
}
try group.await(io);
```

**Advantages:**

- Zero-cost abstractions
- No garbage collection pauses
- Predictable memory layout
- Comptime-optimized

### Go: Goroutines + Channels

```go
// Concurrent but with GC overhead
var wg sync.WaitGroup
for _, ctr := range containers {
    wg.Add(1)
    go func(c *dagger.Container) {
        defer wg.Done()
        c.Stdout(ctx)
    }(ctr)
}
wg.Wait()
```

**Trade-offs:**

- Garbage collection pauses
- Higher memory per goroutine
- Runtime overhead

### Python: asyncio

```python
# Single-threaded event loop
await asyncio.gather(
    *[ctr.stdout() for ctr in containers]
)
```

**Limitations:**

- GIL constraints
- Heavy async overhead
- Requires event loop management

## When to choose each SDK

### Choose dagger-zig when

- you want a small, explicit client
- you care about compile-time checks
- you want the API surface to be easy to audit

### Choose dagger-go when

- the team is already fluent in Go
- you prefer GC-managed code
- ecosystem compatibility is more important than explicit memory control

### Choose dagger-python when

- you want rapid scripting
- you are integrating with Python-heavy workflows
- runtime overhead is acceptable

## The Zig Philosophy in dagger-zig

1. No hidden costs: what you write is what runs
2. Compile-time verification: catch errors before runtime
3. Manual memory management: explicit but safe with `defer`
4. Cross-compilation: build for any target from any host

## Benchmarks

The repository ships offline micro-benchmarks for the SDK's hot paths (GraphQL query construction and string serialization). They need no live engine:

```bash
zig build bench
```

See [`benches/README.md`](../benches/README.md) for what is measured and how to read the output. There is no cross-language (Zig vs Go vs Python) benchmark suite in this repository.

## Summary

**dagger-zig is for you if:**

- you want a single static binary with zero runtime dependencies
- you prefer explicit memory management over a garbage collector
- you prefer compile-time safety and errors-as-values
- you are comfortable working in Zig

**dagger-zig may not be for you if:**

- the team is unfamiliar with Zig
- you need extensive ecosystem libraries
- you prefer runtime flexibility over compile-time safety
