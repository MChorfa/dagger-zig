//! Integration tests. Require a live Dagger engine.
//!
//! Skipped gracefully when `DAGGER_SESSION_PORT` is absent.

const std = @import("std");
const dagger = @import("dagger_sdk");

fn skipIfNoEngine(alloc: std.mem.Allocator) !void {
    const port = std.process.getEnvVarOwned(alloc, "DAGGER_SESSION_PORT") catch {
        std.debug.print("SKIP: no DAGGER_SESSION_PORT — run under `dagger run --`\n", .{});
        return error.SkipZigTest;
    };
    alloc.free(port);
}

test "alpine echo hello end-to-end" {
    try skipIfNoEngine(std.testing.allocator);

    var io_impl: std.Io.Threaded = .init(std.testing.allocator);
    defer io_impl.deinit();
    const io = io_impl.io();

    var client = try dagger.connect(std.testing.allocator, io, .{});
    defer client.close();

    const ctr = try client.dag().container();
    const ctr1 = try ctr.from("alpine:latest");
    const ctr2 = try ctr1.withExec(&.{ "echo", "hello" });

    const out = try ctr2.stdout();
    defer std.testing.allocator.free(out);

    try std.testing.expect(std.mem.indexOf(u8, out, "hello") != null);
}

test "container id is opaque and non-empty" {
    try skipIfNoEngine(std.testing.allocator);

    var io_impl: std.Io.Threaded = .init(std.testing.allocator);
    defer io_impl.deinit();
    const io = io_impl.io();

    var client = try dagger.connect(std.testing.allocator, io, .{});
    defer client.close();

    const ctr = try client.dag().container();
    const ctr1 = try ctr.from("alpine:latest");

    var id = try ctr1.id();
    defer id.deinit(std.testing.allocator);

    try std.testing.expect(id.value.len > 0);
}
