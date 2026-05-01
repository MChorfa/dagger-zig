# Distributed Tracing

OpenTelemetry-compatible tracing for Dagger SDK operations.

## Overview

The `dagger.tracing` module provides distributed tracing capabilities for pipeline operations, compatible with OpenTelemetry and exportable to various backends (Jaeger, Zipkin, OTLP collectors).

## Quick Start

```zig
const dagger = @import("dagger_sdk");
const trace = dagger.tracing;

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    
    // Initialize global tracer
    try trace.initGlobalTracer(allocator);
    
    // Create a span for your operation
    var span = try trace.Span.init(allocator, "build-pipeline", .{});
    defer span.deinit();
    
    // Set attributes
    try span.setAttribute("project", "my-app");
    try span.setAttribute("version", "1.0.0");
    
    // Execute operations
    const result = try buildContainer(client);
    
    // Add events
    try span.addEvent("container-built", .{});
    
    // Set status
    span.setStatus(.ok);
    span.end();
}
```

## Span Lifecycle

```zig
// 1. Initialize
var span = try trace.Span.init(allocator, "operation-name", .{
    .parent_id = parent_span_id, // Optional: for nested spans
});

// 2. Add attributes
try span.setAttribute("key", "value");
try span.setAttribute("count", 42);

// 3. Record events
try span.addEvent("milestone-reached", .{});

// 4. End (records duration)
span.end();
defer span.deinit(); // Clean up resources
```

## Using the Tracer

For multiple related spans, use the `Tracer` type:

```zig
var tracer = try trace.Tracer.init(allocator);
defer tracer.deinit();

// Start a root span
const root = try tracer.startSpan("pipeline");

// Child spans automatically use current span as parent
const build = try tracer.startSpan("build");
// ... build operations ...
tracer.endSpan();

const test = try tracer.startSpan("test");
// ... test operations ...
tracer.endSpan();

tracer.endSpan(); // End root
```

## Exporting Traces

Export spans in OpenTelemetry JSON format:

```zig
var tracer = try trace.Tracer.init(allocator);
defer tracer.deinit();

// ... create spans ...

// Export to stdout
var stdout = std.io.getStdOut().writer();
try tracer.exportJson(stdout);
```

Example output:
```json
[
  {
    "name": "build-pipeline",
    "trace_id": "a1b2c3d4e5f6...",
    "span_id": "1234567890ab...",
    "start_time": 1234567890000000,
    "end_time": 1234567891000000,
    "attributes": {
      "project": "my-app",
      "version": "1.0.0"
    },
    "events": [
      {
        "name": "container-built",
        "timestamp": 1234567890500000
      }
    ],
    "status": "ok"
  }
]
```

## Integration with Pipelines

```zig
fn tracedBuild(client: dagger.Client, image: []const u8) !dagger.Container {
    const allocator = std.heap.page_allocator;
    
    var span = try trace.Span.init(allocator, "container-build", .{});
    defer span.deinit();
    
    try span.setAttribute("image", image);
    
    const ctr = try client.dag()
        .container()
        .from(image)
        .withExec(&.{"echo", "building..."});
    
    try span.addEvent("container-created", .{});
    span.end();
    
    return ctr;
}
```

## Configuration

```zig
// Configure sampling (example)
const tracer = trace.Tracer.init(allocator, .{
    .sampler = .{
        .type = .probability,
        .rate = 0.1, // Sample 10% of traces
    },
});
```

## Best Practices

1. **Use meaningful span names** — "build-container" not "op-1"
2. **Add attributes early** — Set attributes before operations execute
3. **Record errors** — Set status to `.error_` on failures
4. **Keep spans focused** — One logical operation per span
5. **Always end spans** — Use `defer span.end()` to ensure cleanup

## Trace Context Propagation

Pass trace context between services:

```zig
// Extract from incoming request
const trace_id = trace.TraceId.parse(headers.get("trace-id"));
const parent_id = trace.SpanId.parse(headers.get("parent-id"));

// Create span with parent
var span = try trace.Span.init(allocator, "handler", .{
    .trace_id = trace_id,
    .parent_id = parent_id,
});

// Inject into outgoing requests
headers.put("trace-id", span.trace_id.toString());
headers.put("parent-id", span.span_id.toString());
```

## API Reference

### Types

- `Span` — A single operation trace
- `Tracer` — Manages multiple spans with parent-child relationships
- `TraceId` — 16-byte unique trace identifier
- `SpanId` — 8-byte unique span identifier
- `SpanEvent` — Timestamped event within a span
- `AttributeValue` — String, int, float, or bool attribute

### Functions

- `Span.init(allocator, name, options)` — Create a new span
- `Span.setAttribute(key, value)` — Add an attribute
- `Span.addEvent(name, attrs)` — Record an event
- `Span.end()` — Mark span as complete
- `Tracer.startSpan(name)` — Create span, set as current
- `Tracer.endSpan()` — End current span
- `Tracer.exportJson(writer)` — Export to OpenTelemetry format
