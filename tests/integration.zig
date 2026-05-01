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

test "container withEnvVariable and env resolution" {
    try skipIfNoEngine(std.testing.allocator);

    var io_impl: std.Io.Threaded = .init(std.testing.allocator);
    defer io_impl.deinit();
    const io = io_impl.io();

    var client = try dagger.connect(std.testing.allocator, io, .{});
    defer client.close();

    const ctr = try client.dag().container()
        .from("alpine:latest")
        .withEnvVariable("MY_VAR", "my_value");

    const ctr2 = try ctr.withExec(&.{ "sh", "-c", "echo $MY_VAR" });
    const out = try ctr2.stdout();
    defer std.testing.allocator.free(out);

    try std.testing.expect(std.mem.indexOf(u8, out, "my_value") != null);
}

test "directory operations" {
    try skipIfNoEngine(std.testing.allocator);

    var io_impl: std.Io.Threaded = .init(std.testing.allocator);
    defer io_impl.deinit();
    const io = io_impl.io();

    var client = try dagger.connect(std.testing.allocator, io, .{});
    defer client.close();

    // Create a directory with a file
    const dir = try client.dag().directory()
        .withNewFile("hello.txt", "Hello, World!");

    // Get file contents
    const file = try dir.file("hello.txt");
    const contents = try file.contents();
    defer std.testing.allocator.free(contents);

    try std.testing.expectEqualStrings("Hello, World!", contents);
}

test "cache volume persistence" {
    try skipIfNoEngine(std.testing.allocator);

    var io_impl: std.Io.Threaded = .init(std.testing.allocator);
    defer io_impl.deinit();
    const io = io_impl.io();

    var client = try dagger.connect(std.testing.allocator, io, .{});
    defer client.close();

    // Create cache volume
    const cache = try client.dag().cacheVolume("test-cache");

    // Use in container
    const ctr = try client.dag().container()
        .from("alpine:latest")
        .withMountedCache("/cache", cache);

    // Write to cache
    const ctr2 = try ctr.withExec(&.{ "sh", "-c", "echo cached > /cache/data.txt" });
    _ = try ctr2.sync();

    // Read from cache in new container
    const ctr3 = try client.dag().container()
        .from("alpine:latest")
        .withMountedCache("/cache", cache)
        .withExec(&.{ "cat", "/cache/data.txt" });

    const out = try ctr3.stdout();
    defer std.testing.allocator.free(out);

    try std.testing.expect(std.mem.indexOf(u8, out, "cached") != null);
}

test "git repository operations" {
    try skipIfNoEngine(std.testing.allocator);

    var io_impl: std.Io.Threaded = .init(std.testing.allocator);
    defer io_impl.deinit();
    const io = io_impl.io();

    var client = try dagger.connect(std.testing.allocator, io, .{});
    defer client.close();

    // Clone a public repo
    const repo = try client.dag().git("https://github.com/dagger/hello-dagger");
    const head = try repo.head();
    const tree = try head.tree();

    // Check that we got a valid directory
    const id = try tree.id();
    defer id.deinit(std.testing.allocator);

    try std.testing.expect(id.value.len > 0);
}

test "secret handling" {
    try skipIfNoEngine(std.testing.allocator);

    var io_impl: std.Io.Threaded = .init(std.testing.allocator);
    defer io_impl.deinit();
    const io = io_impl.io();

    var client = try dagger.connect(std.testing.allocator, io, .{});
    defer client.close();

    const secret = try client.dag().setSecret("my-secret", "secret-value");

    // Use secret in container
    const ctr = try client.dag().container()
        .from("alpine:latest")
        .withSecretVariable("SECRET", secret)
        .withExec(&.{ "sh", "-c", "echo $SECRET > /dev/null" });

    _ = try ctr.sync();
}

test "multi-platform container" {
    try skipIfNoEngine(std.testing.allocator);

    var io_impl: std.Io.Threaded = .init(std.testing.allocator);
    defer io_impl.deinit();
    const io = io_impl.io();

    var client = try dagger.connect(std.testing.allocator, io, .{});
    defer client.close();

    const ctr = try client.dag().container()
        .from("alpine:latest");

    const ctr2 = try ctr.withExec(&.{ "uname", "-m" });
    const out = try ctr2.stdout();
    defer std.testing.allocator.free(out);

    // Should output architecture
    try std.testing.expect(out.len > 0);
}

test "container publish and reference" {
    try skipIfNoEngine(std.testing.allocator);

    // Skip if no registry credentials
    const registry = std.process.getEnvVarOwned(std.testing.allocator, "TEST_REGISTRY") catch {
        std.debug.print("SKIP: no TEST_REGISTRY set\n", .{});
        return error.SkipZigTest;
    };
    defer std.testing.allocator.free(registry);

    var io_impl: std.Io.Threaded = .init(std.testing.allocator);
    defer io_impl.deinit();
    const io = io_impl.io();

    var client = try dagger.connect(std.testing.allocator, io, .{});
    defer client.close();

    const ctr = try client.dag().container()
        .from("alpine:latest")
        .withExec(&.{ "echo", "published" });

    const addr = try std.fmt.allocPrint(std.testing.allocator, "{s}/dagger-zig-test:latest", .{registry});
    defer std.testing.allocator.free(addr);

    const digest = try ctr.publish(addr);
    defer std.testing.allocator.free(digest);

    try std.testing.expect(digest.len > 0);
}
