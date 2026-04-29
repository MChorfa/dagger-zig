//! Secrets example: demonstrate setSecret and withSecret usage.
//!
//! Run under a Dagger session:
//!
//!   dagger run -- zig build run-secrets
//!
//! This example shows how to:
//!   - Set a secret from environment variable
//!   - Pass secrets to container commands
//!   - Use secrets in build pipelines

const std = @import("std");
const dagger = @import("dagger_sdk");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var client = try dagger.connect(gpa, io, .{});
    defer client.close();

    // Get secret from environment (in real use, use proper secret management)
    const api_key = blk: {
        break :blk std.process.getEnvVarOwned(gpa, "API_KEY") catch {
            std.log.info("Using dummy API_KEY for demo. Set API_KEY env var for real test.", .{});
            break :blk try gpa.dupe(u8, "dummy-api-key-12345");
        };
    };
    defer gpa.free(api_key);

    // Set the secret in Dagger
    const secret = try client.dag().setSecret("api-key", api_key);

    // Build a container that uses the secret
    const ctr = try client.dag()
        .container()
        .from("alpine:latest");

    // Mount the secret and use it (safely - doesn't leak in logs)
    const ctr_with_secret = try ctr
        .withSecret("/run/secrets/api-key", secret);

    // Verify secret is accessible but masked in output
    const ctr_verified = try ctr_with_secret
        .withExec(&.{ "sh", "-c", "echo 'Secret exists:' && test -f /run/secrets/api-key && echo 'YES' || echo 'NO'" });

    const out = try ctr_verified.stdout();
    defer gpa.free(out);

    var stdout_file = std.Io.File.stdout();
    defer stdout_file.close(io);
    try stdout_file.writeStreamingAll(io, out);

    std.log.info("Secret handling complete. API key was never exposed in logs!", .{});
}
