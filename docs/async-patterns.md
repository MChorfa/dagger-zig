# Concurrency & Parallelism

dagger-zig fans out concurrent engine queries with Zig 0.16's `std.Io` — no
threading boilerplate. Under the multi-threaded `Io` backend tasks run in
parallel; under `-fsingle-threaded` they schedule cooperatively. The same user
code works either way.

## The one rule: a client per task

A `dagger.Client` carries per-query mutable state (the last domain error, the
circuit breaker, an in-progress flag) that is **not** synchronized. Sharing one
client across concurrent tasks is a data race. Give each task its own
`client.branch()` — it reuses the parent's engine session (same port and token,
no new subprocess) but has independent state and its own arena. Close each
branch when done; do not let a branch outlive its parent.

## `dagger.parallel.map`

Apply an operation to each input concurrently, writing results into disjoint
slots. The op returns `std.Io.Cancelable!void` and reports its result through an
output pointer (this is the `std.Io.Group` model — `await` surfaces only
cancellation).

```zig
const dagger = @import("dagger_sdk");

const Image = []const u8;

fn fetchOS(io: std.Io, parent: *dagger.Client, image: Image, out: *[]u8) std.Io.Cancelable!void {
    _ = io;
    var c = parent.branch() catch return error.Canceled;
    defer c.close();
    const ctr = c.dag().container() catch return error.Canceled;
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

## `dagger.parallel.forEach`

When you only need side effects (no per-item result), `forEach` runs the op over
every item concurrently:

```zig
try dagger.parallel.forEach(io, &images, &client, struct {
    fn run(io_: std.Io, parent: *dagger.Client, image: []const u8) std.Io.Cancelable!void {
        _ = io_;
        var c = parent.branch() catch return error.Canceled;
        defer c.close();
        // … do work with `c` …
    }
}.run);
```

## Raw `std.Io.Group`

The helpers are thin wrappers; you can drive `std.Io.Group` directly when you
want more control (mixed task shapes, early `await`, etc.). See
[`examples/parallel/main.zig`](../examples/parallel/main.zig) for a complete,
runnable example:

```zig
var group: std.Io.Group = .init;
defer group.cancel(io); // cancel any outstanding task on early return

for (images, 0..) |image, i| {
    group.async(io, fetchOS, .{ io, &branches[i], image, &results[i] });
}
try group.await(io); // surfaces the first cancellation; rest are cancelled
```

## Retries and circuit breaking

Retry with backoff and the circuit breaker are **client configuration**, not a
separate async helper — they apply to every query automatically:

```zig
var client = try dagger.connect(gpa, io, .{
    .enable_circuit_breaker = true,
    // .retry_policy = .{ .max_retries = 3, .initial_backoff_ms = 100, ... },
});
```

See [`src/core/resilience.zig`](../src/core/resilience.zig) for the policy fields.

## Notes

- `std.Io.Group.await` returns `Cancelable!void`. Task functions return
  `std.Io.Cancelable!void` and surface real errors through their output slot
  (e.g. make `Out` an error union), not through `await`.
- Branch up front (one per task) so the concurrent hot path does no extra
  connection work.
