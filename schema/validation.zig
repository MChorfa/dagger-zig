//! Dagger API Schema Validation
//!
//! Validates dagger-zig SDK conformance against the official Dagger GraphQL API.
//! This module provides schema validation, type checking, and conformance vectors
//! to ensure the SDK correctly implements the Dagger API contract.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Schema validation errors
pub const ValidationError = error{
    MissingType,
    MissingField,
    TypeMismatch,
    ReturnTypeMismatch,
    ArgumentMismatch,
    InvalidScalar,
    InvalidEnum,
    InvalidUnion,
    InvalidInterface,
    CircularReference,
    OutOfMemory,
};

/// Dagger GraphQL type kinds
pub const TypeKind = enum {
    scalar,
    object,
    interface,
    @"union",
    enum_type,
    input_object,
    list,
    non_null,
};

/// Field definition in schema
pub const FieldDef = struct {
    name: []const u8,
    return_type: []const u8,
    is_optional: bool,
    args: []const ArgDef = &.{},
    description: ?[]const u8 = null,
    deprecated: ?[]const u8 = null,
};

/// Argument definition
pub const ArgDef = struct {
    name: []const u8,
    type_name: []const u8,
    is_optional: bool,
    default_value: ?[]const u8 = null,
};

/// Type definition in schema
pub const TypeDef = struct {
    name: []const u8,
    kind: TypeKind,
    fields: []const FieldDef = &.{},
    enum_values: []const []const u8 = &.{},
    description: ?[]const u8 = null,

    /// Check if type has a specific field
    pub fn hasField(self: TypeDef, field_name: []const u8) bool {
        for (self.fields) |field| {
            if (std.mem.eql(u8, field.name, field_name)) return true;
        }
        return false;
    }

    /// Get field definition
    pub fn getField(self: TypeDef, field_name: []const u8) ?FieldDef {
        for (self.fields) |field| {
            if (std.mem.eql(u8, field.name, field_name)) return field;
        }
        return null;
    }
};

/// Schema validator state
pub const SchemaValidator = struct {
    allocator: Allocator,
    types: std.StringHashMap(TypeDef),
    queries: std.StringHashMap(FieldDef),
    mutations: std.StringHashMap(FieldDef),

    pub fn init(allocator: Allocator) SchemaValidator {
        return .{
            .allocator = allocator,
            .types = std.StringHashMap(TypeDef).init(allocator),
            .queries = std.StringHashMap(FieldDef).init(allocator),
            .mutations = std.StringHashMap(FieldDef).init(allocator),
        };
    }

    pub fn deinit(self: *SchemaValidator) void {
        self.types.deinit();
        self.queries.deinit();
        self.mutations.deinit();
    }

    /// Register a type definition
    pub fn registerType(self: *SchemaValidator, def: TypeDef) !void {
        try self.types.put(def.name, def);
    }

    /// Register a query field
    pub fn registerQuery(self: *SchemaValidator, def: FieldDef) !void {
        try self.queries.put(def.name, def);
    }

    /// Validate SDK type against schema
    pub fn validateType(self: *SchemaValidator, zig_type_name: []const u8, schema_type_name: []const u8) ValidationError!void {
        const schema_type = self.types.get(schema_type_name) orelse {
            std.log.err("Schema missing type: {s}", .{schema_type_name});
            return ValidationError.MissingType;
        };

        // TODO: Map zig type name to schema type and verify compatibility
        _ = zig_type_name;
        _ = schema_type;
    }

    /// Validate SDK function against schema field
    pub fn validateField(self: *SchemaValidator, type_name: []const u8, field_name: []const u8, zig_return_type: []const u8) ValidationError!void {
        const schema_type = self.types.get(type_name) orelse {
            std.log.err("Schema missing type: {s}", .{type_name});
            return ValidationError.MissingType;
        };

        const field = schema_type.getField(field_name) orelse {
            std.log.err("Type {s} missing field: {s}", .{ type_name, field_name });
            return ValidationError.MissingField;
        };

        // Validate return type compatibility
        if (!isTypeCompatible(zig_return_type, field.return_type)) {
            std.log.err("Return type mismatch for {s}.{s}: expected {s}, got {s}", .{ type_name, field_name, field.return_type, zig_return_type });
            return ValidationError.ReturnTypeMismatch;
        }
    }

    /// Generate conformance report
    pub fn generateReport(self: *SchemaValidator, writer: anytype) !void {
        try writer.print("Dagger API Schema Conformance Report\n", .{});
        try writer.print("====================================\n\n", .{});

        try writer.print("Registered Types: {d}\n", .{self.types.count()});
        try writer.print("Registered Queries: {d}\n", .{self.queries.count()});
        try writer.print("Registered Mutations: {d}\n\n", .{self.mutations.count()});

        var type_iter = self.types.iterator();
        try writer.print("Types:\n", .{});
        while (type_iter.next()) |entry| {
            try writer.print("  - {s} ({s})\n", .{ entry.key_ptr.*, @tagName(entry.value_ptr.kind) });
        }
    }
};

