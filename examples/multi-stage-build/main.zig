//! Multi-stage build example: demonstrate Docker multi-stage equivalent.
//!
//! Run under a Dagger session:
//!
//!   dagger run -- zig build run-multi-stage-build
//!
//! This example shows how to:
//!   - Build in one container (build stage)
//!   - Copy artifacts to another (runtime stage)
//!   - Minimize final image size
//!   - Separate build and runtime dependencies

const std = @import("std");
const dagger = @import("dagger_sdk");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var client = try dagger.connect(gpa, io, .{});
    defer client.close();

    // Stage 1: Build environment
    const build_ctr = try client.dag()
        .container()
        .from("golang:1.22-alpine");

    // Add build dependencies
    const build_with_deps = try build_ctr
        .withExec(&.{"apk", "add", "--no-cache", "git"});

    // Simulate a Go build (creating a simple binary)
    const build_with_code = try build_with_deps
        .withExec(&.{"sh", "-c", "mkdir -p /src && echo 'package main; import \"fmt\"; func main() { fmt.Println(\"Hello from multi-stage!\") }' > /src/main.go"});

    // Build the binary
    const build_output = try build_with_code
        .withWorkdir("/src")
        .withExec(&.{"go", "build", "-o", "app", "main.go"});

    // Export the binary
    const binary = try build_output.file("/src/app");

    // Stage 2: Runtime environment (minimal)
    const runtime_ctr = try client.dag()
        .container()
        .from("alpine:latest");

    // Only copy the binary, not the full Go toolchain
    const runtime_with_app = try runtime_ctr
        .withFile("/app", binary);

    // Make it executable and run
    const final = try runtime_with_app
        .withExec(&.{"chmod", "+x", "/app"});

    // Test the application
    const out = try final
        .withExec(&.{"/app"})
        .stdout();
    defer gpa.free(out);

    // Show size comparison
    const size_info = try final
        .withExec(&.{"sh", "-c", "echo 'Final image size:' && du -sh / | tail -1"})
        .stdout();
    defer gpa.free(size_info);

    var stdout_file = std.Io.File.stdout();
    defer stdout_file.close(io);
    
    try stdout_file.writeStreamingAll(io, "=== Application Output ===\n");
    try stdout_file.writeStreamingAll(io, out);
    try stdout_file.writeStreamingAll(io, "\n=== Size Info ===\n");
    try stdout_file.writeStreamingAll(io, size_info);

    std.log.info("Multi-stage build complete! Final image contains only the binary.", .{});
}
