# Examples

These examples are intentionally small and opinionated: one client per task, branch when you fan out, and keep the code close to what actually runs.

## Parallel fan-out

Pull several base images concurrently. Each task gets its own branch so the client state stays isolated.

```zig
const std = @import("std");
const dagger = @import("dagger_sdk");

const images = [_][]const u8{ "alpine:3.20", "debian:bookworm-slim", "ubuntu:24.04" };

fn pull(io: std.Io, parent: *dagger.Client, image: []const u8) std.Io.Cancelable!void {
    _ = io;
    var c = parent.branch() catch return error.Canceled;
    defer c.close();
    const ctr = c.dag().container() catch return error.Canceled;
    _ = ctr.from(image) catch return error.Canceled;
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var client = try dagger.connect(init.gpa, io, .{});
    defer client.close();

    try dagger.parallel.forEach(io, &images, &client, pull);
}
```

See [`examples/parallel/main.zig`](../examples/parallel/main.zig) for the full runnable version.

## C FFI

```bash
zig build c-lib
zig build run-hello-c
```

```c
#include <dagger.h>

DaggerClient* client = dagger_connect();
if (!client) {
    fprintf(stderr, "connect failed: %s\n", dagger_last_error());
    return 1;
}
```

## SPIFFE registry auth

```zig
const spiffe = dagger.spiffe;

var shell = try spiffe.ShelloutSource.init(gpa, io, .{
    .expected_trust_domain = "MChorfa.internal",
}, null);
defer shell.deinit();

const src = shell.source();
var svid = try src.fetchX509SVID(gpa);
defer svid.deinit();
```

## More

- [Async Patterns](async-patterns.md) for the full concurrency model
- [Compliance](compliance.md) for release provenance and signing
