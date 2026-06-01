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

    var io_impl: std.Io.Threaded = .init(std.testing.allocator, undefined);
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

    var io_impl: std.Io.Threaded = .init(std.testing.allocator, undefined);
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

test "container withEnvVariable and env resolution" {
    try skipIfNoEngine(std.testing.allocator);

    var io_impl: std.Io.Threaded = .init(std.testing.allocator, undefined);
    defer io_impl.deinit();
    const io = io_impl.io();

    var client = try dagger.connect(std.testing.allocator, io, .{});
    defer client.close();

    const ctr = try client.dag().container();
    const ctr1 = try ctr.from("alpine:latest");
    const ctr2_base = try ctr1.withEnvVariable("MY_VAR", "my_value");

    const ctr2 = try ctr2_base.withExec(&.{ "sh", "-c", "echo $MY_VAR" });
    const out = try ctr2.stdout();
    defer std.testing.allocator.free(out);

    try std.testing.expect(std.mem.indexOf(u8, out, "my_value") != null);
}

test "directory operations" {
    try skipIfNoEngine(std.testing.allocator);

    var io_impl: std.Io.Threaded = .init(std.testing.allocator, undefined);
    defer io_impl.deinit();
    const io = io_impl.io();

    var client = try dagger.connect(std.testing.allocator, io, .{});
    defer client.close();

    // Create a file in a container, then read it back through the directory API.
    const ctr = try client.dag().container();
    const ctr_with_file = try ctr.withNewFile("/work/hello.txt", "Hello, World!");
    const dir = try ctr_with_file.directory("/work");
    const file = try dir.file("hello.txt");
    const contents = try file.contents();
    defer std.testing.allocator.free(contents);

    try std.testing.expectEqualStrings("Hello, World!", contents);
}

test "cache volume persistence" {
    try skipIfNoEngine(std.testing.allocator);

    var io_impl: std.Io.Threaded = .init(std.testing.allocator, undefined);
    defer io_impl.deinit();
    const io = io_impl.io();

    var client = try dagger.connect(std.testing.allocator, io, .{});
    defer client.close();

    // Create cache volume
    const cache = try client.dag().cacheVolume("test-cache");

    // Use in container
    const ctr = try client.dag().container();
    const ctr1 = try ctr.from("alpine:latest");
    const ctr_with_cache = try ctr1.withMountedCache("/cache", cache);

    // Write to cache
    const ctr2 = try ctr_with_cache.withExec(&.{ "sh", "-c", "echo cached > /cache/data.txt" });
    _ = try ctr2.sync();

    // Read from cache in new container
    const ctr3_root = try client.dag().container();
    const ctr3_base = try ctr3_root.from("alpine:latest");
    const ctr3_cache = try ctr3_base.withMountedCache("/cache", cache);
    const ctr3 = try ctr3_cache.withExec(&.{ "cat", "/cache/data.txt" });

    const out = try ctr3.stdout();
    defer std.testing.allocator.free(out);

    try std.testing.expect(std.mem.indexOf(u8, out, "cached") != null);
}

test "git repository operations" {
    try skipIfNoEngine(std.testing.allocator);

    var io_impl: std.Io.Threaded = .init(std.testing.allocator, undefined);
    defer io_impl.deinit();
    const io = io_impl.io();

    var client = try dagger.connect(std.testing.allocator, io, .{});
    defer client.close();

    // Clone a public repo
    const repo = try client.dag().git("https://github.com/dagger/hello-dagger");
    const head = try repo.head();
    const tree = try head.tree();

    // Check that we got a valid directory
    var id = try tree.id();
    defer id.deinit(std.testing.allocator);

    try std.testing.expect(id.value.len > 0);
}

test "secret handling" {
    try skipIfNoEngine(std.testing.allocator);

    var io_impl: std.Io.Threaded = .init(std.testing.allocator, undefined);
    defer io_impl.deinit();
    const io = io_impl.io();

    var client = try dagger.connect(std.testing.allocator, io, .{});
    defer client.close();

    const secret = try client.dag().setSecret("my-secret", "secret-value");

    // Use secret in container
    const ctr = try client.dag().container();
    const ctr1 = try ctr.from("alpine:latest");
    const ctr2 = try ctr1.withSecret("/run/secrets/test-secret", secret);
    const ctr3 = try ctr2.withExec(&.{ "sh", "-c", "cat /run/secrets/test-secret > /dev/null" });

    _ = try ctr3.sync();
}

test "multi-platform container" {
    try skipIfNoEngine(std.testing.allocator);

    var io_impl: std.Io.Threaded = .init(std.testing.allocator, undefined);
    defer io_impl.deinit();
    const io = io_impl.io();

    var client = try dagger.connect(std.testing.allocator, io, .{});
    defer client.close();

    const ctr = try client.dag().container();
    const ctr1 = try ctr.from("alpine:latest");

    const ctr2 = try ctr1.withExec(&.{ "uname", "-m" });
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

    var io_impl: std.Io.Threaded = .init(std.testing.allocator, undefined);
    defer io_impl.deinit();
    const io = io_impl.io();

    var client = try dagger.connect(std.testing.allocator, io, .{});
    defer client.close();

    const ctr = try client.dag().container();
    const ctr1 = try ctr.from("alpine:latest");
    const ctr2 = try ctr1.withExec(&.{ "echo", "published" });

    const addr = try std.fmt.allocPrint(std.testing.allocator, "{s}/dagger-zig-test:latest", .{registry});
    defer std.testing.allocator.free(addr);

    const digest = try ctr2.publish(addr);
    defer std.testing.allocator.free(digest);

    try std.testing.expect(digest.len > 0);
}
