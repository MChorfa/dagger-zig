# Getting Started

## Installation

Add dagger-zig to your `build.zig.zon`:

```json
{
  "name": "my-project",
  "version": "0.1.0",
  "dependencies": {
    "dagger_sdk": {
      "url": "https://github.com/ckodex/dagger-zig/archive/refs/tags/v0.1.0.tar.gz",
      "hash": "..."
    }
  }
}
```

## First Pipeline

```zig
const std = @import("std");
const dagger = @import("dagger_sdk");

pub fn main() !void {
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var io_impl: std.Io.Threaded = .init_single_threaded;
    const io = io_impl.io();

    var client = try dagger.connect(gpa, io, .{});
    defer client.close();

    const ctr = try client.dag()
        .container()
        .from("alpine:latest")
        .withExec(&.{"echo", "hello from zig"});

    const out = try ctr.stdout();
    defer gpa.free(out);
    std.debug.print("{s}", .{out});
}
```

Run under a Dagger session:

```shell
dagger run -- zig build run
```

## Requirements

- Zig 0.16.0 or later
- Dagger CLI installed (`dagger` on PATH)

## Next Steps

- [Module Authoring](module-authoring.md) — Create reusable Dagger modules
- [Resilience Patterns](resilience.md) — Configure retry and circuit breaker
- [SPIFFE Integration](spiffe.md) — Workload identity for registry auth
