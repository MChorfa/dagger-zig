# Examples

## Parallel Pipeline

Build multiple platforms concurrently:

```zig
const std = @import("std");
const dagger = @import("dagger_sdk");

fn buildPlatform(
    client: *dagger.Client,
    io: std.Io,
    platform: []const u8,
) !void {
    const ctr = try client.dag()
        .container(.{ .platform = platform })
        .from("alpine");
    _ = ctr;
}

pub fn main() !void {
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var io_impl: std.Io.Threaded = .init_single_threaded;
    const io = io_impl.io();

    var client = try dagger.connect(gpa, io, .{});
    defer client.close();

    const group = try io.group();
    const f1 = try io.async(buildPlatform, .{ &client, io, "linux/amd64" });
    const f2 = try io.async(buildPlatform, .{ &client, io, "linux/arm64" });
    const f3 = try io.async(buildPlatform, .{ &client, io, "darwin/arm64" });
    try group.join(.{ f1, f2, f3 });
}
```

See `examples/parallel/main.zig` for the full example.

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
