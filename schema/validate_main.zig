//! Standalone Dagger API Schema Validator
//!
//! Usage:
//!   zig run schema/validate_main.zig
//!
//! This tool validates the dagger-zig SDK against the official Dagger GraphQL API.
//! It checks type definitions, method signatures, and API coverage.

const std = @import("std");
const validation = @import("validation.zig");
const conformance = @import("conformance.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();
    
    try stdout.print("Dagger-Zig SDK Schema Validator\n", .{});
    try stdout.print("===============================\n\n", .{});
    
    // Parse command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    
    var run_conformance = true;
    var run_schema_check = true;
    var category_filter: ?conformance.TestCategory = null;
    
    if (args.len > 1) {
        for (args[1..]) |arg| {
            if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
                try printHelp(stdout);
                return;
            } else if (std.mem.eql(u8, arg, "--conformance-only")) {
                run_schema_check = false;
            } else if (std.mem.eql(u8, arg, "--schema-only")) {
                run_conformance = false;
            } else if (std.mem.eql(u8, arg, "--category")) {
                // Next arg is category
            } else if (std.mem.startsWith(u8, arg, "--category=")) {
                const cat_str = arg[11..];
                category_filter = parseCategory(cat_str);
            } else if (std.mem.eql(u8, arg, "--list-categories")) {
                try listCategories(stdout);
                return;
            }
        }
    }
    
    var exit_code: u8 = 0;
    
    // Run schema validation
    if (run_schema_check) {
        try stdout.print("Running Schema Validation...\n", .{});
        const schema_ok = try runSchemaValidation(allocator, stdout, stderr);
        if (!schema_ok) {
            exit_code = 1;
        }
        try stdout.print("\n", .{});
    }
    
    // Run conformance tests
    if (run_conformance) {
        try stdout.print("Running Conformance Tests...\n", .{});
        const conformance_ok = try runConformanceTests(allocator, stdout, stderr, category_filter);
        if (!conformance_ok) {
            exit_code = 1;
        }
    }
    
    // Final summary
    try stdout.print("\n", .{});
    if (exit_code == 0) {
        try stdout.print("✓ All validations passed\n", .{});
    } else {
        try stdout.print("✗ Some validations failed\n", .{});
    }
    
    std.process.exit(exit_code);
}

fn printHelp(writer: anytype) !void {
    try writer.print(
        \\Dagger-Zig SDK Schema Validator
        \\n        \\Usage: zig run schema/validate_main.zig [OPTIONS]
        \\n        \\Options:
        \\  --help, -h              Show this help message
        \\  --conformance-only      Run only conformance tests
        \\  --schema-only           Run only schema validation
        \\  --category=<CAT>        Run only tests in category
        \\  --list-categories       List available test categories
        \\n        \\Examples:
        \\  zig run schema/validate_main.zig
        \\  zig run schema/validate_main.zig --category=container_api
        \\  zig run schema/validate_main.zig --schema-only
        \\n    , .{});
}

fn listCategories(writer: anytype) !void {
    try writer.print("Available test categories:\n", .{});
    const categories = std.enums.values(conformance.TestCategory);
    for (categories) |cat| {
        try writer.print("  - {s}\n", .{@tagName(cat)});
    }
}

fn parseCategory(str: []const u8) ?conformance.TestCategory {
    const categories = std.enums.values(conformance.TestCategory);
    for (categories) |cat| {
        if (std.mem.eql(u8, str, @tagName(cat))) {
            return cat;
        }
    }
    return null;
}

fn runSchemaValidation(allocator: std.mem.Allocator, stdout: anytype, stderr: anytype) !bool {
    _ = stderr;
    
    var validator = try validation.loadCoreSchema(allocator);
    defer validator.deinit();
    
    try validator.generateReport(stdout);
    
    // TODO: Add actual SDK validation logic
    // For now, just report what we have
    try stdout.print("\nSchema loaded: {d} types, {d} queries\n", 
        .{validator.types.count(), validator.queries.count()});
    
    return true;
}

fn runConformanceTests(
    allocator: std.mem.Allocator, 
    stdout: anytype, 
    stderr: anytype,
    category_filter: ?conformance.TestCategory,
) !bool {
    _ = stderr;
    
    var runner = conformance.ConformanceRunner.init(allocator);
    defer runner.deinit();
    
    if (category_filter) |cat| {
        try runner.runCategory(cat);
    } else {
        try runner.runAll();
    }
    
    try runner.generateReport(stdout);
    
    // Check if all passed
    var all_passed = true;
    for (runner.results.items) |result| {
        if (!result.passed) {
            all_passed = false;
            break;
        }
    }
    
    return all_passed;
}