/// Check if two types are compatible
fn isTypeCompatible(zig_type: []const u8, schema_type: []const u8) bool {
    // Direct match
    if (std.mem.eql(u8, zig_type, schema_type)) return true;

    // Common type mappings
    const mappings = .{
        .{ "Container", "Container" },
        .{ "Directory", "Directory" },
        .{ "File", "File" },
        .{ "Secret", "Secret" },
        .{ "Service", "Service" },
        .{ "CacheVolume", "CacheVolume" },
        .{ "Socket", "Socket" },
        .{ "Port", "Port" },
        .{ "EnvVariable", "EnvVariable" },
        .{ "Platform", "Platform" },
    };

    for (mappings) |mapping| {
        if (std.mem.eql(u8, zig_type, mapping[0]) and
            std.mem.eql(u8, schema_type, mapping[1]))
        {
            return true;
        }
    }

    // ID type suffix handling
    if (std.mem.endsWith(u8, zig_type, "ID") and
        std.mem.endsWith(u8, schema_type, "ID"))
    {
        return true;
    }

    return false;
}

/// Load Dagger core API schema
pub fn loadCoreSchema(allocator: Allocator) !SchemaValidator {
    var validator = SchemaValidator.init(allocator);
    errdefer validator.deinit();

    // Register core Dagger types
    try validator.registerType(.{
        .name = "Container",
        .kind = .object,
        .description = "An OCI-compatible container",
    });

    try validator.registerType(.{
        .name = "Directory",
        .kind = .object,
        .description = "A directory",
    });

    try validator.registerType(.{
        .name = "File",
        .kind = .object,
        .description = "A file",
    });

    try validator.registerType(.{
        .name = "Secret",
        .kind = .object,
        .description = "A secret value",
    });

    try validator.registerType(.{
        .name = "Service",
        .kind = .object,
        .description = "A TCP service",
    });

    try validator.registerType(.{
        .name = "CacheVolume",
        .kind = .object,
        .description = "A cache volume",
    });

    try validator.registerType(.{
        .name = "Socket",
        .kind = .object,
        .description = "A Unix or TCP socket",
    });

    try validator.registerType(.{
        .name = "Platform",
        .kind = .scalar,
        .description = "Platform configuration",
    });

    // Register query fields
    try validator.registerQuery(.{
        .name = "container",
        .return_type = "Container",
        .is_optional = false,
    });

    try validator.registerQuery(.{
        .name = "directory",
        .return_type = "Directory",
        .is_optional = false,
    });

    try validator.registerQuery(.{
        .name = "file",
        .return_type = "File",
        .is_optional = false,
    });

    try validator.registerQuery(.{
        .name = "secret",
        .return_type = "Secret",
        .is_optional = false,
    });

    try validator.registerQuery(.{
        .name = "git",
        .return_type = "GitRepository",
        .is_optional = false,
    });

    try validator.registerQuery(.{
        .name = "http",
        .return_type = "File",
        .is_optional = false,
    });

    try validator.registerQuery(.{
        .name = "defaultPlatform",
        .return_type = "Platform",
        .is_optional = false,
    });

    return validator;
}
