//! GraphQL introspection query + response schema.
//!
//! Sent to the Dagger engine once at codegen time; the result is a complete
//! description of every type, field, arg, and enum in the engine's API.
//! We then walk that description and emit Zig code.
//!
//! The query mirrors dagql's own introspection (dagql/introspection/query.graphql),
//! including the nonstandard `directives` applications on types, fields, and
//! input values — Dagger uses `@expectedType` to mark which object type an `ID`
//! value refers to, which the emitter needs for typed ID arguments and
//! node-loading return values.
//!
//! `parse` accepts three body shapes:
//!   - `{"data":{"__schema":{...}}}`   — raw GraphQL envelope (live query)
//!   - `{"__schema":{...}}`            — unwrapped envelope
//!   - `{"queryType":..,"types":[..]}` — bare schema object (e.g. the upstream
//!     `cmd/codegen/introspection/testdata/schema.json` fixture)

const std = @import("std");

pub const query =
    \\query IntrospectionQuery {
    \\  __schemaVersion
    \\  __schema {
    \\    queryType { name }
    \\    mutationType { name }
    \\    subscriptionType { name }
    \\    types {
    \\      ...FullType
    \\    }
    \\    directives {
    \\      name
    \\      description
    \\      locations
    \\      args(includeDeprecated: true) {
    \\        ...InputValue
    \\      }
    \\    }
    \\  }
    \\}
    \\fragment FullType on __Type {
    \\  kind
    \\  name
    \\  description
    \\  fields(includeDeprecated: true) {
    \\    name
    \\    description
    \\    args(includeDeprecated: true) {
    \\      ...InputValue
    \\    }
    \\    type {
    \\      ...TypeRef
    \\    }
    \\    isDeprecated
    \\    deprecationReason
    \\    directives {
    \\      ...DirectiveApplication
    \\    }
    \\  }
    \\  inputFields(includeDeprecated: true) {
    \\    ...InputValue
    \\  }
    \\  interfaces {
    \\    ...TypeRef
    \\  }
    \\  enumValues(includeDeprecated: true) {
    \\    name
    \\    description
    \\    isDeprecated
    \\    deprecationReason
    \\    directives {
    \\      ...DirectiveApplication
    \\    }
    \\  }
    \\  possibleTypes {
    \\    ...TypeRef
    \\  }
    \\  directives {
    \\    ...DirectiveApplication
    \\  }
    \\}
    \\fragment InputValue on __InputValue {
    \\  name
    \\  description
    \\  type { ...TypeRef }
    \\  defaultValue
    \\  isDeprecated
    \\  deprecationReason
    \\  directives {
    \\    ...DirectiveApplication
    \\  }
    \\}
    \\fragment TypeRef on __Type {
    \\  kind
    \\  name
    \\  ofType {
    \\    kind
    \\    name
    \\    ofType {
    \\      kind
    \\      name
    \\      ofType {
    \\        kind
    \\        name
    \\        ofType {
    \\          kind
    \\          name
    \\          ofType {
    \\            kind
    \\            name
    \\            ofType {
    \\              kind
    \\              name
    \\              ofType {
    \\                kind
    \\                name
    \\              }
    \\            }
    \\          }
    \\        }
    \\      }
    \\    }
    \\  }
    \\}
    \\fragment DirectiveApplication on _DirectiveApplication {
    \\  name
    \\  args {
    \\    name
    \\    value
    \\  }
    \\}
;

/// An applied schema directive, e.g. `@expectedType(name: "Container")`.
pub const DirectiveArg = struct {
    name: []const u8,
    value: ?[]const u8 = null,
};

pub const DirectiveApplication = struct {
    name: []const u8,
    args: []const DirectiveArg = &.{},

    /// Fetch the `value` of the named argument, unquoting the SDL literal
    /// (values arrive as `"\"Container\""` — the inner quotes are part of the
    /// wire encoding).
    pub fn argValue(self: DirectiveApplication, arg_name: []const u8) ?[]const u8 {
        for (self.args) |a| {
            if (std.mem.eql(u8, a.name, arg_name)) {
                const v = a.value orelse return null;
                return std.mem.trim(u8, v, "\"");
            }
        }
        return null;
    }
};

pub const DirectiveList = []const DirectiveApplication;

/// Find an applied directive by name.
pub fn findDirective(directives: DirectiveList, name: []const u8) ?DirectiveApplication {
    for (directives) |d| {
        if (std.mem.eql(u8, d.name, name)) return d;
    }
    return null;
}

