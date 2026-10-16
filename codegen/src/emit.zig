//! Zig source emitter.
//!
//! Given a parsed `Schema`, emit a Zig file (`gen.zig`) containing:
//!   - one `pub const XxxID = struct { value, toWire, deinit }` per Node type
//!   - one `pub const Foo = struct { ... }` per OBJECT/INTERFACE type, with
//!     methods mirroring its GraphQL fields
//!   - one `pub const FooEnum = enum { ..., toWire, fromString }` per ENUM
//!   - one `pub const Bar = struct { ... }` per INPUT_OBJECT
//!   - the root Query object, plus synthetic `loadXFromID` methods that use
//!     the modern `node(id:)` + inline-fragment selection
//!
//! This is a straight text generator. We deliberately do NOT build an AST —
//! Zig source is line-oriented and templated emission is easier to debug.
//!
//! ## Schema model (engine >= v0.21.x)
//!
//! Object identity uses the plain `ID` scalar; `XxxID` scalar types are gone
//! from introspection. Dagger carries the type an ID refers to in the
//! nonstandard `@expectedType(name:)` applied directive, which dagql's
//! introspection exposes on fields and input values:
//!
//!   - `field: ID! @expectedType(name: "Container")` — execute the field,
//!     then reconstruct `Container` via `node(id:)` + `... on Container`.
//!   - `arg: ID! @expectedType(name: "Directory")` — the parameter is a
//!     `Directory` object; we resolve `obj.id()` eagerly before serializing.
//!   - `field: [ID!]! @expectedType(...)` — list of IDs, same via node().
//!   - `field: [X!]!` (OBJECT) — select `{ field { id } }`, then rebuild each
//!     element via `node(id:)` + fragment.
//!
//! ## Mapping rules
//!
//! | GraphQL             | Zig                           |
//! |---------------------|-------------------------------|
//! | String              | []const u8 arg / []u8 ret     |
//! | Int                 | i64                           |
//! | Float               | f64                           |
//! | Boolean             | bool                          |
//! | ID (bare)           | []const u8 arg / []u8 ret     |
//! | ID + @expectedType  | object handle (see above)     |
//! | JSON, Platform      | opaque string wrapper         |
//! | Void                | void                          |
//! | [T]                 | []const T arg / []T ret       |
//! | T!                  | unwraps one NON_NULL layer    |
//! | OBJECT              | lazy struct wrapper           |
//! | ENUM                | generated enum                |

const std = @import("std");
const intro = @import("introspection.zig");

