# Why dagger-zig?

Rationale for choosing Zig over the Go or Python SDKs. This page compares
language characteristics, not benchmark numbers — the figures that previously
appeared here were never measured and have been removed. If you need numbers for
your workload, measure them on your own runners.

## What Zig brings

These are facts about the language, not measurements:

- **No garbage collector.** No GC pauses; memory is freed at points you write
  (`defer`, explicit `free`).
- **No language runtime.** A pipeline compiles to a single statically linked
  native executable; there is no interpreter or managed runtime to ship or
  initialize before the first query.
- **Explicit allocation.** Allocators are passed as parameters, so where memory
  comes from is visible in the source.
- **Errors are values.** Error sets are part of function signatures, so many
  failure modes are caught by the compiler instead of at runtime.

Whether these translate into smaller binaries, lower memory, or faster startup
for *your* pipeline depends on the pipeline — measure it on your own runners. The
Go SDK trades some of these properties for ecosystem maturity and GC convenience;
the Python SDK trades them for rapid prototyping and data-science integration.

## Concurrency Model

### Zig: std.Io.async

```zig
// Fan out one task per item; runs in parallel under the multi-threaded
// Io backend, cooperatively under -fsingle-threaded. Same code either way.
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

## When to Choose Each SDK

### Choose dagger-zig when

- Performance is critical
- Binary size matters (embedded, edge)
- You want zero dependencies
- Memory efficiency is important
- You prefer compile-time safety

### Choose dagger-go when

- Team already knows Go
- Ecosystem maturity is priority
- You need maximum compatibility
- Team prefers garbage collection

### Choose dagger-python when

- Team already knows Python
- Rapid prototyping
- Data science integration
- You accept runtime overhead

## The Zig Philosophy in dagger-zig

1. **No hidden costs**: What you write is what runs
2. **Compile-time verification**: Catch errors before runtime
3. **Manual memory management**: Explicit but safe with defer
4. **Cross-compilation**: Build for any target from any host

## Benchmarks

The repository ships offline micro-benchmarks for the SDK's hot paths (GraphQL
query construction and string serialization). They need no live engine:

```bash
zig build bench
```

See [`benches/README.md`](../benches/README.md) for what is measured and how to
read the output. There is no cross-language (Zig vs Go vs Python) benchmark suite
in this repository.

## Summary

**dagger-zig is for you if:**

- You want a single static binary with zero runtime dependencies
- You prefer explicit memory management over a garbage collector
- You prefer compile-time safety and errors-as-values
- You are comfortable working in Zig

**dagger-zig may not be for you if:**

- Team is unfamiliar with Zig
- You need extensive ecosystem libraries
- You prefer runtime flexibility over compile-time safety
