//! `serve` — the module runtime entry point.
//!
//! Protocol (from the Dagger engine's perspective):
//!
//!   1. Engine spawns the module binary with DAGGER_SESSION_PORT +
//!      DAGGER_SESSION_TOKEN set. We are the client in this session; the
//!      engine is serving its GraphQL API for us to query.
//!   2. Module connects to the engine via `dagger.connect`.
//!   3. Module queries `currentFunctionCall` to learn why it was invoked:
//!        - name == ""  → introspection mode: return the schema.
//!        - name != ""  → dispatch mode: run the named function.
//!   4. Module writes the result back via `currentFunctionCall.returnValue`.
//!   5. Module exits.
//!
//! All errors during dispatch surface as GraphQL errors the engine relays
//! to the caller of `dagger call`. Errors during introspection fail the
//! module load and prevent any invocations.

const std = @import("std");
const dagger = @import("../root.zig");
const dispatch = @import("dispatch.zig");
const td_mod = @import("typedef.zig");
const serde = @import("serde.zig");
const Context = @import("context.zig").Context;
const module_api = @import("../module_api.zig");

pub const ServeError = error{
    NotInvokedByEngine,
    UnknownFunction,
    BadArgs,
    SchemaRegistrationFailed,
} || anyerror;

/// Serve the given module instance for one engine invocation.
pub fn serve(init: std.process.Init, module_instance: anytype) ServeError!void {
    const M = @TypeOf(module_instance);
    const table = comptime dispatch.build(M);

    // Comptime check: at least one eligible method, or the module is useless.
    if (comptime table.len == 0) {
        @compileError("dagger-zig: module type `" ++ @typeName(M) ++
            "` has no eligible methods. A module method must be `pub fn name(self: *const Self, ctx: *Context, ...)`.");
    }

    const gpa = init.gpa;
    const io = init.io;

    // Connect to the engine. If the env vars aren't set, we aren't being
    // invoked by the engine — report and exit.
    var client = dagger.connect(gpa, io, .{}) catch |e| switch (e) {
        error.InvalidEnv => return error.NotInvokedByEngine,
        else => return e,
    };
    defer client.close();

    // Per-dispatch arena — everything we allocate while handling THIS
    // invocation goes here and is freed on return.
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var ctx: Context = .{
        .client = &client,
        .arena = arena,
        .io = io,
        .spiffe_source = null,
    };

    const mq = module_api.moduleQuery(client.dag());
    const call = try mq.currentFunctionCall();
    const fn_name = try call.name();
    defer gpa.free(fn_name);

    if (fn_name.len == 0) {
        return runIntrospection(M, &ctx, &call, table);
    } else {
        return runDispatch(M, &module_instance, &ctx, &call, fn_name, table);
    }
}

// ─────────────────────────── introspection ──────────────────────────────

/// Build the module's schema and return it as a `ModuleSource` ID.
///
/// The engine expects us to build a `ModuleSource` via its API, add each
/// user function with `withFunction(...)`, and call `.id()`.
///
/// Because our linear-chain querybuilder can't cleanly express the nested
/// TypeDef construction Dagger uses, we emit the raw introspection query
/// as a template string. This is the same approach other modules use when
/// their SDKs don't have a fluent schema builder.
fn runIntrospection(
    comptime M: type,
    ctx: *Context,
    call: *const module_api.FunctionCall,
    table: []const dispatch.Entry(M),
) !void {
    // Assemble the GraphQL mutation that builds the ModuleSource and
    // attaches one Function per table entry.
    var buf = std.ArrayList(u8).init(ctx.arena);
    defer buf.deinit();

    try buf.appendSlice(ctx.arena, "query{moduleSource(refString:\".\")");
    for (table) |entry| {
        try buf.appendSlice(ctx.arena, ".withFunction(function:");
        try emitFunctionBuilder(&buf, ctx.arena, entry.def);
        try buf.appendSlice(ctx.arena, ")");
    }
    try buf.appendSlice(ctx.arena, ".id}");

    // Execute the schema-building query. Returns the ModuleSource ID.
    const query_str = buf.items;
    const body = try ctx.client.gql.query(query_str);
    defer ctx.client.allocator.free(body);

    const parsed = try std.json.parseFromSlice(std.json.Value, ctx.arena, body, .{});
    defer parsed.deinit();

    const id = walkToString(parsed.value) orelse return error.SchemaRegistrationFailed;

    // Now hand the ID back to the engine via returnValue.
    const id_json = try std.fmt.allocPrint(ctx.arena, "\"{s}\"", .{id});
    try call.returnValue(id_json);
}