pub const Emitter = struct {
    allocator: std.mem.Allocator,
    out: std.ArrayList(u8),
    /// Names of OBJECT and INTERFACE types (post-filter). Used to know which
    /// names are loadable node types and for `{Name}ID` wrapper emission.
    object_names: std.StringHashMap(void),
    /// Enum type names — needed to distinguish enum args (bare literal) from
    /// scalar wrappers at emission time.
    enum_names: std.StringHashMap(void),

    pub fn init(allocator: std.mem.Allocator) Emitter {
        return .{
            .allocator = allocator,
            .out = .empty,
            .object_names = std.StringHashMap(void).init(allocator),
            .enum_names = std.StringHashMap(void).init(allocator),
        };
    }

    pub fn deinit(self: *Emitter) void {
        self.out.deinit(self.allocator);
        self.object_names.deinit();
        self.enum_names.deinit();
    }

    pub fn source(self: *Emitter) []const u8 {
        return self.out.items;
    }

    // ── top level ───────────────────────────────────────────────────────────

    pub fn emitAll(self: *Emitter, schema: intro.Schema) !void {
        // Index type names.
        for (schema.types) |t| {
            const name = t.name orelse continue;
            if (isInternalName(name)) continue;
            if (std.mem.eql(u8, t.kind, "OBJECT") or std.mem.eql(u8, t.kind, "INTERFACE")) {
                try self.object_names.put(name, {});
            } else if (std.mem.eql(u8, t.kind, "ENUM")) {
                try self.enum_names.put(name, {});
            }
        }

        try self.writePrelude();

        // Collect + sort each bucket deterministically.
        const scalars = try self.sortedTypes(schema, "SCALAR");
        const inputs = try self.sortedTypes(schema, "INPUT_OBJECT");
        const enums = try self.sortedTypes(schema, "ENUM");
        const objects = try self.sortedKinds(schema, &.{ "OBJECT", "INTERFACE" });
        defer {
            self.allocator.free(scalars);
            self.allocator.free(inputs);
            self.allocator.free(enums);
            self.allocator.free(objects);
        }

        // 1. Custom scalars (JSON, Platform — Void is emitted as `void`).
        for (scalars) |t| try self.emitScalar(t);

        // 2. `{Name}ID` wrappers for every object/interface.
        for (objects) |t| try self.emitIdWrapper(t.name.?);

        // 3. Input objects.
        for (inputs) |t| try self.emitInput(t);

        // 4. Enums.
        for (enums) |t| try self.emitEnum(t);

        // 5. Objects; the query root first so it is easy to find.
        for (objects) |t| {
            if (std.mem.eql(u8, t.name.?, self.queryName(schema))) {
                try self.emitObject(t, true);
            }
        }
        for (objects) |t| {
            if (!std.mem.eql(u8, t.name.?, self.queryName(schema))) {
                try self.emitObject(t, false);
            }
        }
    }

    fn queryName(self: *Emitter, schema: intro.Schema) []const u8 {
        _ = self;
        if (schema.queryType) |q| return q.name;
        return "Query";
    }

    fn isInternalName(name: []const u8) bool {
        return std.mem.startsWith(u8, name, "_") or std.mem.startsWith(u8, name, "__");
    }

    fn isBuiltinScalar(name: []const u8) bool {
        const builtins = [_][]const u8{ "String", "Float", "Int", "Boolean", "DateTime", "ID" };
        for (builtins) |b| if (std.mem.eql(u8, name, b)) return true;
        return false;
    }

    fn sortedTypes(self: *Emitter, schema: intro.Schema, kind: []const u8) ![]const intro.FullType {
        return self.sortedKinds(schema, &.{kind});
    }

    fn sortedKinds(self: *Emitter, schema: intro.Schema, kinds: []const []const u8) ![]const intro.FullType {
        var matches: std.ArrayList(intro.FullType) = .empty;
        defer matches.deinit(self.allocator);
        for (schema.types) |t| {
            const name = t.name orelse continue;
            if (isInternalName(name)) continue;
            for (kinds) |k| {
                if (std.mem.eql(u8, t.kind, k)) {
                    try matches.append(self.allocator, t);
                    break;
                }
            }
        }
        std.mem.sort(intro.FullType, matches.items, {}, struct {
            fn lt(_: void, a: intro.FullType, b: intro.FullType) bool {
                return std.mem.lessThan(u8, a.name.?, b.name.?);
            }
        }.lt);
        return matches.toOwnedSlice(self.allocator);
    }

    // ── prelude + runtime helpers ───────────────────────────────────────────

    fn writePrelude(self: *Emitter) !void {
        try self.writeAll(
            \\//! Auto-generated from the Dagger introspection schema.
            \\//! DO NOT EDIT — regenerate with `zig build codegen`.
            \\
            \\const std = @import("std");
            \\const qb = @import("querybuilder.zig");
            \\const gql = @import("core/graphql_client.zig");
            \\const Selection = qb.Selection;
            \\const GraphQLClient = gql.GraphQLClient;
            \\
            \\// ── execution helpers ────────────────────────────────────────────────
            \\
            \\/// Walk the GraphQL `data` payload down its single-key object chain to
            \\/// the terminal JSON value (generated methods select exactly one field
            \\/// per level).
            \\fn walkLeaf(v: std.json.Value) ?std.json.Value {
            \\    return switch (v) {
            \\        .object => |o| blk: {
            \\            if (o.count() != 1) break :blk null;
            \\            var it = o.iterator();
            \\            const entry = it.next() orelse break :blk null;
            \\            break :blk walkLeaf(entry.value_ptr.*);
            \\        },
            \\        else => v,
            \\    };
            \\}
            \\
            \\/// Execute `sel` and decode the leaf into `T`. Caller owns the result
            \\/// via `allocator`. For `T == void` the response is validated only to
            \\/// the transport layer and then discarded.
            \\fn executeLeaf(
            \\    comptime T: type,
            \\    allocator: std.mem.Allocator,
            \\    sel: *const Selection,
            \\    client: *GraphQLClient,
            \\) !T {
            \\    const query_str = try sel.build(allocator);
            \\    defer allocator.free(query_str);
            \\
            \\    const body = try client.query(query_str);
            \\    defer allocator.free(body);
            \\
            \\    if (T == void) return;
            \\
            \\    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch
            \\        return error.MalformedResponse;
            \\    defer parsed.deinit();
            \\
            \\    const root = parsed.value.object.get("data") orelse return error.InvalidEnvelope;
            \\    const leaf = walkLeaf(root) orelse return error.InvalidEnvelope;
            \\    return std.json.parseFromValueLeaky(T, allocator, leaf, .{
            \\        .ignore_unknown_fields = true,
            \\        .allocate = .alloc_always,
            \\    }) catch return error.MalformedResponse;
            \\}
            \\
            \\/// Execute `sel`, expecting a leaf of the form `[{id: "..."}, ...]`.
            \\/// The caller is responsible for selecting the `id` subfield.
            \\fn executeIdList(
            \\    allocator: std.mem.Allocator,
            \\    sel: *const Selection,
            \\    client: *GraphQLClient,
            \\) ![][]const u8 {
            \\    const query_str = try sel.build(allocator);
            \\    defer allocator.free(query_str);
            \\
            \\    const body = try client.query(query_str);
            \\    defer allocator.free(body);
            \\
            \\    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch
            \\        return error.MalformedResponse;
            \\    defer parsed.deinit();
            \\
            \\    const root = parsed.value.object.get("data") orelse return error.InvalidEnvelope;
            \\    const leaf = walkLeaf(root) orelse return error.InvalidEnvelope;
            \\    if (leaf != .array) return error.InvalidEnvelope;
            \\
            \\    var out: std.ArrayList([]const u8) = .empty;
            \\    errdefer out.deinit(allocator);
            \\    for (leaf.array.items) |item| {
            \\        if (item != .object) return error.InvalidEnvelope;
            \\        const idv = item.object.get("id") orelse return error.InvalidEnvelope;
            \\        if (idv != .string) return error.InvalidEnvelope;
            \\        try out.append(allocator, try allocator.dupe(u8, idv.string));
            \\    }
            \\    return out.toOwnedSlice(allocator);
            \\}
            \\
            \\/// Rebuild a typed object handle from an engine ID via the modern
            \\/// `node(id:)` loader scoped by an inline fragment.
            \\fn loadNode(
            \\    comptime T: type,
            \\    ctx: anytype,
            \\    comptime type_name: []const u8,
            \\    id: []const u8,
            \\) !T {
            \\    const s1 = try Selection.root.select(ctx.arena, "node");
            \\    const s2 = try s1.arg(ctx.arena, "id", .{ .eager = try qb.serializeString(ctx.arena, id) });
            \\    const s3 = try s2.selectInlineFragment(ctx.arena, type_name);
            \\    return .{ .allocator = ctx.allocator, .arena = ctx.arena, .selection = s3, .gql = ctx.gql };
            \\}
            \\
            \\fn refAllDecls(comptime T: type) void {
            \\    inline for (comptime std.meta.declarations(T)) |d| {
            \\        const decl_name = comptime if (@hasField(@TypeOf(d), "name")) d.name else d;
            \\        _ = &@field(T, decl_name);
            \\        const DT = @field(T, decl_name);
            \\        if (@TypeOf(DT) == type) {
            \\            switch (@typeInfo(DT)) {
            \\                .@"struct", .@"enum", .@"union" => refAllDecls(DT),
            \\                else => {},
            \\            }
            \\        }
            \\    }
            \\}
            \\
            \\// Compile gate: `zig build test` analyzes every generated method body.
            \\test "all generated declarations analyze" {
            \\    refAllDecls(@This());
            \\}
            \\
            \\
        );
    }

    // ── scalars + ID wrappers ───────────────────────────────────────────────

    fn emitScalar(self: *Emitter, t: intro.FullType) !void {
        const name = t.name.?;
        if (isBuiltinScalar(name)) return; // String/Int/Float/Boolean/DateTime/ID map inline
        if (std.mem.eql(u8, name, "Void")) return; // Void maps to Zig void
        try self.writeDoc(t.description);
        try self.print(
            \\/// Opaque `{s}` scalar.
            \\pub const {s} = struct {{
            \\    value: []const u8,
            \\    pub fn toWire(self: {s}) []const u8 {{ return self.value; }}
            \\    pub fn deinit(self: *{s}, allocator: std.mem.Allocator) void {{
            \\        allocator.free(self.value);
            \\    }}
            \\}};
            \\
            \\
        , .{ name, name, name, name });
    }

    fn emitIdWrapper(self: *Emitter, name: []const u8) !void {
        try self.print(
            \\/// Opaque engine ID for `{s}`.
            \\pub const {s}ID = struct {{
            \\    value: []const u8,
            \\    pub fn toWire(self: {s}ID) []const u8 {{ return self.value; }}
            \\    pub fn deinit(self: *{s}ID, allocator: std.mem.Allocator) void {{
            \\        allocator.free(self.value);
            \\    }}
            \\}};
            \\
            \\
        , .{ name, name, name, name });
    }

    // ── input objects ───────────────────────────────────────────────────────

    fn emitInput(self: *Emitter, t: intro.FullType) !void {
        const name = t.name.?;
        try self.writeDoc(t.description);
        try self.print("pub const {s} = struct {{\n", .{name});
        if (t.inputFields) |fields| {
            const sorted = try self.allocator.dupe(intro.InputValue, fields);
            defer self.allocator.free(sorted);
            std.mem.sort(intro.InputValue, sorted, {}, inputValueLessThan);
            for (sorted) |f| {
                try self.writeDocIndented(f.description, "    ");
                const zt = try self.toZigType(f.type, .input);
                defer self.allocator.free(zt);
                const fname = try self.zigIdent(f.name);
                defer self.allocator.free(fname);
                // toZigType already emits `?T` for nullable refs.
                if (f.isOptional()) {
                    try self.print("    {s}: {s} = null,\n", .{ fname, zt });
                } else {
                    try self.print("    {s}: {s},\n", .{ fname, zt });
                }
            }
        }
        try self.writeAll("};\n\n");
    }

    // ── enums ───────────────────────────────────────────────────────────────

    fn emitEnum(self: *Emitter, t: intro.FullType) !void {
        const name = t.name.?;
        try self.writeDoc(t.description);
        try self.print("pub const {s} = enum {{\n    const Self = @This();\n", .{name});

        var tags: std.ArrayList(struct { tag: []const u8, wire: []const u8, doc: ?[]const u8 }) = .empty;
        defer {
            for (tags.items) |t2| self.allocator.free(t2.tag);
            tags.deinit(self.allocator);
        }
        var seen = std.StringHashMap(void).init(self.allocator);
        defer seen.deinit();

        if (t.enumValues) |values| {
            for (values) |v| {
                const tag = try self.camelCase(v.name);
                if (seen.contains(tag)) continue;
                try seen.put(tag, {});
                try tags.append(self.allocator, .{
                    .tag = tag,
                    .wire = v.name,
                    .doc = v.description,
                });
            }
        }

        for (tags.items) |tag| {
            try self.writeDocIndented(tag.doc, "    ");
            try self.print("    {s},\n", .{tag.tag});
        }

        try self.writeAll("\n    /// GraphQL wire name for this enum value.\n    pub fn toWire(self: Self) []const u8 {\n        return switch (self) {\n");
        for (tags.items) |tag| {
            try self.print("            .{s} => \"{s}\",\n", .{ tag.tag, tag.wire });
        }
        try self.writeAll("        };\n    }\n\n    /// Parse a wire name back into a tag.\n    pub fn fromString(s: []const u8) !Self {\n");
        for (tags.items) |tag| {
            try self.print("        if (std.mem.eql(u8, s, \"{s}\")) return .{s};\n", .{ tag.wire, tag.tag });
        }
        try self.writeAll("        return error.UnknownEnumValue;\n    }\n};\n\n");
    }

    // ── objects ─────────────────────────────────────────────────────────────

    fn emitObject(self: *Emitter, t: intro.FullType, is_root: bool) !void {
        const name = t.name.?;
        try self.writeDoc(t.description);
        try self.print(
            \\pub const {s} = struct {{
            \\    allocator: std.mem.Allocator,
            \\    arena: std.mem.Allocator,
            \\    selection: *const Selection,
            \\    gql: *GraphQLClient,
            \\
            \\
        , .{name});

        if (t.fields) |fields| {
            const sorted = try self.allocator.dupe(intro.Field, fields);
            defer self.allocator.free(sorted);
            std.mem.sort(intro.Field, sorted, {}, fieldLessThan);

            // Sibling method names — args may not shadow them.
            var siblings: std.ArrayList([]const u8) = .empty;
            defer {
                for (siblings.items) |sn| self.allocator.free(sn);
                siblings.deinit(self.allocator);
            }
            for (sorted) |f| {
                const mn = try self.camelCase(f.name);
                defer self.allocator.free(mn);
                try siblings.append(self.allocator, try self.allocator.dupe(u8, bareIdent(mn)));
            }

            for (sorted) |f| {
                try self.emitField(name, f, siblings.items);
            }
        }

        // Synthetic `loadXFromID` methods on the root object — one per emitted
        // type, via the modern `node(id:)` + inline-fragment mechanism.
        if (is_root) {
            try self.writeAll("    // ── node loaders ───────────────────────────────────────────\n\n");
            var names: std.ArrayList([]const u8) = .empty;
            defer names.deinit(self.allocator);
            var it = self.object_names.keyIterator();
            while (it.next()) |k| try names.append(self.allocator, k.*);
            std.mem.sort([]const u8, names.items, {}, struct {
                fn lt(_: void, a: []const u8, b: []const u8) bool {
                    return std.mem.lessThan(u8, a, b);
                }
            }.lt);
            for (names.items) |obj_name| {
                try self.print(
                    \\    /// Load a {s} from its ID.
                    \\    pub fn load{s}FromID(self: {s}, id_arg: {s}ID) !{s} {{
                    \\        return loadNode({s}, self, "{s}", id_arg.value);
                    \\    }}
                    \\
                    \\
                , .{ obj_name, obj_name, t.name.?, obj_name, obj_name, obj_name, obj_name });
            }
        }

        try self.writeAll("};\n\n");
    }

    // ── fields ──────────────────────────────────────────────────────────────

    const ArgClass = struct {
        required: std.ArrayList(intro.InputValue),
        optional: std.ArrayList(intro.InputValue),
    };

    fn splitArgs(self: *Emitter, f: intro.Field) !ArgClass {
        var req: std.ArrayList(intro.InputValue) = .empty;
        var opt: std.ArrayList(intro.InputValue) = .empty;
        errdefer req.deinit(self.allocator);
        errdefer opt.deinit(self.allocator);
        for (f.args) |a| {
            if (a.isOptional()) {
                try opt.append(self.allocator, a);
            } else {
                try req.append(self.allocator, a);
            }
        }
        return .{ .required = req, .optional = opt };
    }

    fn emitField(self: *Emitter, parent: []const u8, f: intro.Field, siblings: []const []const u8) !void {
        try self.writeDocIndented(f.description, "    ");
        if (f.isDeprecated) {
            try self.print("    /// @deprecated: {s}\n", .{f.deprecationReason orelse "No reason provided."});
        }

        var args = try self.splitArgs(f);
        defer args.required.deinit(self.allocator);
        defer args.optional.deinit(self.allocator);

        const method_name = try self.camelCase(f.name);
        defer self.allocator.free(method_name);

        const ret_sig = try self.returnSig(parent, f);
        defer self.allocator.free(ret_sig);

        // Resolve all arg identifiers up front so the signature and the apply
        // statements use the same names.
        var arg_names: std.ArrayList([]const u8) = .empty;
        var opt_names: std.ArrayList([]const u8) = .empty;
        defer {
            for (arg_names.items) |n| self.allocator.free(n);
            for (opt_names.items) |n| self.allocator.free(n);
            arg_names.deinit(self.allocator);
            opt_names.deinit(self.allocator);
        }
        for (args.required.items) |a| {
            try arg_names.append(self.allocator, try self.argIdent(a.name, arg_names.items, siblings));
        }
        for (args.optional.items) |a| {
            try opt_names.append(self.allocator, try self.argIdent(a.name, opt_names.items, siblings));
        }

        try self.print("    pub fn {s}(self: {s}", .{ method_name, parent });

        for (args.required.items, arg_names.items) |a, an| {
            const at = try self.toZigType(a.type, .arg);
            defer self.allocator.free(at);
            const pt = try self.argParamType(a, at);
            defer self.allocator.free(pt);
            try self.print(", {s}: {s}", .{ an, pt });
        }

        if (args.optional.items.len > 0) {
            try self.writeAll(", options: struct {\n");
            for (args.optional.items, opt_names.items) |a, an| {
                const at = try self.toZigType(a.type, .arg);
                defer self.allocator.free(at);
                const pt = try self.argParamType(a, at);
                defer self.allocator.free(pt);
                try self.writeDocIndented(a.description, "        ");
                if (std.mem.startsWith(u8, pt, "?")) {
                    try self.print("        {s}: {s} = null,\n", .{ an, pt });
                } else {
                    try self.print("        {s}: ?{s} = null,\n", .{ an, pt });
                }
            }
            // Zig has no default parameter values; callers pass `.{}`.
            try self.writeAll("    }");
        }

        try self.print(") !{s} {{\n", .{ret_sig});
        const mut = args.required.items.len + args.optional.items.len > 0;
        try self.print("        {s} s = try self.selection.select(self.arena, \"{s}\");\n", .{ if (mut) "var" else "const", f.name });

        for (args.required.items, arg_names.items) |a, an| {
            try self.emitArgApply(a, an, "s");
        }
        for (args.optional.items, opt_names.items) |a, an| {
            try self.emitOptionalArgApply(a, an);
        }

        try self.emitReturn(f, "s");
        try self.writeAll("    }\n\n");
    }

    /// Emit the arg-application statements for a required arg. `sel_var` is the
    /// Selection chain variable name in scope.
    fn emitArgApply(self: *Emitter, a: intro.InputValue, zig_name: []const u8, sel_var: []const u8) !void {
        // ID-typed arg with @expectedType → object param; resolve id eagerly.
        if (self.expectedObjectType(a.type, a.directives) != null) {
            const bare = bareIdent(zig_name);
            if (self.listInnerObjectType(a.type, a.directives) != null) {
                try self.print(
                    \\        const __ids_{s} = try self.arena.alloc([]const u8, {s}.len);
                    \\        for ({s}, 0..) |__o, __i| {{
                    \\            var __id = try __o.id();
                    \\            defer __id.deinit(self.allocator);
                    \\            __ids_{s}[__i] = try self.arena.dupe(u8, __id.value);
                    \\        }}
                    \\        {s} = try {s}.arg(self.arena, "{s}", .{{ .eager = try qb.serializeValue(self.arena, __ids_{s}) }});
                    \\
                , .{ bare, zig_name, zig_name, bare, sel_var, sel_var, a.name, bare });
            } else {
                try self.print(
                    \\        var __id_{s} = try {s}.id();
                    \\        defer __id_{s}.deinit(self.allocator);
                    \\        {s} = try {s}.arg(self.arena, "{s}", .{{ .eager = try qb.serializeValue(self.arena, __id_{s}) }});
                    \\
                , .{ bare, zig_name, bare, sel_var, sel_var, a.name, bare });
            }
            return;
        }
        try self.print(
            "        {s} = try {s}.arg(self.arena, \"{s}\", .{{ .eager = try qb.serializeValue(self.arena, {s}) }});\n",
            .{ sel_var, sel_var, a.name, zig_name },
        );
    }

    fn emitOptionalArgApply(self: *Emitter, a: intro.InputValue, zig_name: []const u8) !void {
        if (self.expectedObjectType(a.type, a.directives)) |_| {
            if (self.listInnerObjectType(a.type, a.directives) != null) {
                try self.print(
                    \\        if (options.{s}) |__arg| {{
                    \\            const __ids = try self.arena.alloc([]const u8, __arg.len);
                    \\            for (__arg, 0..) |__o, __i| {{
                    \\                var __id = try __o.id();
                    \\                defer __id.deinit(self.allocator);
                    \\                __ids[__i] = try self.arena.dupe(u8, __id.value);
                    \\            }}
                    \\            s = try s.arg(self.arena, "{s}", .{{ .eager = try qb.serializeValue(self.arena, __ids) }});
                    \\        }}
                    \\
                , .{ zig_name, a.name });
            } else {
                try self.print(
                    \\        if (options.{s}) |__v| {{
                    \\            var __id = try __v.id();
                    \\            defer __id.deinit(self.allocator);
                    \\            s = try s.arg(self.arena, "{s}", .{{ .eager = try qb.serializeValue(self.arena, __id) }});
                    \\        }}
                    \\
                , .{ zig_name, a.name });
            }
            return;
        }
        try self.print(
            "        if (options.{s}) |__v| s = try s.arg(self.arena, \"{s}\", .{{ .eager = try qb.serializeValue(self.arena, __v) }});\n",
            .{ zig_name, a.name },
        );
    }

    // ── return decision tree ────────────────────────────────────────────────

    /// The declared Zig return type for the method signature.
    fn returnSig(self: *Emitter, parent: []const u8, f: intro.Field) ![]const u8 {
        const inner = self.unwrapAll(f.type);
        if (inner.name != null and std.mem.eql(u8, inner.name.?, "Void")) {
            return self.allocator.dupe(u8, "void");
        }
        // `id` on any object → `{Parent}ID` wrapper.
        if (std.mem.eql(u8, f.name, "id") and self.isBareId(f.type)) {
            return std.fmt.allocPrint(self.allocator, "{s}ID", .{parent});
        }
        // ID + @expectedType → object handle (possibly optional/list).
        if (self.expectedObjectType(f.type, f.directives)) |obj| {
            const optional = !std.mem.eql(u8, f.type.kind, "NON_NULL");
            const is_list = self.listInnerObjectType(f.type, f.directives) != null;
            if (is_list) return std.fmt.allocPrint(self.allocator, "[]{s}", .{obj});
            return std.fmt.allocPrint(self.allocator, "{s}{s}", .{ if (optional) "?" else "", obj });
        }
        return self.toZigType(f.type, .ret);
    }

    fn emitReturn(self: *Emitter, f: intro.Field, sel_var: []const u8) !void {
        const inner = self.unwrapAll(f.type);
        const optional = !std.mem.eql(u8, f.type.kind, "NON_NULL");

        // Void → execute and discard.
        if (inner.name != null and std.mem.eql(u8, inner.name.?, "Void")) {
            try self.print("        _ = try executeLeaf(void, self.allocator, {s}, self.gql);\n", .{sel_var});
            return;
        }

        // `id` → wrapper.
        if (std.mem.eql(u8, f.name, "id") and self.isBareId(f.type)) {
            try self.print(
                \\        const raw = try executeLeaf([]const u8, self.allocator, {s}, self.gql);
                \\        return .{{ .value = raw }};
                \\
            , .{sel_var});
            return;
        }

        // ID + @expectedType → node-load reconstruction.
        if (self.expectedObjectType(f.type, f.directives)) |obj| {
            if (self.listInnerObjectType(f.type, f.directives) != null) {
                // [ID!]! @expectedType(X) — leaf is an ID string list; dagql
                // resolves bare ID lists directly (no subfield needed).
                try self.print(
                    \\        const __ids = try executeLeaf([]const []const u8, self.allocator, {s}, self.gql);
                    \\        const __out = try self.allocator.alloc({s}, __ids.len);
                    \\        for (__ids, 0..) |__id, __i| __out[__i] = try loadNode({s}, self, "{s}", __id);
                    \\        return __out;
                    \\
                , .{ sel_var, obj, obj, obj });
            } else if (optional) {
                try self.print(
                    \\        const __id = try executeLeaf(?[]const u8, self.allocator, {s}, self.gql);
                    \\        if (__id) |__v| return try loadNode({s}, self, "{s}", __v);
                    \\        return null;
                    \\
                , .{ sel_var, obj, obj });
            } else {
                try self.print(
                    \\        const __id = try executeLeaf([]const u8, self.allocator, {s}, self.gql);
                    \\        return try loadNode({s}, self, "{s}", __id);
                    \\
                , .{ sel_var, obj, obj });
            }
            return;
        }

        switch (self.innerKind(inner)) {
            .object => {
                if (self.listDepth(f.type) > 0) {
                    // [Object!]! — select `id` for each element, then rebuild.
                    try self.print("        const __sel = try {s}.select(self.arena, \"id\");\n", .{sel_var});
                    try self.print(
                        \\        const __ids = try executeIdList(self.allocator, __sel, self.gql);
                        \\        const __out = try self.allocator.alloc({s}, __ids.len);
                        \\        for (__ids, 0..) |__id, __i| __out[__i] = try loadNode({s}, self, "{s}", __id);
                        \\        return __out;
                        \\
                    , .{ inner.name.?, inner.name.?, inner.name.? });
                } else {
                    // Lazy chaining — do NOT execute.
                    try self.print(
                        \\        return .{{
                        \\            .allocator = self.allocator,
                        \\            .arena = self.arena,
                        \\            .selection = {s},
                        \\            .gql = self.gql,
                        \\        }};
                        \\
                    , .{sel_var});
                }
            },
            .@"enum" => {
                const en = inner.name.?;
                if (self.listDepth(f.type) > 0) {
                    try self.print(
                        \\        const __ss = try executeLeaf([]const []const u8, self.allocator, {s}, self.gql);
                        \\        const __out = try self.allocator.alloc({s}, __ss.len);
                        \\        for (__ss, 0..) |__v, __i| __out[__i] = try {s}.fromString(__v);
                        \\        return __out;
                        \\
                    , .{ sel_var, en, en });
                } else if (optional) {
                    try self.print(
                        \\        const __s = try executeLeaf(?[]const u8, self.allocator, {s}, self.gql);
                        \\        if (__s) |__v| return try {s}.fromString(__v);
                        \\        return null;
                        \\
                    , .{ sel_var, en });
                } else {
                    try self.print(
                        \\        const __s = try executeLeaf([]const u8, self.allocator, {s}, self.gql);
                        \\        return try {s}.fromString(__s);
                        \\
                    , .{ sel_var, en });
                }
            },
            .scalar => {
                const n = inner.name.?;
                if (std.mem.eql(u8, n, "ID")) {
                    // Bare ID without directive — opaque engine string.
                    if (self.listDepth(f.type) > 0) {
                        try self.print("        return try executeLeaf([]const []const u8, self.allocator, {s}, self.gql);\n", .{sel_var});
                    } else if (optional) {
                        try self.print("        return try executeLeaf(?[]const u8, self.allocator, {s}, self.gql);\n", .{sel_var});
                    } else {
                        try self.print("        return try executeLeaf([]const u8, self.allocator, {s}, self.gql);\n", .{sel_var});
                    }
                    return;
                }
                if (isBuiltinScalar(n)) {
                    const zt = try self.toZigType(f.type, .ret);
                    defer self.allocator.free(zt);
                    try self.print("        return try executeLeaf({s}, self.allocator, {s}, self.gql);\n", .{ zt, sel_var });
                    return;
                }
                // Custom scalar (JSON, Platform, …) → wrap leaf string.
                if (self.listDepth(f.type) > 0) {
                    try self.print(
                        \\        const __ss = try executeLeaf([]const []const u8, self.allocator, {s}, self.gql);
                        \\        const __out = try self.allocator.alloc({s}, __ss.len);
                        \\        for (__ss, 0..) |__v, __i| __out[__i] = .{{ .value = __v }};
                        \\        return __out;
                        \\
                    , .{ sel_var, n });
                } else if (optional) {
                    try self.print(
                        \\        const __s = try executeLeaf(?[]const u8, self.allocator, {s}, self.gql);
                        \\        if (__s) |__v| return .{{ .value = __v }};
                        \\        return null;
                        \\
                    , .{sel_var});
                } else {
                    try self.print(
                        \\        const __s = try executeLeaf([]const u8, self.allocator, {s}, self.gql);
                        \\        return .{{ .value = __s }};
                        \\
                    , .{sel_var});
                }
            },
            .other => {
                // INPUT_OBJECT / UNION / unknown — do not silently emit a
                // wrong binding; surface it at compile time when used.
                try self.print(
                    \\        @compileError("codegen: unsupported return type on field `{s}`");
                    \\
                , .{f.name});
            },
        }
    }

    // ── type analysis ───────────────────────────────────────────────────────

    const LeafKind = enum { object, @"enum", scalar, other };

    fn innerKind(self: *Emitter, inner: intro.TypeRef) LeafKind {
        if (std.mem.eql(u8, inner.kind, "OBJECT") or std.mem.eql(u8, inner.kind, "INTERFACE")) return .object;
        if (std.mem.eql(u8, inner.kind, "ENUM")) return .@"enum";
        if (std.mem.eql(u8, inner.kind, "SCALAR")) {
            if (inner.name) |n| {
                if (self.enum_names.contains(n)) return .@"enum";
            }
            return .scalar;
        }
        return .other;
    }

    /// Strip NON_NULL and LIST wrappers to the named leaf.
    fn unwrapAll(self: *Emitter, ref: intro.TypeRef) intro.TypeRef {
        _ = self;
        var curr = ref;
        while ((std.mem.eql(u8, curr.kind, "NON_NULL") or std.mem.eql(u8, curr.kind, "LIST")) and curr.ofType != null) {
            curr = curr.ofType.?.*;
        }
        return curr;
    }

    /// Number of LIST wrappers around the named leaf.
    fn listDepth(self: *Emitter, ref: intro.TypeRef) usize {
        _ = self;
        var depth: usize = 0;
        var curr = ref;
        while (curr.ofType) |inner| {
            if (std.mem.eql(u8, curr.kind, "LIST")) depth += 1;
            curr = inner.*;
        }
        return depth;
    }

    /// True when `ref` is the bare `ID` scalar (optionally NON_NULL/LIST
    /// wrapped).
    fn isBareId(self: *Emitter, ref: intro.TypeRef) bool {
        const inner = self.unwrapAll(ref);
        return std.mem.eql(u8, inner.kind, "SCALAR") and
            inner.name != null and std.mem.eql(u8, inner.name.?, "ID");
    }

    /// If `ref` resolves to an ID (or list of IDs) carrying an
    /// `@expectedType(name:)` directive, return the referenced object type.
    fn expectedObjectType(self: *Emitter, ref: intro.TypeRef, directives: intro.DirectiveList) ?[]const u8 {
        _ = self;
        const inner = unwrapAllStatic(ref);
        const is_id = std.mem.eql(u8, inner.kind, "SCALAR") and
            inner.name != null and std.mem.eql(u8, inner.name.?, "ID");
        if (!is_id) return null;
        const d = intro.findDirective(directives, "expectedType") orelse return null;
        return d.argValue("name");
    }

    /// For `[ID!]!` + @expectedType refs, the object type name; else null.
    fn listInnerObjectType(self: *Emitter, ref: intro.TypeRef, directives: intro.DirectiveList) ?[]const u8 {
        if (self.expectedObjectType(ref, directives) == null) return null;
        return if (self.listDepth(ref) > 0) self.expectedObjectType(ref, directives) else null;
    }

    fn unwrapAllStatic(ref: intro.TypeRef) intro.TypeRef {
        var curr = ref;
        while ((std.mem.eql(u8, curr.kind, "NON_NULL") or std.mem.eql(u8, curr.kind, "LIST")) and curr.ofType != null) {
            curr = curr.ofType.?.*;
        }
        return curr;
    }

    // ── Zig type mapping ────────────────────────────────────────────────────

    const TypeCtx = enum { arg, ret, input };

    /// Map a TypeRef to a Zig type expression. `.arg`/`.input` produce
    /// const-friendly forms; `.ret` produces owned-return forms. For `ID` args
    /// this maps the *wire* type (`[]const u8`); callers must run
    /// `expectedObjectType` first to substitute object params.
    fn toZigType(self: *Emitter, ref: intro.TypeRef, ctx: TypeCtx) ![]const u8 {
        return self.toZigTypeInner(ref, ctx, true);
    }

    fn toZigTypeInner(self: *Emitter, ref: intro.TypeRef, ctx: TypeCtx, top: bool) error{OutOfMemory}![]const u8 {
        if (std.mem.eql(u8, ref.kind, "NON_NULL")) {
            return self.toZigTypeInner(ref.ofType.?.*, ctx, false);
        }
        var base: []const u8 = undefined;
        if (std.mem.eql(u8, ref.kind, "LIST")) {
            const inner = try self.toZigTypeInner(ref.ofType.?.*, ctx, true);
            defer self.allocator.free(inner);
            base = try std.fmt.allocPrint(self.allocator, "[]const {s}", .{inner});
        } else if (ref.name) |n| {
            if (std.mem.eql(u8, n, "String")) {
                base = try self.allocator.dupe(u8, if (ctx == .ret) "[]u8" else "[]const u8");
            } else if (std.mem.eql(u8, n, "Int")) {
                base = try self.allocator.dupe(u8, "i64");
            } else if (std.mem.eql(u8, n, "Float")) {
                base = try self.allocator.dupe(u8, "f64");
            } else if (std.mem.eql(u8, n, "Boolean")) {
                base = try self.allocator.dupe(u8, "bool");
            } else if (std.mem.eql(u8, n, "Void")) {
                base = try self.allocator.dupe(u8, "void");
            } else if (std.mem.eql(u8, n, "DateTime")) {
                base = try self.allocator.dupe(u8, if (ctx == .ret) "[]u8" else "[]const u8");
            } else if (std.mem.eql(u8, n, "ID")) {
                base = try self.allocator.dupe(u8, if (ctx == .ret) "[]u8" else "[]const u8");
            } else if (self.object_names.contains(n)) {
                base = try self.allocator.dupe(u8, n);
            } else if (self.enum_names.contains(n)) {
                base = try self.allocator.dupe(u8, n);
            } else {
                base = try self.allocator.dupe(u8, n); // custom scalars, inputs
            }
        } else {
            base = try self.allocator.dupe(u8, "anyopaque");
        }
        if (top and !std.mem.eql(u8, ref.kind, "NON_NULL")) {
            defer self.allocator.free(base);
            return std.fmt.allocPrint(self.allocator, "?{s}", .{base});
        }
        return base;
    }

    /// The *parameter* type for an arg: when `ID @expectedType(X)` the param is
    /// the object `X` (not the wire `[]const u8`).
    fn argParamType(self: *Emitter, a: intro.InputValue, wire_type: []const u8) ![]const u8 {
        if (self.expectedObjectType(a.type, a.directives)) |obj| {
            if (self.listDepth(a.type) > 0) {
                return std.fmt.allocPrint(self.allocator, "[]const {s}", .{obj});
            }
            return self.allocator.dupe(u8, obj);
        }
        return self.allocator.dupe(u8, wire_type);
    }

    // ── naming ──────────────────────────────────────────────────────────────

    /// camelCase a GraphQL name; `@"kw"` for Zig keywords.
    fn camelCase(self: *Emitter, s: []const u8) ![]const u8 {
        if (s.len == 0) return "";
        var result: std.ArrayList(u8) = .empty;
        errdefer result.deinit(self.allocator);
        var next_upper = false;
        var all_upper = true;
        for (s) |c| {
            if (std.ascii.isLower(c)) {
                all_upper = false;
                break;
            }
        }
        for (s, 0..) |c, i| {
            if (c == '_') {
                next_upper = true;
                continue;
            }
            if (next_upper) {
                try result.append(self.allocator, std.ascii.toUpper(c));
                next_upper = false;
            } else if (i == 0) {
                try result.append(self.allocator, std.ascii.toLower(c));
            } else {
                try result.append(self.allocator, if (all_upper) std.ascii.toLower(c) else c);
            }
        }
        const name = try result.toOwnedSlice(self.allocator);
        if (isKeyword(name)) {
            defer self.allocator.free(name);
            return std.fmt.allocPrint(self.allocator, "@\"{s}\"", .{name});
        }
        return name;
    }

    /// Zig-safe identifier for input-object field names (kept wire-identical;
    /// only keyword-quoted when needed).
    fn zigIdent(self: *Emitter, s: []const u8) ![]const u8 {
        if (isKeyword(s)) {
            return std.fmt.allocPrint(self.allocator, "@\"{s}\"", .{s});
        }
        return self.allocator.dupe(u8, s);
    }

    /// Identifier for a method arg — disambiguated against `self`, `options`,
    /// `Self`, the struct's own field names, sibling method names, and
    /// previously emitted arg names.
    fn argIdent(self: *Emitter, name: []const u8, taken: []const []const u8, siblings: []const []const u8) ![]const u8 {
        var id = try self.camelCase(name);
        // `@"kw"` forms print fine as params; literal collisions get `_arg`.
        const bare = if (std.mem.startsWith(u8, id, "@\""))
            id[2 .. id.len - 1]
        else
            id;
        const reserved = [_][]const u8{ "self", "options", "Self", "s", "allocator", "arena", "selection", "gql" };
        for (reserved) |r| {
            if (std.mem.eql(u8, bare, r)) {
                const renamed = try std.fmt.allocPrint(self.allocator, "{s}_arg", .{bare});
                self.allocator.free(id);
                return renamed;
            }
        }
        for (siblings) |t| {
            if (std.mem.eql(u8, bare, t)) {
                const renamed = try std.fmt.allocPrint(self.allocator, "{s}_arg", .{bare});
                self.allocator.free(id);
                return renamed;
            }
        }
        for (taken) |t| {
            if (std.mem.eql(u8, id, t)) {
                const renamed = try std.fmt.allocPrint(self.allocator, "{s}_arg", .{bare});
                self.allocator.free(id);
                return renamed;
            }
        }
        return id;
    }

    // ── writers ─────────────────────────────────────────────────────────────

    fn print(self: *Emitter, comptime fmt: []const u8, args: anytype) !void {
        const str = try std.fmt.allocPrint(self.allocator, fmt, args);
        defer self.allocator.free(str);
        try self.out.appendSlice(self.allocator, str);
    }

    fn writeAll(self: *Emitter, bytes: []const u8) !void {
        try self.out.appendSlice(self.allocator, bytes);
    }

    fn writeDoc(self: *Emitter, description: ?[]const u8) !void {
        try self.writeDocIndented(description, "");
    }

    fn writeDocIndented(self: *Emitter, description: ?[]const u8, indent: []const u8) !void {
        const d = description orelse return;
        if (d.len == 0) return;
        var it = std.mem.splitSequence(u8, d, "\n");
        while (it.next()) |line| {
            try self.print("{s}/// {s}\n", .{ indent, line });
        }
    }
};

/// Strip `@"..."` quoting for use as a temp-variable component.
fn bareIdent(id: []const u8) []const u8 {
    if (std.mem.startsWith(u8, id, "@\"") and id.len > 3) return id[2 .. id.len - 1];
    return id;
}

fn fieldLessThan(_: void, a: intro.Field, b: intro.Field) bool {
    return std.mem.lessThan(u8, a.name, b.name);
}

fn inputValueLessThan(_: void, a: intro.InputValue, b: intro.InputValue) bool {
    return std.mem.lessThan(u8, a.name, b.name);
}

fn isKeyword(name: []const u8) bool {
    const keywords = [_][]const u8{
        "addrspace", "align",       "and",     "asm",    "async",       "await",          "break",     "catch",    "comptime",
        "const",     "continue",    "defer",   "else",   "enum",        "errdefer",       "error",     "export",   "extern",
        "fn",        "for",         "if",      "inline", "noalias",     "noinline",       "nosuspend", "opaque",   "or",
        "orelse",    "packed",      "pub",     "resume", "return",      "linksection",    "struct",    "suspend",  "switch",
        "test",      "threadlocal", "try",     "union",  "unreachable", "usingnamespace", "var",       "volatile", "while",
        "type",      "anyframe",    "anytype",
    };
    for (keywords) |kw| {
        if (std.mem.eql(u8, name, kw)) return true;
    }
    return false;
}

// ─────────────────────────── tests ──────────────────────────────────────────

const testing = std.testing;

fn scalar(comptime name: []const u8) intro.TypeRef {
    return .{ .kind = "SCALAR", .name = name };
}
fn nonNull(inner: *const intro.TypeRef) intro.TypeRef {
    return .{ .kind = "NON_NULL", .ofType = @constCast(inner) };
}
fn list(inner: *const intro.TypeRef) intro.TypeRef {
    return .{ .kind = "LIST", .ofType = @constCast(inner) };
}

test "emitter produces prelude + helpers" {
    var e = Emitter.init(testing.allocator);
    defer e.deinit();

    const empty: intro.Schema = .{ .types = &.{} };
    try e.emitAll(empty);

    const src = e.source();
    try testing.expect(std.mem.indexOf(u8, src, "querybuilder.zig") != null);
    try testing.expect(std.mem.indexOf(u8, src, "fn executeLeaf") != null);
    try testing.expect(std.mem.indexOf(u8, src, "fn loadNode") != null);
}

test "emit object with scalar and chainable fields" {
    var e = Emitter.init(testing.allocator);
    defer e.deinit();

    const str_nn = nonNull(&scalar("String"));
    const obj_foo = nonNull(&.{ .kind = "OBJECT", .name = "Foo" });
    const schema: intro.Schema = .{ .types = &.{
        .{
            .kind = "OBJECT",
            .name = "Foo",
            .fields = &.{
                .{ .name = "name", .type = str_nn },
                .{ .name = "child", .type = obj_foo },
            },
        },
    } };

    try e.emitAll(schema);
    const src = e.source();
    try testing.expect(std.mem.indexOf(u8, src, "pub const Foo = struct") != null);
    try testing.expect(std.mem.indexOf(u8, src, "pub const FooID = struct") != null);
    try testing.expect(std.mem.indexOf(u8, src, "pub fn name(") != null);
    try testing.expect(std.mem.indexOf(u8, src, "pub fn child(") != null);
}

test "emit enum with toWire/fromString" {
    var e = Emitter.init(testing.allocator);
    defer e.deinit();

    const schema: intro.Schema = .{ .types = &.{
        .{
            .kind = "ENUM",
            .name = "ShareMode",
            .enumValues = &.{
                .{ .name = "SHARED" },
                .{ .name = "PRIVATE" },
            },
        },
    } };

    try e.emitAll(schema);
    const src = e.source();
    try testing.expect(std.mem.indexOf(u8, src, "pub const ShareMode = enum") != null);
    try testing.expect(std.mem.indexOf(u8, src, ".shared => \"SHARED\"") != null);
    try testing.expect(std.mem.indexOf(u8, src, "return .private") != null);
}

test "emit input object with optional field" {
    var e = Emitter.init(testing.allocator);
    defer e.deinit();

    const schema: intro.Schema = .{ .types = &.{
        .{
            .kind = "INPUT_OBJECT",
            .name = "BuildArg",
            .inputFields = &.{
                .{ .name = "name", .type = nonNull(&scalar("String")) },
                .{ .name = "value", .type = nonNull(&scalar("String")) },
            },
        },
    } };

    try e.emitAll(schema);
    const src = e.source();
    try testing.expect(std.mem.indexOf(u8, src, "pub const BuildArg = struct") != null);
    try testing.expect(std.mem.indexOf(u8, src, "name: []const u8") != null);
}

test "sync-style field emits node-load reconstruction" {
    var e = Emitter.init(testing.allocator);
    defer e.deinit();

    const id_nn = nonNull(&scalar("ID"));
    const schema: intro.Schema = .{ .types = &.{
        .{
            .kind = "OBJECT",
            .name = "Container",
            .fields = &.{
                .{
                    .name = "sync",
                    .type = id_nn,
                    .directives = &.{
                        .{ .name = "expectedType", .args = &.{.{ .name = "name", .value = "\"Container\"" }} },
                    },
                },
            },
        },
    } };

    try e.emitAll(schema);
    const src = e.source();
    try testing.expect(std.mem.indexOf(u8, src, "pub fn sync(self: Container) !Container") != null);
    try testing.expect(std.mem.indexOf(u8, src, "loadNode(Container") != null);
}

test "id field emits parent ID wrapper" {
    var e = Emitter.init(testing.allocator);
    defer e.deinit();

    const schema: intro.Schema = .{ .types = &.{
        .{
            .kind = "OBJECT",
            .name = "File",
            .fields = &.{.{ .name = "id", .type = nonNull(&scalar("ID")) }},
        },
    } };

    try e.emitAll(schema);
    const src = e.source();
    try testing.expect(std.mem.indexOf(u8, src, "pub fn id(self: File) !FileID") != null);
}
