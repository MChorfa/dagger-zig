//! Build pipeline: demonstrates the full chain — base image, workdir, env,
//! cache volume, exec, stdout capture.

const std = @import("std");
const dagger = @import("dagger_sdk");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var client = try dagger.connect(gpa, io, .{});
    defer client.close();

    const q = client.dag();
    const cache = try q.cacheVolume("zig-global-cache");

    const ctr = try q.container();
    const ctr2 = try ctr.from("alpine:3.20");
    const ctr3 = try ctr2.withWorkdir("/work");
    const ctr4 = try ctr3.withEnvVariable("HELLO", "from dagger-zig");
    const ctr5 = try ctr4.withMountedCache("/var/cache/zig", cache);
    const ctr6 = try ctr5.withExec(&.{ "sh", "-c", "echo ${HELLO}; date" });

    const out = try ctr6.stdout();
    defer gpa.free(out);

    var stdout_file = std.Io.File.stdout();
    defer stdout_file.close(io);
    try stdout_file.writeStreamingAll(io, out);
}