/// Emit the GraphQL fragment that constructs a `Function` value with its
/// return TypeDef and args. Appends into `buf`.
fn emitFunctionBuilder(
    buf: *std.ArrayList(u8),
    a: std.mem.Allocator,
    def: td_mod.FunctionDef,
) !void {
    // function(name: "X", returnType: <typedef>)
    try buf.appendSlice(a, "function(name:\"");
    try buf.appendSlice(a, def.name);
    try buf.appendSlice(a, "\",returnType:");
    try emitTypeDefBuilder(buf, a, def.return_type);
    try buf.appendSlice(a, ")");

    // Chain .withArg(name, typedef) for each arg.
    for (def.args) |arg| {
        try buf.appendSlice(a, ".withArg(name:\"");
        try buf.appendSlice(a, arg.name);
        try buf.appendSlice(a, "\",typeDef:");
        try emitTypeDefBuilder(buf, a, arg.type_def);
        try buf.appendSlice(a, ")");
    }
}

/// Emit the GraphQL fragment that constructs a `TypeDef` value.
/// Uses the engine's TypeDef builder: typeDef().withKind(X) then further
/// withXxx() for complex kinds.
fn emitTypeDefBuilder(
    buf: *std.ArrayList(u8),
    a: std.mem.Allocator,
    def: td_mod.TypeDef,
) !void {
    try buf.appendSlice(a, "typeDef");

    switch (def.kind) {
        .string, .integer, .boolean, .void_kind => {
            try buf.appendSlice(a, ".withKind(kind:");
            try buf.appendSlice(a, def.kind.graphqlName());
            try buf.appendSlice(a, ")");
        },
        .list => {
            try buf.appendSlice(a, ".withListOf(elementType:");
            try emitTypeDefBuilder(buf, a, def.element.?.*);
            try buf.appendSlice(a, ")");
        },
        .object => {
            try buf.appendSlice(a, ".withObject(name:\"");
            try buf.appendSlice(a, def.object_name.?);
            try buf.appendSlice(a, "\")");
        },
        .input => {
            try buf.appendSlice(a, ".withInput(name:\"");
            try buf.appendSlice(a, def.input.?.name);
            try buf.appendSlice(a, "\")");
            for (def.input.?.fields) |f| {
                try buf.appendSlice(a, ".withField(name:\"");
                try buf.appendSlice(a, f.name);
                try buf.appendSlice(a, "\",typeDef:");
                try emitTypeDefBuilder(buf, a, f.type_def);
                try buf.appendSlice(a, ")");
            }
        },
        .enum_kind => {
            try buf.appendSlice(a, ".withEnum(name:\"");
            try buf.appendSlice(a, def.enum_def.?.name);
            try buf.appendSlice(a, "\")");
            for (def.enum_def.?.values) |v| {
                try buf.appendSlice(a, ".withValue(name:\"");
                try buf.appendSlice(a, v);
                try buf.appendSlice(a, "\")");
            }
        },
    }

    if (def.optional) try buf.appendSlice(a, ".withOptional(optional:true)");
}

fn walkToString(v: std.json.Value) ?[]const u8 {
    return switch (v) {
        .string => |s| s,
        .object => |o| blk: {
            if (o.count() != 1) break :blk null;
            var it = o.iterator();
            const entry = it.next() orelse break :blk null;
            break :blk walkToString(entry.value_ptr.*);
        },
        else => null,
    };
}

// ─────────────────────────── dispatch ───────────────────────────────────

fn runDispatch(
    comptime M: type,
    module_instance: *const M,
    ctx: *Context,
    call: *const module_api.FunctionCall,
    fn_name: []const u8,
    table: []const dispatch.Entry(M),
) !void {
    // Find the entry for this function.
    const entry = for (table) |e| {
        if (std.mem.eql(u8, e.name, fn_name)) break e;
    } else {
        return error.UnknownFunction;
    };

    // Collect args into a single JSON object the serde layer can parse.
    const args_json = try assembleArgsJson(ctx.arena, call);

    // Build a Zig-stdlib writer we can pass into the shim for the return.
    // We use an ArrayList-backed writer; the final bytes become the JSON we
    // pass to returnValue().
    var buf = std.ArrayList(u8).init(ctx.arena);
    defer buf.deinit();

    var aw = std.Io.Writer.Allocating.fromArrayList(ctx.arena, &buf);
    entry.invoke(module_instance, ctx, args_json, &aw.writer) catch |e| {
        // Translate Zig errors into a GraphQL error by rerouting through
        // returnValue with a structured error payload. v0.1 keeps this
        // simple: send the error name as a string so `dagger call` shows
        // something actionable.
        const err_json = try std.fmt.allocPrint(
            ctx.arena,
            "{{\"error\":\"{s}\"}}",
            .{@errorName(e)},
        );
        try call.returnValue(err_json);
        return e;
    };
    buf = aw.toArrayList();

    try call.returnValue(buf.items);
}

