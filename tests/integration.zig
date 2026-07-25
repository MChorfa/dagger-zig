//! Integration tests. Require a live Dagger engine.
//!
//! Skipped gracefully when `DAGGER_SESSION_PORT` is absent.

const std = @import("std");
const dagger = @import("dagger_sdk");

fn skipIfNoEngine(alloc: std.mem.Allocator) !void {
    _ = alloc;
    if (std.c.getenv("DAGGER_SESSION_PORT") == null) {
        std.debug.print("SKIP: no DAGGER_SESSION_PORT — run under `dagger run --`\n", .{});
        return error.SkipZigTest;
    }
}

test "alpine echo hello end-to-end" {
    try skipIfNoEngine(std.testing.allocator);

    var io_impl: std.Io.Threaded = .init(std.testing.allocator, .{});
    defer io_impl.deinit();
    const io = io_impl.io();

    var client = try dagger.connect(std.testing.allocator, io, .{});
    defer client.close();

    const ctr = try client.dag().container(null);
    const ctr1 = try ctr.from("alpine:latest", null);
    const ctr2 = try ctr1.withExec(&.{ "echo", "hello" }, null, null, null, null, null, null, null, null, null, null);

    const out = try ctr2.stdout();
    defer std.testing.allocator.free(out);

    try std.testing.expect(std.mem.indexOf(u8, out, "hello") != null);
}

test "container id is opaque and non-empty" {
    try skipIfNoEngine(std.testing.allocator);

    var io_impl: std.Io.Threaded = .init(std.testing.allocator, .{});
    defer io_impl.deinit();
    const io = io_impl.io();

    var client = try dagger.connect(std.testing.allocator, io, .{});
    defer client.close();

    const ctr = try client.dag().container(null);
    const ctr1 = try ctr.from("alpine:latest", null);

    var id = try ctr1.id();
    defer id.deinit(std.testing.allocator);

    try std.testing.expect(id.value.len > 0);
}

test "container withEnvVariable and env resolution" {
    try skipIfNoEngine(std.testing.allocator);

    var io_impl: std.Io.Threaded = .init(std.testing.allocator, .{});
    defer io_impl.deinit();
    const io = io_impl.io();

    var client = try dagger.connect(std.testing.allocator, io, .{});
    defer client.close();

    const ctr = try client.dag().container(null);
    const ctr1 = try ctr.from("alpine:latest", null);
    const ctr2_base = try ctr1.withEnvVariable("MY_VAR", "my_value", null);

    const ctr2 = try ctr2_base.withExec(&.{ "sh", "-c", "echo $MY_VAR" }, null, null, null, null, null, null, null, null, null, null);
    const out = try ctr2.stdout();
    defer std.testing.allocator.free(out);

    try std.testing.expect(std.mem.indexOf(u8, out, "my_value") != null);
}

test "directory operations" {
    try skipIfNoEngine(std.testing.allocator);

    var io_impl: std.Io.Threaded = .init(std.testing.allocator, .{});
    defer io_impl.deinit();
    const io = io_impl.io();

    var client = try dagger.connect(std.testing.allocator, io, .{});
    defer client.close();

    // Create a file in a container, then read it back through the directory API.
    const ctr = try client.dag().container(null);
    const ctr_with_file = try ctr.withNewFile("/work/hello.txt", "Hello, World!", null, null, null);
    const dir = try ctr_with_file.directory("/work", null);
    const file = try dir.file("hello.txt");
    const contents = try file.contents(null, null);
    defer std.testing.allocator.free(contents);

    try std.testing.expectEqualStrings("Hello, World!", contents);
}

test "cache volume persistence" {
    try skipIfNoEngine(std.testing.allocator);

    var io_impl: std.Io.Threaded = .init(std.testing.allocator, .{});
    defer io_impl.deinit();
    const io = io_impl.io();

    var client = try dagger.connect(std.testing.allocator, io, .{});
    defer client.close();

    // Create cache volume
    const cache = try client.dag().cacheVolume("test-cache", null, null, null);
    var cache_id = try cache.id();
    defer cache_id.deinit(std.testing.allocator);

    // Use in container
    const ctr = try client.dag().container(null);
    const ctr1 = try ctr.from("alpine:latest", null);
    const ctr_with_cache = try ctr1.withMountedCache("/cache", cache_id.value, null, null, null, null);

    // Write to cache
    const ctr2 = try ctr_with_cache.withExec(&.{ "sh", "-c", "echo cached > /cache/data.txt" }, null, null, null, null, null, null, null, null, null, null);
    var written_id = try ctr2.sync();
    defer written_id.deinit(std.testing.allocator);

    // Read back from the same mounted cache chain.
    const ctr3 = try ctr2.withExec(&.{ "cat", "/cache/data.txt" }, null, null, null, null, null, null, null, null, null, null);

    const out = try ctr3.stdout();
    defer std.testing.allocator.free(out);

    try std.testing.expect(std.mem.indexOf(u8, out, "cached") != null);
}

