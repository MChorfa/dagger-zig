# Why dagger-zig?

Rationale for choosing Zig over the Go or Python SDKs. This page compares
language characteristics, not benchmark numbers — the figures that previously
appeared here were never measured and have been removed. If you need numbers for
your workload, measure them on your own runners.

## What Zig brings

Zig has **no garbage collector and no language runtime**. A pipeline compiles to a
single statically linked native executable. That has a few concrete consequences
relative to the Go and Python SDKs:

| Property            | Why it follows from the language                                                                                |
| ------------------- | -------------------------------------------------------------------------------------------------------------- |
| Small binaries      | No runtime to embed; a static Zig binary is smaller than the Go equivalent and far smaller than a Python image |
| Low, flat memory    | No GC heap and no interpreter; baseline memory is low and does not grow with collector slack                   |
| Fast startup        | No managed runtime to initialize before the first query                                                        |
| Predictable latency | No GC pauses; allocation is explicit and visible in the source                                                 |
| Compile-time safety | Errors are values; many failure modes are caught by the compiler instead of at runtime                         |

These are design-level statements, not measurements. The Go SDK trades some of
these for ecosystem maturity and GC convenience; the Python SDK trades them for
rapid prototyping and data-science integration.

## Concurrency Model

### Zig: std.Io.async

```zig
// True parallelism with async/await
var group: std.Io.Group(void) = .{};
for (containers) |ctr| {
    group.add(ctr.stdout());
}
try group.wait();
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

## Expected Characteristics

The points below follow from language design — Zig has no garbage collector and no
runtime — rather than from a measured benchmark suite in this repository. Treat
them as qualitative expectations, not numbers we have published.

- **Binaries**: a statically linked Zig pipeline is a single small native
  executable with no runtime dependencies, smaller than the equivalent Go binary
  and far smaller than a Python runtime + interpreter.
- **Memory**: no GC means lower and more predictable baseline memory use, which
  matters on constrained CI runners.
- **Startup**: a native binary starts faster than a process that must initialize
  a managed runtime.

If you need concrete numbers for your own workload, measure it on your runners —
language-level comparisons depend heavily on the specific pipeline.

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

- You want maximum performance
- You value small binaries
- You prefer compile-time safety
- You're building resource-constrained systems

**dagger-zig may not be for you if:**

- Team is unfamiliar with Zig
- You need extensive ecosystem libraries
- You prefer runtime flexibility over compile-time safety
