# Examples

## Parallel Pipeline

Pull several base images concurrently. Each task takes its own `client.branch()`
— sharing one client across concurrent tasks would race on its per-query state.

```zig
const std = @import("std");
const dagger = @import("dagger_sdk");

const images = [_][]const u8{ "alpine:3.20", "debian:bookworm-slim", "ubuntu:24.04" };

fn pull(io: std.Io, parent: *dagger.Client, image: []const u8) std.Io.Cancelable!void {
    _ = io;
    var c = parent.branch() catch return error.Canceled; // own client per task
    defer c.close();
    const ctr = c.dag().container() catch return error.Canceled;
    const based = ctr.from(image) catch return error.Canceled;
    _ = based.id() catch return error.Canceled; // force the engine to resolve it
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var client = try dagger.connect(init.gpa, io, .{});
    defer client.close();

    // forEach fans out one task per image and waits for all of them.
    try dagger.parallel.forEach(io, &images, &client, pull);
}
```

See [`examples/parallel/main.zig`](../examples/parallel/main.zig) for the full,
runnable example (collects each pipeline's output), and
[docs/async-patterns.md](async-patterns.md) for `map`, raw `std.Io.Group`, and
retries.

## C FFI Usage

```bash
zig build c-lib              # produces libdagger.{a,so}
zig build run-hello-c        # builds and runs the C example
```

```c
#include <dagger.h>

DaggerClient* client = dagger_connect();
if (!client) {
    fprintf(stderr, "connect failed: %s\n", dagger_last_error());
    return 1;
}

DaggerContainer* ctr = dagger_query_container(client);
dagger_container_from(ctr, "alpine:latest");
char* out = dagger_container_stdout(ctr);
printf("%s\n", out);

dagger_client_close(client);
```

## Python via cffi

```python
import cffi
ffi = cffi.FFI()

# See examples/c-client/hello.py for full bindings
```

## SPIFFE Registry Auth

```zig
const spiffe = dagger.spiffe;

var shell = try spiffe.ShelloutSource.init(gpa, io, .{
    .expected_trust_domain = "MChorfa.internal",
}, null);
defer shell.deinit();

const src = shell.source();
var svid = try src.fetchX509SVID(gpa);
defer svid.deinit();

// Use svid for registry authentication
```