/// Pull every inputArg from the FunctionCall and stitch them into a single
/// JSON object: `{"arg0": <value_json>, "arg1": <value_json>, ...}`.
/// Matches the arg-name convention the comptime shim uses in dispatch.zig.
fn assembleArgsJson(
    a: std.mem.Allocator,
    call: *const module_api.FunctionCall,
) ![]const u8 {
    const args = try call.inputArgs();
    defer {
        for (args) |*arg| arg.deinit();
        a.free(args);
    }

    var buf = std.ArrayList(u8).init(a);
    errdefer buf.deinit();

    try buf.append(a, '{');
    for (args, 0..) |arg, i| {
        if (i > 0) try buf.append(a, ',');
        var name_aw = std.Io.Writer.Allocating.fromArrayList(a, &buf);
        try std.json.Stringify.value(arg.name, .{}, &name_aw.writer);
        buf = name_aw.toArrayList();
        try buf.append(a, ':');
        // arg.value_json is already a JSON literal; copy verbatim.
        try buf.appendSlice(a, arg.value_json);
    }
    try buf.append(a, '}');
    return buf.toOwnedSlice(a);
}

// ─────────────────────────── tests ──────────────────────────────────────

const testing = std.testing;

test "comptime: module with no eligible methods fails to compile" {
    // We can't actually @compileError-check in a test, but we can verify
    // that a well-formed module passes the dispatch build. The negative
    // case is covered at compile time by the @compileError in serve().
    const OK = struct {
        pub fn run(self: *const @This(), ctx: *Context) !void {
            _ = self;
            _ = ctx;
        }
    };
    const table = comptime dispatch.build(OK);
    try testing.expectEqual(@as(usize, 1), table.len);
    try testing.expectEqualStrings("run", table[0].name);
}

test "emitTypeDefBuilder emits expected fragments" {
    const a = testing.allocator;
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(a);

    try emitTypeDefBuilder(&buf, a, .{ .kind = .string });
    try testing.expectEqualStrings("typeDef.withKind(kind:STRING_KIND)", buf.items);

    buf.clearRetainingCapacity();
    try emitTypeDefBuilder(&buf, a, .{ .kind = .boolean, .optional = true });
    try testing.expectEqualStrings(
        "typeDef.withKind(kind:BOOLEAN_KIND).withOptional(optional:true)",
        buf.items,
    );

    buf.clearRetainingCapacity();
    try emitTypeDefBuilder(&buf, a, .{
        .kind = .object,
        .object_name = "Container",
    });
    try testing.expectEqualStrings(
        "typeDef.withObject(name:\"Container\")",
        buf.items,
    );

    buf.clearRetainingCapacity();
    const int_def: td_mod.TypeDef = .{ .kind = .integer };
    try emitTypeDefBuilder(&buf, a, .{
        .kind = .list,
        .element = &int_def,
    });
    try testing.expectEqualStrings(
        "typeDef.withListOf(elementType:typeDef.withKind(kind:INTEGER_KIND))",
        buf.items,
    );
}

test "emitFunctionBuilder emits function + withArg chain" {
    const a = testing.allocator;
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(a);

    const str_def: td_mod.TypeDef = .{ .kind = .string };
    const int_def: td_mod.TypeDef = .{ .kind = .integer };
    const def: td_mod.FunctionDef = .{
        .name = "build",
        .args = &.{
            .{ .name = "target", .type_def = str_def },
            .{ .name = "parallelism", .type_def = int_def },
        },
        .return_type = str_def,
    };

    try emitFunctionBuilder(&buf, a, def);
    try testing.expectEqualStrings(
        "function(name:\"build\",returnType:typeDef.withKind(kind:STRING_KIND))" ++
            ".withArg(name:\"target\",typeDef:typeDef.withKind(kind:STRING_KIND))" ++
            ".withArg(name:\"parallelism\",typeDef:typeDef.withKind(kind:INTEGER_KIND))",
        buf.items,
    );
}
