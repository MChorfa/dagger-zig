//! Stub schema validator for the CI module.
//!
//! The full schema validator lived in `full_main.zig` which was removed.
//! This stub provides the same interface so the CI module compiles and
//! runs; the validation logic can be re-added when needed.

const std = @import("std");
const dagger = @import("dagger_sdk");

pub const SchemaValidator = struct {
    pub fn validate(self: SchemaValidator, ctx: *dagger.Context) !dagger.File {
        _ = self;
        var dir = try ctx.directory();
        return try dir.withNewFile(
            "schema-validation.md",
            "# Schema Validation\n\nStatus: stub (validator not yet implemented)\n",
        );
    }

    pub fn conformance(self: SchemaValidator, ctx: *dagger.Context, category: []const u8) !dagger.File {
        _ = self;
        const buf = try std.fmt.allocPrint(ctx.arena, "# Conformance: {s}\n\nStatus: stub (validator not yet implemented)\n", .{category});
        var dir = try ctx.directory();
        return try dir.withNewFile("conformance.md", buf);
    }
};
