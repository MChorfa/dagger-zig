# Distributed Tracing

`dagger.tracing` provides a small OpenTelemetry-compatible tracing surface for
SDK operations.

## What It Gives You

- `Span` for a single operation
- `Tracer` for grouping related spans
- `trace()` for wrapping a function call
- JSON export for local inspection and test fixtures

## Span Basics

Create a span, annotate it, and end it when the operation completes:

```zig
const std = @import("std");
const dagger = @import("dagger_sdk");
const trace = dagger.tracing;

pub fn build(client: *dagger.Client) !void {
    var span = try trace.Span.init(std.heap.page_allocator, "build-container", .{});
    defer span.deinit();
    defer span.end();

    try span.setAttribute("image", "alpine:latest");
    const ctr = try client.dag().container().from("alpine:latest");
    try span.addEvent("container-created", .{});

    _ = ctr;
    span.setStatus(.ok);
}
```

## Parent-Child Spans

Use `Tracer` when you want a simple span stack:

```zig
var tracer = try trace.Tracer.init(std.heap.page_allocator);
defer tracer.deinit();

const root = try tracer.startSpan("pipeline");
_ = root;

const build = try tracer.startSpan("build");
_ = build;
tracer.endSpan();

const test = try tracer.startSpan("test");
_ = test;
tracer.endSpan();

tracer.endSpan();
```

## Wrapping Functions

The `trace()` helper is useful when you want lightweight coverage around an
existing function:

```zig
const tracedBuild = trace.trace("build", buildFn);
```

## Exporting JSON

Use `Tracer.exportJson()` for local debugging or fixtures:

```zig
var tracer = try trace.Tracer.init(std.heap.page_allocator);
defer tracer.deinit();

// ... start spans ...

var stdout = std.io.getStdOut().writer();
try tracer.exportJson(stdout);
```

## Practical Guidance

- Keep spans short and tied to one meaningful operation.
- Add attributes before the expensive part starts.
- Mark failures with `setStatus(.error_)`.
- End every span with `defer`.

## Caveat

The current implementation uses lightweight internal IDs and deterministic
counters rather than a full production tracer backend. It is good for local
inspection and SDK instrumentation, not a drop-in observability platform.

## Related Pages

- [Observability](observability.md)
- [Architecture](architecture.md)
- [Examples](examples.md)
