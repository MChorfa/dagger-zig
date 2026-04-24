//! Schema Validator - Dagger Module
//!
//! This module provides schema validation and conformance testing
//! for the dagger-zig SDK against the official Dagger GraphQL API.

const std = @import("std");
const dagger = @import("dagger_sdk");
const validation = @import("validation.zig");
const conformance = @import("conformance.zig");

pub const SchemaValidator = struct {
    /// Run full schema validation
    pub fn validate(
        self: *const SchemaValidator,
        ctx: *dagger.Context,
    ) !dagger.File {
        _ = self;
        
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        const allocator = gpa.allocator();
        
        // Run validation
        var validator = try validation.loadCoreSchema(allocator);
        defer validator.deinit();
        
        // Generate report
        var report = std.ArrayList(u8).init(allocator);
        defer report.deinit();
        const writer = report.writer();
        
        try writer.print("# Dagger API Schema Validation Report\n\n", .{});
        try validator.generateReport(writer);
        
        // Write to file
        return try ctx.directory().withNewFile("schema-report.md", report.items);
    }
    
    /// Run conformance tests
    pub fn conformance(
        self: *const SchemaValidator,
        ctx: *dagger.Context,
        category: ?[]const u8,
    ) !dagger.File {
        _ = self;
        
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        const allocator = gpa.allocator();
        
        var runner = conformance.ConformanceRunner.init(allocator);
        defer runner.deinit();
        
        // Parse category if provided
        const cat = if (category) |c| parseCategory(c) else null;
        
        if (cat) |c| {
            try runner.runCategory(c);
        } else {
            try runner.runAll();
        }
        
        // Generate report
        var report = std.ArrayList(u8).init(allocator);
        defer report.deinit();
        
        try runner.generateReport(report.writer());
        
        return try ctx.directory().withNewFile("conformance-report.md", report.items);
    }
    
    /// Validate specific SDK type against schema
    pub fn validateType(
        self: *const SchemaValidator,
        ctx: *dagger.Context,
        zig_type_name: []const u8,
        schema_type_name: []const u8,
    ) !dagger.File {
        _ = self;
        
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        const allocator = gpa.allocator();
        
        var validator = try validation.loadCoreSchema(allocator);
        defer validator.deinit();
        
        const result = validator.validateType(zig_type_name, schema_type_name);
        
        const output = if (result) 
            "✓ Type validation passed"
        else |_|
            "✗ Type validation failed";
        
        return try ctx.directory().withNewFile("type-validation.txt", output);
    }
    
    /// Get API schema version
    pub fn schemaVersion(
        self: *const SchemaValidator,
        ctx: *dagger.Context,
    ) !dagger.File {
        _ = self;
        return try ctx.directory().withNewFile("version.txt", "v0.11.0");
    }
    
    /// List available test categories
    pub fn listCategories(
        self: *const SchemaValidator,
        ctx: *dagger.Context,
    ) !dagger.File {
        _ = self;
        
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        const allocator = gpa.allocator();
        
        var list = std.ArrayList(u8).init(allocator);
        defer list.deinit();
        const writer = list.writer();
        
        try writer.print("# Available Test Categories\n\n", .{});
        
        const categories = std.enums.values(conformance.TestCategory);
        for (categories) |cat| {
            try writer.print("- {s}\n", .{@tagName(cat)});
        }
        
        return try ctx.directory().withNewFile("categories.md", list.items);
    }
    
    /// Full validation pipeline
    pub fn fullValidation(
        self: *const SchemaValidator,
        ctx: *dagger.Context,
    ) !dagger.Directory {
        // Run schema validation
        const schema_report = try self.validate(ctx);
        
        // Run conformance tests
        const conformance_report = try self.conformance(ctx, null);
        
        // Aggregate results
        var results = try ctx.directory();
        results = try results.withFile("schema-report.md", schema_report);
        results = try results.withFile("conformance-report.md", conformance_report);
        
        return results;
    }
};

fn parseCategory(str: []const u8) ?conformance.TestCategory {
    const categories = std.enums.values(conformance.TestCategory);
    for (categories) |cat| {
        if (std.mem.eql(u8, str, @tagName(cat))) {
            return cat;
        }
    }
    return null;
}

pub fn main(init: std.process.Init) !void {
    return dagger.module.serve(init, SchemaValidator{});
}
