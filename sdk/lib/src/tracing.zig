//! OpenTelemetry-compatible tracing for Dagger SDK operations.
//!
//! This module provides distributed tracing for Dagger pipeline operations,
//! compatible with OpenTelemetry and exportable to various backends.
//!
//! Timestamps come from the caller's `std.Io` clock (`Clock.real`) and IDs
//! are generated from `io.random`, so span times and trace/span IDs are real
//! wall-clock values and CSPRNG-seeded randomness respectively.
//!
//! ## Example Usage
//!
//! ```zig
//! const trace = dagger.tracing;
//!
//! // Create a span for an operation
//! var span = try trace.Span.init(allocator, io, "build-container", .{});
//! defer span.end();
//!
//! // Add attributes
//! try span.setAttribute("image", "alpine:latest");
//!
//! // Record the operation
//! const ctr = try client.dag().container(.{}).from("alpine:latest");
//! try span.addEvent("container-created", .{});
//! ```

const std = @import("std");
const meta_compat = @import("meta_compat.zig");

/// Current wall-clock time in nanoseconds since the Unix epoch.
fn nowNs(io: std.Io) i64 {
    return @intCast(std.Io.Clock.real.now(io).toNanoseconds());
}

// ─────────────────────────── Span Types ───────────────────────────

/// A trace span representing a single operation.
pub const Span = struct {
    name: []const u8,
    trace_id: TraceId,
    span_id: SpanId,
    parent_id: ?SpanId,
    start_time: i64, // nanoseconds since epoch
    end_time: ?i64,
    attributes: std.StringHashMap(AttributeValue),
    events: std.ArrayList(SpanEvent),
    status: SpanStatus,
    allocator: std.mem.Allocator,
    io: std.Io,

    pub const SpanStatus = enum {
        unset,
        ok,
        error_,
    };

    /// Initialize a new span.
    pub fn init(allocator: std.mem.Allocator, io: std.Io, name: []const u8, opts: SpanOptions) !Span {
        return .{
            .name = name,
            .trace_id = opts.trace_id orelse TraceId.generate(io),
            .span_id = SpanId.generate(io),
            .parent_id = opts.parent_id,
            .start_time = nowNs(io),
            .end_time = null,
            .attributes = std.StringHashMap(AttributeValue).init(allocator),
            .events = std.ArrayList(SpanEvent).empty,
            .status = .unset,
            .allocator = allocator,
            .io = io,
        };
    }

    /// Clean up span resources.
    pub fn deinit(self: *Span) void {
        var it = self.attributes.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(self.allocator);
        }
        self.attributes.deinit();
        for (self.events.items) |*event| {
            event.deinit(self.allocator);
        }
        self.events.deinit(self.allocator);
    }

    /// End the span.
    pub fn end(self: *Span) void {
        if (self.end_time == null) {
            self.end_time = nowNs(self.io);
        }
    }

    /// Set the span status.
    pub fn setStatus(self: *Span, status: SpanStatus) void {
        self.status = status;
    }

    /// Set a string attribute. Copies the key; overwrites any existing value.
    pub fn setAttribute(self: *Span, key: []const u8, value: anytype) !void {
        const owned_key = try self.allocator.dupe(u8, key);
        errdefer self.allocator.free(owned_key);
        const v = try AttributeValue.from(self.allocator, value);
        errdefer v.deinit(self.allocator);

        if (self.attributes.fetchRemove(key)) |old| {
            self.allocator.free(old.key);
            old.value.deinit(self.allocator);
        }

        try self.attributes.put(owned_key, v);
    }

    /// Add an event to the span. `attrs` may be `.{}` for no attributes or a
    /// struct literal whose fields become event attributes (field names are
    /// borrowed, not copied).
    pub fn addEvent(self: *Span, name: []const u8, attrs: anytype) !void {
        const event = SpanEvent{
            .name = name,
            .timestamp = nowNs(self.io),
            .attributes = try eventAttrs(self.allocator, attrs),
        };
        errdefer {
            var ev = event;
            ev.deinit(self.allocator);
        }
        try self.events.append(self.allocator, event);
    }

    /// Get duration in nanoseconds.
    pub fn durationNs(self: Span) ?i64 {
        const end_time = self.end_time orelse return null;
        return end_time - self.start_time;
    }
};

