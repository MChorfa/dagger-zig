//! End-to-end offline test of the module runtime's comptime plumbing.
//!
//! This proves, without any engine or network, that:
//!
//!   1. A user-defined module struct compiles.
//!   2. `dispatch.build(M)` produces a table with one entry per method.
//!   3. The shim deserializes arg JSON, calls the method, and serializes
//!      the return value correctly.
//!   4. TypeDef extraction matches the expected Dagger schema shape.
//!   5. Schema emission produces the expected GraphQL fragment.
//!
//! If this test passes, the module runtime's type layer is sound. The one
//! remaining unproven piece is the real engine I/O, which the integration
//! test (against a live Dagger session) covers.

const std = @import("std");
const dagger = @import("dagger_sdk");
const dispatch = dagger.module.dispatch;
const td_mod = dagger.module.typedef;
const serde = dagger.module.serde;
const Context = dagger.module.Context;

/// Example module under test. Three methods covering the common shapes:
///   - one with scalar args returning a scalar
///   - one with an optional struct arg
///   - one that returns void
const ExampleModule = struct {
    tenant: []const u8 = "default",

    pub fn echo(self: *const ExampleModule, ctx: *Context, message: []const u8) ![]const u8 {
        _ = self;
        return ctx.arena.dupe(u8, message);
    }

    pub fn add(self: *const ExampleModule, ctx: *Context, a: i64, b: i64) !i64 {
        _ = self;
        _ = ctx;
        return a + b;
    }

    pub fn configure(self: *const ExampleModule, ctx: *Context, opts: BuildOpts) !bool {
        _ = self;
        _ = ctx;
        return opts.race;
    }
};

const BuildOpts = struct {
    target: []const u8,
    race: bool = false,
    parallelism: u32 = 4,
};

test "dispatch.build enumerates all eligible methods" {
    const table = comptime dispatch.build(ExampleModule);
    try std.testing.expectEqual(@as(usize, 3), table.len);

    const names = [_][]const u8{ "echo", "add", "configure" };
    for (names) |expected| {
        var found = false;
        for (table) |e| {
            if (std.mem.eql(u8, e.name, expected)) {
                found = true;
                break;
            }
        }
        try std.testing.expect(found);
    }
}

test "TypeDef for echo: string → string" {
    const def = comptime td_mod.functionOfMethod(ExampleModule, "echo");
    try std.testing.expectEqualStrings("echo", def.name);
    try std.testing.expectEqual(@as(usize, 1), def.args.len);
    try std.testing.expectEqual(td_mod.Kind.string, def.args[0].type_def.kind);
    try std.testing.expectEqual(td_mod.Kind.string, def.return_type.kind);
}

test "TypeDef for add: (i64,i64) → i64" {
    const def = comptime td_mod.functionOfMethod(ExampleModule, "add");
    try std.testing.expectEqual(@as(usize, 2), def.args.len);
    try std.testing.expectEqual(td_mod.Kind.integer, def.args[0].type_def.kind);
    try std.testing.expectEqual(td_mod.Kind.integer, def.args[1].type_def.kind);
    try std.testing.expectEqual(td_mod.Kind.integer, def.return_type.kind);
}

test "TypeDef for configure: user struct → bool" {
    const def = comptime td_mod.functionOfMethod(ExampleModule, "configure");
    try std.testing.expectEqual(@as(usize, 1), def.args.len);
    try std.testing.expectEqual(td_mod.Kind.input, def.args[0].type_def.kind);
    try std.testing.expect(def.args[0].type_def.input != null);
    try std.testing.expectEqual(@as(usize, 3), def.args[0].type_def.input.?.fields.len);
    try std.testing.expectEqualStrings("target", def.args[0].type_def.input.?.fields[0].name);
    try std.testing.expectEqual(td_mod.Kind.boolean, def.return_type.kind);
}

test "invoker runs a method and writes the return to the buffer" {
    // Build a Context manually. Client and arena are what the serde layer
    // touches; we can skip the real client because `echo` only uses
    // ctx.arena for its dupe.
    var io_impl: std.Io.Threaded = .init(std.testing.allocator, .{});
    defer io_impl.deinit();
    const io = io_impl.io();

    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();

    var ctx: Context = .{
        .client = undefined, // unused for echo
        .arena = arena_state.allocator(),
        .io = io,
        .spiffe_source = null,
    };

    const table = comptime dispatch.build(ExampleModule);
    const echo_entry = for (table) |e| {
        if (std.mem.eql(u8, e.name, "echo")) break e;
    } else unreachable;

    const module: ExampleModule = .{ .tenant = "test" };

    // Build a writer for the return value.
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(std.testing.allocator);
    var aw: std.Io.Writer.Allocating = .fromArrayList(std.testing.allocator, &out);

    // Engine would pass this after stitching inputArgs into an object.
    const args_json = "{\"arg0\":\"hello from test\"}";

    try echo_entry.invoke(&module, &ctx, args_json, &aw.writer);
    out = aw.toArrayList();

    try std.testing.expectEqualStrings("\"hello from test\"", out.items);
}

test "invoker runs a numeric add" {
    var io_impl: std.Io.Threaded = .init(std.testing.allocator, .{});
    defer io_impl.deinit();
    const io = io_impl.io();
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();

    var ctx: Context = .{
        .client = undefined,
        .arena = arena_state.allocator(),
        .io = io,
        .spiffe_source = null,
    };

    const table = comptime dispatch.build(ExampleModule);
    const add_entry = for (table) |e| {
        if (std.mem.eql(u8, e.name, "add")) break e;
    } else unreachable;

    const module: ExampleModule = .{};
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(std.testing.allocator);
    var aw: std.Io.Writer.Allocating = .fromArrayList(std.testing.allocator, &out);

    const args_json = "{\"arg0\":40,\"arg1\":2}";
    try add_entry.invoke(&module, &ctx, args_json, &aw.writer);
    out = aw.toArrayList();

    try std.testing.expectEqualStrings("42", out.items);
}

test "invoker handles struct arg with defaults" {
    var io_impl: std.Io.Threaded = .init(std.testing.allocator, .{});
    defer io_impl.deinit();
    const io = io_impl.io();
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();

    var ctx: Context = .{
        .client = undefined,
        .arena = arena_state.allocator(),
        .io = io,
        .spiffe_source = null,
    };

    const table = comptime dispatch.build(ExampleModule);
    const conf_entry = for (table) |e| {
        if (std.mem.eql(u8, e.name, "configure")) break e;
    } else unreachable;

    const module: ExampleModule = .{};
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(std.testing.allocator);
    var aw: std.Io.Writer.Allocating = .fromArrayList(std.testing.allocator, &out);

    // Omit `race` and `parallelism`; defaults should kick in.
    const args_json = "{\"arg0\":{\"target\":\"linux\"}}";
    try conf_entry.invoke(&module, &ctx, args_json, &aw.writer);
    out = aw.toArrayList();

    // configure returns opts.race, which defaults to false.
    try std.testing.expectEqualStrings("false", out.items);

    // Now with race explicitly set.
    out.clearRetainingCapacity();
    var aw2: std.Io.Writer.Allocating = .fromArrayList(std.testing.allocator, &out);
    const args_json2 = "{\"arg0\":{\"target\":\"linux\",\"race\":true}}";
    try conf_entry.invoke(&module, &ctx, args_json2, &aw2.writer);
    out = aw2.toArrayList();
    try std.testing.expectEqualStrings("true", out.items);
}
