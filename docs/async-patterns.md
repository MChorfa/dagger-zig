# Concurrency & Parallelism

`dagger-zig` uses Zig 0.16 `std.Io.Group` for fan-out. The API stays synchronous at the call site, but independent tasks can run in parallel when the backend supports it.

## The Rule

Give each concurrent task its own `Client.branch()`.

`Client` carries mutable per-query state such as the last error and circuit breaker. Sharing one client across concurrent tasks is not safe. A branch reuses the same engine session and connection parameters, but owns its own mutable state and arena.

## `dagger.parallel.map`

Use `map` when every item produces a result:

```zig
const dagger = @import("dagger_sdk");

const Image = []const u8;

fn fetchOS(io: std.Io, parent: *dagger.Client, image: Image, out: *[]u8) std.Io.Cancelable!void {
    _ = io;
    var client = parent.branch() catch return error.Canceled;
    defer client.close();

    const ctr = client.dag().container() catch return error.Canceled;
    const based = ctr.from(image) catch return error.Canceled;
    const run = based.withExec(&.{ "cat", "/etc/os-release" }) catch return error.Canceled;
    out.* = run.stdout() catch return error.Canceled;
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var client = try dagger.connect(init.gpa, io, .{});
    defer client.close();

    const images = [_]Image{ "alpine:3.20", "debian:bookworm-slim", "ubuntu:24.04" };
    var results: [images.len][]u8 = undefined;

    try dagger.parallel.map(io, &images, &results, &client, fetchOS);

    for (&results) |*r| init.gpa.free(r.*);
}
```

The task function returns `std.Io.Cancelable!void`; actual per-item data is written into the output slot.

## `dagger.parallel.forEach`

Use `forEach` for side effects:

```zig
try dagger.parallel.forEach(io, &images, &client, struct {
    fn run(io_: std.Io, parent: *dagger.Client, image: []const u8) std.Io.Cancelable!void {
        _ = io_;
        var c = parent.branch() catch return error.Canceled;
        defer c.close();
        _ = image;
        // do work
    }
}.run);
```

## Raw `std.Io.Group`

The helpers are thin wrappers. Use `std.Io.Group` directly when you need explicit control over task lifetime:

```zig
var group: std.Io.Group = .init;
defer group.cancel(io);

for (images, 0..) |image, i| {
    group.async(io, fetchOS, .{ io, &branches[i], image, &results[i] });
}

try group.await(io);
```

## Retry and Circuit Breaking

Retry and circuit-breaker behavior is configured on the client:

```zig
var client = try dagger.connect(gpa, io, .{
    .enable_circuit_breaker = true,
    .retry_policy = .{},
});
```

See [Resilience Patterns](resilience.md) for the underlying policy.

## Notes

- `std.Io.Group.await` returns `Cancelable!void`.
- Branch once per task so the hot path does not do extra connection work.
- Keep fan-out bounded; parallelism only helps when tasks are independent.

## Related Pages

- [Examples](examples.md)
- [Resilience Patterns](resilience.md)
- [Architecture](architecture.md)