/// Build an event attribute map from a struct literal. Returns null for
/// empty attribute lists. Field-name keys are static and not owned by the
/// map; values produced by `AttributeValue.from` are owned.
fn eventAttrs(allocator: std.mem.Allocator, attrs: anytype) !?std.StringHashMap(AttributeValue) {
    const AttrsType = @TypeOf(attrs);
    if (@typeInfo(AttrsType) != .@"struct") return null;
    const field_names = comptime meta_compat.structFieldNames(AttrsType);
    if (field_names.len == 0) return null;
    var map = std.StringHashMap(AttributeValue).init(allocator);
    errdefer {
        var it = map.iterator();
        while (it.next()) |entry| entry.value_ptr.deinit(allocator);
        map.deinit();
    }
    inline for (field_names) |name| {
        const v = try AttributeValue.from(allocator, @field(attrs, name));
        map.put(name, v) catch |e| {
            v.deinit(allocator);
            return e;
        };
    }
    return map;
}

pub const SpanOptions = struct {
    trace_id: ?TraceId = null,
    parent_id: ?SpanId = null,
};

/// An event that occurred during a span.
pub const SpanEvent = struct {
    name: []const u8,
    timestamp: i64,
    attributes: ?std.StringHashMap(AttributeValue),

    /// Free owned attribute values and the map. Keys are static field names.
    pub fn deinit(self: *SpanEvent, allocator: std.mem.Allocator) void {
        if (self.attributes) |*map| {
            var it = map.iterator();
            while (it.next()) |entry| {
                entry.value_ptr.deinit(allocator);
            }
            map.deinit();
            self.attributes = null;
        }
    }
};

// ─────────────────────────── IDs ───────────────────────────

/// 16-byte trace ID.
pub const TraceId = struct {
    bytes: [16]u8,

    /// Generate a random trace ID using the io-provided CSPRNG.
    pub fn generate(io: std.Io) TraceId {
        var bytes: [16]u8 = undefined;
        io.random(&bytes);
        return .{ .bytes = bytes };
    }

    pub fn format(
        self: TraceId,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        for (self.bytes) |b| {
            try writer.print("{x:0>2}", .{b});
        }
    }
};

/// 8-byte span ID.
pub const SpanId = struct {
    bytes: [8]u8,

    /// Generate a random span ID using the io-provided CSPRNG.
    pub fn generate(io: std.Io) SpanId {
        var bytes: [8]u8 = undefined;
        io.random(&bytes);
        return .{ .bytes = bytes };
    }

    pub fn eql(self: SpanId, other: SpanId) bool {
        return std.mem.eql(u8, &self.bytes, &other.bytes);
    }

    pub fn format(
        self: SpanId,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        for (self.bytes) |b| {
            try writer.print("{x:0>2}", .{b});
        }
    }
};

// ─────────────────────────── Attributes ───────────────────────────

pub const AttributeValue = union(enum) {
    string: []const u8,
    int: i64,
    float: f64,
    bool: bool,

    pub fn from(allocator: std.mem.Allocator, value: anytype) !AttributeValue {
        const T = @TypeOf(value);
        switch (@typeInfo(T)) {
            .int, .comptime_int => return .{ .int = @intCast(value) },
            .float, .comptime_float => return .{ .float = value },
            .bool => return .{ .bool = value },
            .pointer => |p| {
                const child_info = @typeInfo(p.child);
                const is_u8_slice = p.size == .slice and p.child == u8;
                const is_u8_array_ptr = p.size == .one and
                    child_info == .array and child_info.array.child == u8;
                if (is_u8_slice or is_u8_array_ptr) {
                    return .{ .string = try allocator.dupe(u8, value) };
                }
            },
            else => {},
        }
        return error.UnsupportedAttributeType;
    }

    pub fn deinit(self: AttributeValue, allocator: std.mem.Allocator) void {
        switch (self) {
            .string => |s| allocator.free(s),
            else => {},
        }
    }
};

// ─────────────────────────── Tracer ───────────────────────────

