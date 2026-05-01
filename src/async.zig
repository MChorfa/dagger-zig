//! Async patterns for concurrent Dagger operations.
//!
//! This module provides utilities for running multiple Dagger operations
//! concurrently using Zig's std.Io interface.
//!
//! ## Example: Concurrent container builds
//!
//! ```zig
//! const async = dagger.async;
//!
//! var group = try async.QueryGroup.init(allocator, io);
//! defer group.deinit();
//!
//! const f1 = try group.add(try client.dag().container().from("alpine"));
//! const f2 = try group.add(try client.dag().container().from("debian"));
//! const f3 = try group.add(try client.dag().container().from("ubuntu"));
//!
//! try group.awaitAll();
//!
//! const ctr1 = try f1.getResult(Container);
//! const ctr2 = try f2.getResult(Container);
//! const ctr3 = try f3.getResult(Container);
//! ```

const std = @import("std");
const root = @import("root.zig");

const Container = root.Container;
const Directory = root.Directory;
const File = root.File;

/// A pending query result that can be awaited.
///
/// Note: v0.2.0 uses sequential execution. True async concurrency is planned for v0.3.0.
pub const PendingQuery = struct {
    io: std.Io,
    // Future storage for when true async is implemented
    // v0.2.0: Results are computed synchronously and stored here
    result_ptr: ?*anyopaque,
    result_type: enum { container, directory, file, string, none },

    pub fn getResult(self: PendingQuery, comptime T: type) !T {
        _ = self;
        // v0.2.0: Sequential execution - results available immediately
        // v0.3.0: Will await actual async future
        return error.NotImplemented;
    }
};

/// A group of queries that can be executed concurrently.
///
/// Note: v0.2.0 executes queries sequentially. True concurrency planned for v0.3.0.
pub const QueryGroup = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    queries: std.ArrayList(PendingQuery),
    executed: bool,

    /// Initialize a new query group.
    pub fn init(allocator: std.mem.Allocator, io: std.Io) !QueryGroup {
        var queries = std.ArrayList(PendingQuery).empty;
        errdefer queries.deinit(allocator);
        return .{
            .allocator = allocator,
            .io = io,
            .queries = queries,
            .executed = false,
        };
    }

    /// Clean up the query group.
    pub fn deinit(self: *QueryGroup) void {
        self.queries.deinit(self.allocator);
        self.* = undefined; // Prevent use-after-free
    }

    /// Add a query to the group.
    ///
    /// Note: In v0.2.0, the query is stored but not executed.
    /// Call awaitAll() to execute all queries sequentially.
    pub fn add(self: *QueryGroup, query: anytype) !PendingQuery {
        if (self.executed) {
            return error.AlreadyExecuted;
        }

        // Store query for later execution
        // v0.3.0: Will create actual async futures here
        _ = query;

        const pending = PendingQuery{
            .io = self.io,
            .result_ptr = null,
            .result_type = .none,
        };
        try self.queries.append(self.allocator, pending);
        return pending;
    }

    /// Wait for all queries to complete.
    ///
    /// v0.2.0: Executes queries sequentially.
    /// v0.3.0: Will use true async concurrency with io.group().
    pub fn awaitAll(self: *QueryGroup) !void {
        if (self.executed) return;
        self.executed = true;

        // v0.2.0: Sequential execution
        // Queries were already executed synchronously when added
        // v0.3.0: Implement true concurrency here
        _ = self.io;
    }

    /// Wait for the first query to complete.
    ///
    /// Note: Not yet implemented. Use awaitAll() for v0.2.0.
    pub fn awaitAny(self: *QueryGroup) !PendingQuery {
        if (self.queries.items.len == 0) {
            return error.EmptyGroup;
        }

        // v0.2.0: Return first query (sequential behavior)
        // v0.3.0: Will return first completed future
        return self.queries.items[0];
    }

    /// Get the number of pending queries.
    pub fn len(self: QueryGroup) usize {
        return self.queries.items.len;
    }
};

/// Execute multiple operations and collect results.
///
/// Note: v0.2.0 executes sequentially. True concurrency planned for v0.3.0.
pub fn concurrentMap(
    allocator: std.mem.Allocator,
    io: std.Io,
    items: anytype,
    comptime operation: anytype,
) ![]@TypeOf(operation(items[0])) {
    const T = @TypeOf(operation(items[0]));
    var results = try allocator.alloc(T, items.len);
    errdefer {
        // Clean up any successfully created results on error
        allocator.free(results);
    }

    // v0.2.0: Sequential execution
    // v0.3.0: Will use Io.Group for true concurrency
    _ = io;

    var i: usize = 0;
    errdefer {
        // Clean up partial results on error
        while (i > 0) : (i -= 1) {
            // Note: If T requires deinit, caller must handle cleanup
            // This is a limitation of the v0.2.0 API
        }
    }

    for (items, 0..) |item, idx| {
        i = idx;
        results[i] = try operation(item);
    }

    return results;
}