test "git repository operations" {
    try skipIfNoEngine(std.testing.allocator);

    var io_impl: std.Io.Threaded = .init(std.testing.allocator, .{});
    defer io_impl.deinit();
    const io = io_impl.io();

    var client = try dagger.connect(std.testing.allocator, io, .{});
    defer client.close();

    // Clone a public repo
    const repo = try client.dag().git("https://github.com/dagger/hello-dagger", null, null, null, null, null, null);
    const head = try repo.head();
    const tree = try head.tree(null, null, null);

    // Check that we got a valid directory
    var id = try tree.id();
    defer id.deinit(std.testing.allocator);

    try std.testing.expect(id.value.len > 0);
}

test "secret handling" {
    try skipIfNoEngine(std.testing.allocator);

    var io_impl: std.Io.Threaded = .init(std.testing.allocator, .{});
    defer io_impl.deinit();
    const io = io_impl.io();

    var client = try dagger.connect(std.testing.allocator, io, .{});
    defer client.close();

    const secret = try client.dag().setSecret("my-secret", "secret-value");
    var secret_id = try secret.id();
    defer secret_id.deinit(std.testing.allocator);

    // Use secret in container
    const ctr = try client.dag().container(null);
    const ctr1 = try ctr.from("alpine:latest", null);
    const ctr2 = try ctr1.withSecretVariable("TEST_SECRET", secret_id.value);
    const ctr3 = try ctr2.withExec(&.{ "sh", "-c", "test -n \"$TEST_SECRET\"" }, null, null, null, null, null, null, null, null, null, null);

    var ctr_id = try ctr3.sync();
    defer ctr_id.deinit(std.testing.allocator);
}

test "multi-platform container" {
    try skipIfNoEngine(std.testing.allocator);

    var io_impl: std.Io.Threaded = .init(std.testing.allocator, .{});
    defer io_impl.deinit();
    const io = io_impl.io();

    var client = try dagger.connect(std.testing.allocator, io, .{});
    defer client.close();

    const ctr = try client.dag().container(null);
    const ctr1 = try ctr.from("alpine:latest", null);

    const ctr2 = try ctr1.withExec(&.{ "uname", "-m" }, null, null, null, null, null, null, null, null, null, null);
    const out = try ctr2.stdout();
    defer std.testing.allocator.free(out);

    // Should output architecture
    try std.testing.expect(out.len > 0);
}

test "container publish and reference" {
    try skipIfNoEngine(std.testing.allocator);

    // Skip if no registry credentials
    const registry_ptr = std.c.getenv("TEST_REGISTRY") orelse {
        std.debug.print("SKIP: no TEST_REGISTRY set\n", .{});
        return error.SkipZigTest;
    };
    const registry = try std.testing.allocator.dupe(u8, std.mem.span(registry_ptr));
    defer std.testing.allocator.free(registry);

    var io_impl: std.Io.Threaded = .init(std.testing.allocator, .{});
    defer io_impl.deinit();
    const io = io_impl.io();

    var client = try dagger.connect(std.testing.allocator, io, .{});
    defer client.close();

    const ctr = try client.dag().container(null);
    const ctr1 = try ctr.from("alpine:latest", null);
    const ctr2 = try ctr1.withExec(&.{ "echo", "published" }, null, null, null, null, null, null, null, null, null, null);

    const addr = try std.fmt.allocPrint(std.testing.allocator, "{s}/dagger-zig-test:latest", .{registry});
    defer std.testing.allocator.free(addr);

    const digest = try ctr2.publish(addr, null, null, null, null);
    defer std.testing.allocator.free(digest);

    try std.testing.expect(digest.len > 0);
}