/// The main tracer interface. Spans are heap-allocated so `startSpan`
/// pointers stay valid as more spans are added.
pub const Tracer = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    spans: std.ArrayList(*Span),
    current_span: ?SpanId,

    pub fn init(allocator: std.mem.Allocator, io: std.Io) !Tracer {
        return .{
            .allocator = allocator,
            .io = io,
            .spans = std.ArrayList(*Span).empty,
            .current_span = null,
        };
    }

    pub fn deinit(self: *Tracer) void {
        for (self.spans.items) |span| {
            span.deinit();
            self.allocator.destroy(span);
        }
        self.spans.deinit(self.allocator);
    }

    /// Start a new span. The returned pointer stays valid until `deinit`.
    pub fn startSpan(self: *Tracer, name: []const u8) !*Span {
        const span = try self.allocator.create(Span);
        errdefer self.allocator.destroy(span);
        span.* = try Span.init(self.allocator, self.io, name, .{
            .parent_id = self.current_span,
        });
        errdefer span.deinit();
        try self.spans.append(self.allocator, span);
        self.current_span = span.span_id;
        return span;
    }

    /// End the current span. No-op if no span is active.
    pub fn endSpan(self: *Tracer) void {
        const current = self.current_span orelse return;
        for (self.spans.items) |span| {
            if (span.span_id.eql(current)) {
                span.end();
                self.current_span = span.parent_id;
                return;
            }
        }
    }

    /// Export spans to a writer (OpenTelemetry format).
    pub fn exportJson(self: Tracer, writer: anytype) !void {
        try writer.writeAll("[\n");
        for (self.spans.items, 0..) |span, i| {
            if (i > 0) try writer.writeAll(",\n");
            try writer.writeAll("  {\n");
            try writer.print("    \"name\": \"{s}\",\n", .{span.name});
            try writer.print("    \"traceId\": \"{}\",\n", .{span.trace_id});
            try writer.print("    \"spanId\": \"{}\",\n", .{span.span_id});
            try writer.print("    \"startTime\": {d},\n", .{span.start_time});
            if (span.end_time) |end| {
                try writer.print("    \"endTime\": {d}\n", .{end});
            } else {
                try writer.writeAll("    \"endTime\": null\n");
            }
            try writer.writeAll("  }");
        }
        try writer.writeAll("\n]\n");
    }
};

// Helper for SpanId comparison
pub fn spanIdEql(a: SpanId, b: SpanId) bool {
    return std.mem.eql(u8, &a.bytes, &b.bytes);
}

// ─────────────────────────── Convenience Functions ───────────────────────────

var global_tracer: ?Tracer = null;

/// Initialize the global tracer.
pub fn initGlobalTracer(allocator: std.mem.Allocator, io: std.Io) !void {
    global_tracer = try Tracer.init(allocator, io);
}

/// Get the global tracer.
pub fn getTracer() ?*Tracer {
    return if (global_tracer) |*t| t else null;
}

/// Trace a function call.
pub fn trace(comptime name: []const u8, comptime func: anytype) @TypeOf(func) {
    return struct {
        pub fn traced(args: anytype) !@typeInfo(@TypeOf(func)).@"fn".return_type.? {
            const tracer = getTracer();
            var span_started = false;
            if (tracer) |t| {
                if (t.startSpan(name)) |_| {
                    span_started = true;
                } else |_| {}
            }
            defer {
                if (span_started) {
                    if (tracer) |t| t.endSpan();
                }
            }

            return @call(.auto, func, args);
        }
    }.traced;
}

// ─────────────────────────── Tests ───────────────────────────

const testing = std.testing;

test "Span lifecycle" {
    const allocator = testing.allocator;
    const io = testing.io;
    var span = try Span.init(allocator, io, "test-span", .{});
    defer span.deinit();

    try span.setAttribute("key", "value");
    try span.setAttribute("count", 42);
    try span.addEvent("event", .{ .detail = "hello" });
    span.end();

    try testing.expect(span.end_time != null);
    try testing.expect(span.durationNs() != null);
    // Real wall-clock: a Unix timestamp in ns is far larger than 1e18.
    try testing.expect(span.start_time > 1_700_000_000_000_000_000);
}

test "TraceId generation" {
    const id1 = TraceId.generate(testing.io);
    const id2 = TraceId.generate(testing.io);

    // Should be different
    try testing.expect(!std.mem.eql(u8, &id1.bytes, &id2.bytes));
}

test "Tracer basic operations" {
    const allocator = testing.allocator;
    var tracer = try Tracer.init(allocator, testing.io);
    defer tracer.deinit();

    const span = try tracer.startSpan("test");
    try testing.expectEqual(@as(usize, 1), tracer.spans.items.len);

    span.end();
    tracer.endSpan();
}

test "Tracer span pointers survive additional spans" {
    const allocator = testing.allocator;
    var tracer = try Tracer.init(allocator, testing.io);
    defer tracer.deinit();

    const first = try tracer.startSpan("first");
    for (0..32) |_| {
        _ = try tracer.startSpan("filler");
    }
    first.end();
    try testing.expect(first.end_time != null);
    try testing.expectEqualStrings("first", first.name);
}