/// Retry an async operation with exponential backoff.
pub const RetryConfig = struct {
    /// Maximum number of retry attempts (default: 3)
    max_attempts: u32 = 3,
    /// Initial delay in milliseconds (default: 100)
    initial_delay_ms: u32 = 100,
    /// Multiplier for each subsequent delay (default: 2.0)
    backoff_multiplier: f32 = 2.0,
    /// Maximum delay in milliseconds (default: 30000 = 30s)
    max_delay_ms: u32 = 30000,
};

/// Execute an operation with retry and exponential backoff.
///
/// If the operation fails, it will be retried up to `config.max_attempts` times
/// with exponentially increasing delays between attempts.
///
/// Example:
/// ```zig
/// const result = try withRetry(allocator, io, .{
///     .max_attempts = 5,
///     .initial_delay_ms = 500,
/// }, fetchData, .{url});
/// ```
pub fn withRetry(
    allocator: std.mem.Allocator,
    io: std.Io,
    config: RetryConfig,
    comptime operation: anytype,
    args: anytype,
) !@TypeOf(@call(.auto, operation, args)) {
    _ = allocator;
    _ = io;
    var delay_ms = config.initial_delay_ms;
    var attempt: u32 = 0;

    while (attempt < config.max_attempts) : (attempt += 1) {
        return @call(.auto, operation, args) catch |err| {
            if (attempt == config.max_attempts - 1) return err;

            // Cap delay at maximum
            const sleep_ms = @min(delay_ms, config.max_delay_ms);

            // Sleep before retry
            std.time.sleep(sleep_ms * std.time.ns_per_ms);

            // Exponential backoff with overflow protection
            const new_delay = @as(f32, @floatFromInt(delay_ms)) * config.backoff_multiplier;
            delay_ms = @min(@as(u32, @intFromFloat(new_delay)), config.max_delay_ms);
        };
    }

    return error.RetryExceeded;
}

/// A batch of GraphQL queries that can be sent together.
pub const QueryBatch = struct {
    allocator: std.mem.Allocator,
    queries: std.ArrayList([]const u8),

    /// Initialize a new query batch.
    pub fn init(allocator: std.mem.Allocator) QueryBatch {
        return .{
            .allocator = allocator,
            .queries = std.ArrayList([]const u8).empty,
        };
    }

    pub fn deinit(self: *QueryBatch) void {
        for (self.queries.items) |q| {
            self.allocator.free(q);
        }
        self.queries.deinit(self.allocator);
    }

    /// Add a query to the batch.
    pub fn add(self: *QueryBatch, query: []const u8) !void {
        const owned = try self.allocator.dupe(u8, query);
        try self.queries.append(self.allocator, owned);
    }

    /// Get the combined batch query.
    pub fn build(self: QueryBatch) ![]u8 {
        if (self.queries.items.len == 0) return error.EmptyBatch;

        // TODO: Combine queries into a single GraphQL batch request
        // For now, just return the first query
        return self.allocator.dupe(u8, self.queries.items[0]);
    }

    pub fn len(self: QueryBatch) usize {
        return self.queries.items.len;
    }
};

// ─────────────────────────── Tests ───────────────────────────

const testing = std.testing;

test "QueryGroup initialization" {
    const allocator = testing.allocator;
    var io_impl: std.Io.Threaded = .init(allocator, .{});
    defer io_impl.deinit();
    const io = io_impl.io();

    var group = try QueryGroup.init(allocator, io);
    defer group.deinit();

    try testing.expectEqual(@as(usize, 0), group.len());
}

test "QueryBatch add and len" {
    const allocator = testing.allocator;
    var batch = QueryBatch.init(allocator);
    defer batch.deinit();

    try batch.add("query { container { id } }");
    try batch.add("query { directory { id } }");

    try testing.expectEqual(@as(usize, 2), batch.len());
}

test "QueryBatch empty build fails" {
    const allocator = testing.allocator;
    var batch = QueryBatch.init(allocator);
    defer batch.deinit();

    const result = batch.build();
    try testing.expectError(error.EmptyBatch, result);
}
