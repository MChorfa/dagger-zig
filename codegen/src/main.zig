//! `dagger-codegen` — generates `sdk/lib/src/gen.zig` from the Dagger
//! introspection schema.
//!
//! Usage:
//!   dagger run -- zig build codegen -- --out sdk/lib/src/gen.zig   (live engine)
//!   zig build codegen -- --schema introspection.json --out sdk/lib/src/gen.zig
//!
//! `--schema` reads a previously captured introspection response instead of
//! connecting to a live engine. The file may be the raw GraphQL envelope
//! (`{"data":{"__schema":...}}`), a `{"__schema":...}` wrapper, or a bare
//! schema object (`{"queryType":...,"types":[...]}`) — e.g. upstream's
//! `cmd/codegen/introspection/testdata/schema.json`.

const std = @import("std");
const dagger = @import("dagger_sdk");
const intro = @import("introspection.zig");
const emit = @import("emit.zig");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;
    const arena = init.arena.allocator();

    const args = try init.minimal.args.toSlice(arena);

    var out_path: ?[]const u8 = null;
    var schema_path: ?[]const u8 = null;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--out") and i + 1 < args.len) {
            out_path = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--schema") and i + 1 < args.len) {
            schema_path = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--help") or std.mem.eql(u8, args[i], "-h")) {
            var stdout = std.Io.File.stdout();
            defer stdout.close(io);
            try stdout.writeStreamingAll(io,
                \\dagger-codegen — Zig SDK code generator
                \\
                \\Usage:
                \\  dagger-codegen [--out PATH] [--schema PATH]
                \\
                \\  --schema PATH   Read a captured introspection JSON instead of
                \\                  querying a live engine.
                \\  --out PATH      Output file (default: stdout).
                \\
            );
            return;
        }
    }

    var body: []u8 = undefined;
    if (schema_path) |p| {
        const cwd = std.Io.Dir.cwd();
        body = try cwd.readFileAlloc(io, p, gpa, .limited(256 * 1024 * 1024));
    } else {
        var client = try dagger.connect(gpa, io, .{});
        defer client.close();
        body = try client.gql.query(intro.query);
    }
    defer gpa.free(body);

    var parsed = try intro.parse(arena, body);
    defer parsed.deinit();

    var emitter = emit.Emitter.init(arena);
    defer emitter.deinit();

    try emitter.emitAll(parsed.value);

    if (out_path) |p| {
        var cwd = std.Io.Dir.cwd();
        var f = try cwd.createFile(io, p, .{});
        defer f.close(io);
        try f.writeStreamingAll(io, emitter.source());
        std.debug.print("codegen: wrote {d} bytes to {s}\n", .{ emitter.source().len, p });
    } else {
        var stdout = std.Io.File.stdout();
        defer stdout.close(io);
        try stdout.writeStreamingAll(io, emitter.source());
    }
}
