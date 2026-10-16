//! Compatibility layer for Zig 0.16 and 0.17 comptime type reflection.
//!
//! Handles Structure-of-Arrays (SOA) @typeInfo changes introduced in Zig 0.17:
//! - Struct/Union: field_names/field_types/field_attrs vs fields; decl_names vs decls
//! - Enum: field_names/field_values vs fields
//! - Fn: param_types/param_attrs vs params
//! - Pointer: attrs.@"const" vs is_const
//! - Tuple: @Tuple vs std.meta.Tuple
//! - std.meta.declarations: strings vs declarations with .name

const std = @import("std");

/// Uniform struct field representation across Zig 0.16 and 0.17.
pub const StructField = struct {
    name: [:0]const u8,
    type: type,
    default_value_ptr: ?*const anyopaque = null,
};

/// Get uniform struct field descriptors across Zig 0.16 and 0.17.
pub fn structFields(comptime T: type) []const StructField {
    const info = @typeInfo(T).@"struct";
    if (@hasField(@TypeOf(info), "fields")) {
        // Zig 0.16 AOS representation
        const count = info.fields.len;
        var result: [count]StructField = undefined;
        inline for (info.fields, 0..) |f, i| {
            result[i] = .{
                .name = f.name,
                .type = f.type,
                .default_value_ptr = f.default_value_ptr,
            };
        }
        const final = result;
        return &final;
    } else {
        // Zig 0.17 SOA representation
        const count = info.field_names.len;
        var result: [count]StructField = undefined;
        inline for (info.field_names, info.field_types, info.field_attrs, 0..) |fname, ftype, fattr, i| {
            result[i] = .{
                .name = fname,
                .type = ftype,
                .default_value_ptr = fattr.default_value_ptr,
            };
        }
        const final = result;
        return &final;
    }
}

/// Get struct field names across Zig 0.16 and 0.17.
pub fn structFieldNames(comptime T: type) []const [:0]const u8 {
    const info = @typeInfo(T).@"struct";
    if (@hasField(@TypeOf(info), "fields")) {
        const count = info.fields.len;
        var result: [count][:0]const u8 = undefined;
        inline for (info.fields, 0..) |f, i| {
            result[i] = f.name;
        }
        const final = result;
        return &final;
    } else {
        return info.field_names;
    }
}

/// Get enum field names across Zig 0.16 and 0.17.
pub fn enumFieldNames(comptime T: type) []const [:0]const u8 {
    const info = @typeInfo(T).@"enum";
    if (@hasField(@TypeOf(info), "fields")) {
        const count = info.fields.len;
        var result: [count][:0]const u8 = undefined;
        inline for (info.fields, 0..) |f, i| {
            result[i] = f.name;
        }
        const final = result;
        return &final;
    } else {
        return info.field_names;
    }
}

/// Get declaration names of a struct across Zig 0.16 and 0.17.
pub fn structDeclNames(comptime T: type) []const [:0]const u8 {
    const info = @typeInfo(T).@"struct";
    if (@hasField(@TypeOf(info), "decls")) {
        const count = info.decls.len;
        var result: [count][:0]const u8 = undefined;
        inline for (info.decls, 0..) |d, i| {
            result[i] = d.name;
        }
        const final = result;
        return &final;
    } else {
        return info.decl_names;
    }
}

/// Extract declaration name from an item produced by `std.meta.declarations(T)`.
/// In Zig 0.16, `d` is `Declaration` with `.name`.
/// In Zig 0.17, `d` is `[:0]const u8` (the name string directly).
pub inline fn declItemName(comptime d: anytype) [:0]const u8 {
    return comptime if (@hasField(@TypeOf(d), "name")) d.name else d;
}

/// Check if pointer is const across Zig 0.16 and 0.17.
pub inline fn ptrIsConst(comptime ptr: std.builtin.Type.Pointer) bool {
    if (@hasField(@TypeOf(ptr), "is_const")) {
        return ptr.is_const;
    } else {
        return ptr.attrs.@"const";
    }
}

/// Number of parameters for a function type info.
pub inline fn fnParamCount(comptime fn_info: anytype) usize {
    if (@hasField(@TypeOf(fn_info), "params")) {
        return fn_info.params.len;
    } else {
        return fn_info.param_types.len;
    }
}

/// Parameter type at index for a function type info.
pub inline fn fnParamType(comptime fn_info: anytype, comptime idx: usize) ?type {
    if (@hasField(@TypeOf(fn_info), "params")) {
        return fn_info.params[idx].type;
    } else {
        return fn_info.param_types[idx];
    }
}

/// Create a tuple type from a slice of types across Zig 0.16 and 0.17.
pub fn Tuple(comptime types: []const type) type {
    if (@hasDecl(std.meta, "Tuple")) {
        return std.meta.Tuple(types);
    } else {
        return @Tuple(types);
    }
}
