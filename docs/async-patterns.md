# Async Patterns

Concurrent operations for Dagger pipelines using the `dagger.async` module.

## Overview

The async module provides utilities for executing multiple Dagger operations concurrently, enabling faster pipeline execution by parallelizing independent work.

## QueryGroup

Group multiple queries and execute them concurrently:

```zig
const dagger = @import("dagger_sdk");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var io_impl: std.Io.Threaded = .init(gpa.allocator(), .{});
    defer io_impl.deinit();

    var client = try dagger.connect(gpa.allocator(), io_impl.io(), .{});
    defer client.close();

    // Create a query group for concurrent operations
    var group = try dagger.async.QueryGroup.init(gpa.allocator(), io_impl.io());
    defer group.deinit();

    // Add multiple container builds
    const alpine = try group.add(client.dag().container().from("alpine:latest"));
    const ubuntu = try group.add(client.dag().container().from("ubuntu:latest"));
    const fedora = try group.add(client.dag().container().from("fedora:latest"));

    // Wait for all to complete
    try group.awaitAll();

    // Get results
    const alpine_id = try alpine.getResult(dagger.Container);
    const ubuntu_id = try ubuntu.getResult(dagger.Container);
    const fedora_id = try fedora.getResult(dagger.Container);
}
```

## QueryBatch

Batch multiple GraphQL queries into a single request:

```zig
var batch = dagger.async.QueryBatch.init(allocator);
defer batch.deinit();

try batch.add("query { container { id } }");
try batch.add("query { directory { id } }");
try batch.add("query { git(url: \"https://github.com/example/repo\") { id } }");

const combined_query = try batch.build();
```

## Retry with Backoff

Automatically retry failed operations with exponential backoff:

```zig
const config = dagger.async.RetryConfig{
    .max_attempts = 3,
    .initial_delay_ms = 100,
    .backoff_multiplier = 2.0,
};

const result = try dagger.async.withRetry(
    allocator,
    io,
    config,
    fetchContainer,
    .{client, "alpine:latest"},
);
```

## Concurrent Map

Apply an operation to multiple items concurrently:

```zig
const images = &.{ "alpine:latest", "ubuntu:latest", "fedora:latest" };

const containers = try dagger.async.concurrentMap(
    allocator,
    io,
    images,
    struct {
        fn fetch(img: []const u8) !dagger.Container {
            return client.dag().container().from(img);
        }
    }.fetch,
);
```

## Performance Considerations

- Use `QueryGroup` for operations with no dependencies
- Use `QueryBatch` for many small queries to reduce round trips
- Be mindful of resource limits when using high concurrency
- Consider `withRetry` for network-dependent operations

## API Reference

### Types

- `PendingQuery` — A query that will execute asynchronously
- `QueryGroup` — A collection of queries executed concurrently
- `QueryBatch` — Batched GraphQL queries
- `RetryConfig` — Configuration for retry behavior

### Functions

- `QueryGroup.init(allocator, io)` — Create a new query group
- `QueryGroup.add(query)` — Add a query to the group
- `QueryGroup.awaitAll()` — Wait for all queries to complete
- `QueryGroup.awaitAny()` — Wait for the first query to complete
- `QueryBatch.build()` — Combine batched queries
- `withRetry(allocator, io, config, operation, args)` — Retry with backoff
- `concurrentMap(allocator, io, items, operation)` — Map operation over items concurrently