/// A type reference in the schema. `kind` tells you what `name`/`ofType` mean:
///   - SCALAR, OBJECT, ENUM, INPUT_OBJECT: `name` is set, `ofType` is null
///   - NON_NULL, LIST: `name` is null, `ofType` holds the wrapped type
pub const TypeRef = struct {
    kind: []const u8,
    name: ?[]const u8 = null,
    ofType: ?*TypeRef = null,
};

pub const InputValue = struct {
    name: []const u8,
    description: ?[]const u8 = null,
    type: TypeRef,
    defaultValue: ?[]const u8 = null,
    isDeprecated: bool = false,
    deprecationReason: ?[]const u8 = null,
    directives: DirectiveList = &.{},

    /// Optional per the engine contract: nullable type OR a declared default.
    pub fn isOptional(self: InputValue) bool {
        return self.defaultValue != null or
            !std.mem.eql(u8, self.type.kind, "NON_NULL");
    }
};

pub const Field = struct {
    name: []const u8,
    description: ?[]const u8 = null,
    args: []const InputValue = &.{},
    type: TypeRef,
    isDeprecated: bool = false,
    deprecationReason: ?[]const u8 = null,
    directives: DirectiveList = &.{},
};

pub const EnumValue = struct {
    name: []const u8,
    description: ?[]const u8 = null,
    isDeprecated: bool = false,
    deprecationReason: ?[]const u8 = null,
    directives: DirectiveList = &.{},
};

pub const FullType = struct {
    kind: []const u8,
    name: ?[]const u8 = null,
    description: ?[]const u8 = null,
    fields: ?[]const Field = null,
    inputFields: ?[]const InputValue = null,
    enumValues: ?[]const EnumValue = null,
    interfaces: ?[]const TypeRef = null,
    possibleTypes: ?[]const TypeRef = null,
    directives: DirectiveList = &.{},
};

pub const Schema = struct {
    queryType: ?struct { name: []const u8 } = null,
    types: []const FullType,
};

pub fn parse(allocator: std.mem.Allocator, body: []const u8) !std.json.Parsed(Schema) {
    // Shape 1: full GraphQL envelope {"data":{"__schema":{...}}}.
    {
        const Outer = struct { data: struct { __schema: Schema } };
        if (std.json.parseFromSlice(Outer, allocator, body, .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_always,
        })) |p| {
            return .{ .arena = p.arena, .value = p.value.data.__schema };
        } else |_| {}
    }
    // Shape 2: {"__schema":{...}}.
    {
        const Outer = struct { __schema: Schema };
        if (std.json.parseFromSlice(Outer, allocator, body, .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_always,
        })) |p| {
            return .{ .arena = p.arena, .value = p.value.__schema };
        } else |_| {}
    }
    // Shape 3: bare schema object {"queryType":..,"types":[..]}.
    return std.json.parseFromSlice(Schema, allocator, body, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
}

// ─────────────────────────── tests ──────────────────────────────────────────

const testing = std.testing;

test "parse bare schema object (schema.json fixture shape)" {
    const body =
        \\{"queryType":{"name":"Query"},"types":[{"kind":"OBJECT","name":"Container","fields":[{"name":"id","type":{"kind":"NON_NULL","ofType":{"kind":"SCALAR","name":"ID"}}}]}]}
    ;
    const p = try parse(testing.allocator, body);
    defer p.deinit();
    try testing.expectEqual(@as(usize, 1), p.value.types.len);
    try testing.expectEqualStrings("Container", p.value.types[0].name.?);
    const f = p.value.types[0].fields.?[0];
    try testing.expectEqualStrings("NON_NULL", f.type.kind);
    try testing.expectEqualStrings("ID", f.type.ofType.?.name.?);
}

test "parse envelope shape {data:{__schema:{...}}}" {
    const body =
        \\{"data":{"__schema":{"types":[{"kind":"SCALAR","name":"JSON"}]}}}
    ;
    const p = try parse(testing.allocator, body);
    defer p.deinit();
    try testing.expectEqualStrings("JSON", p.value.types[0].name.?);
}

test "field directives parse with expectedType arg" {
    const body =
        \\{"types":[{"kind":"OBJECT","name":"Container","fields":[{"name":"sync","type":{"kind":"NON_NULL","ofType":{"kind":"SCALAR","name":"ID"}},"directives":[{"name":"expectedType","args":[{"name":"name","value":"\"Container\""}]}]}]}]}
    ;
    const p = try parse(testing.allocator, body);
    defer p.deinit();
    const f = p.value.types[0].fields.?[0];
    const d = findDirective(f.directives, "expectedType").?;
    try testing.expectEqualStrings("Container", d.argValue("name").?);
}
