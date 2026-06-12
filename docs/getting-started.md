# Getting Started

This is the shortest path to a working call.

## 1. Add the SDK

Add `dagger-zig` to your `build.zig.zon`:

```json
{
  "name": "my-project",
  "version": "0.1.0",
  "dependencies": {
    "dagger_sdk": {
      "url": "https://github.com/MChorfa/dagger-zig/archive/refs/tags/v0.3.2.tar.gz",
      "hash": "..."
    }
  }
}
```

## 2. Open a client

```zig
const std = @import("std");
const dagger = @import("dagger_sdk");

pub fn main() !void {
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var io_impl: std.Io.Threaded = .init(gpa, .{});
    defer io_impl.deinit();
    const io = io_impl.io();

    var client = try dagger.connect(gpa, io, .{});
    defer client.close();

    const out = try client.dag()
        .container()
        .from("alpine:latest")
        .withExec(&.{"echo", "hello from zig"})
        .stdout();
    defer gpa.free(out);

    std.debug.print("{s}", .{out});
}
```

## 3. Run it

```bash
dagger run -- zig build run
```

## Requirements

- Zig 0.16.0 or later
- Dagger CLI on `PATH`

## What to read next

- [Examples](examples.md) for copyable patterns
- [Module Authoring](module-authoring.md) for turning Zig structs into Dagger modules
- [Async Patterns](async-patterns.md) for concurrent fan-out
