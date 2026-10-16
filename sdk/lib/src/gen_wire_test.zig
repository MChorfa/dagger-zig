//! Offline wire-format tests for the generated SDK surface.
//!
//! These tests build Selection chains through generated methods and assert
//! on the emitted GraphQL text — no engine required. They pin the contract
//! the generator must uphold against the real v0.21.9 schema:
//!
//!   - IDs are plain GraphQL `ID` scalars (no `XxxID` scalars upstream)
//!   - object reconstruction is `node(id:)` + `... on T` inline fragments
//!   - args serialize via qb.serializeValue (strings/ints/enums/inputs/lists)
//!
//! Execution paths (executeLeaf, sync, list reconstruction) are covered by
//! the live-engine suite, not here — a never-dereferenced client pointer is
//! enough for selection-building.

const std = @import("std");
const testing = std.testing;
const api = @import("gen.zig");
const qb = @import("querybuilder.zig");
const gql = @import("core/graphql_client.zig");

const Selection = qb.Selection;

const Fixture = struct {
    arena_impl: std.heap.ArenaAllocator,
    stub_client: gql.GraphQLClient,

    fn init() Fixture {
        return .{
            .arena_impl = std.heap.ArenaAllocator.init(testing.allocator),
            // Never dereferenced: chain-only methods copy the pointer.
            .stub_client = undefined,
        };
    }

    fn arena(self: *Fixture) std.mem.Allocator {
        return self.arena_impl.allocator();
    }

    fn query(self: *Fixture) api.Query {
        return .{
            .allocator = testing.allocator,
            .arena = self.arena(),
            .selection = &Selection.root,
            .gql = &self.stub_client,
        };
    }

    fn deinit(self: *Fixture) void {
        self.arena_impl.deinit();
    }
};

test "loadContainerFromID emits node + inline fragment" {
    var f = Fixture.init();
    defer f.deinit();

    const q = f.query();
    const ctr = try q.loadContainerFromID(.{ .value = "abc123" });

    const text = try ctr.selection.build(testing.allocator);
    defer testing.allocator.free(text);

    try testing.expectEqualStrings(
        \\query{node(id:"abc123"){... on Container}}
    , text);
}

test "loadDirectoryFromID then chained select lands inside the fragment" {
    var f = Fixture.init();
    defer f.deinit();

    const q = f.query();
    const dir = try q.loadDirectoryFromID(.{ .value = "d9" });
    const file = try dir.file("/etc/hostname");

    const text = try file.selection.build(testing.allocator);
    defer testing.allocator.free(text);

    try testing.expectEqualStrings(
        \\query{node(id:"d9"){... on Directory{file(path:"/etc/hostname")}}}
    , text);
}

test "container options serialize scalar wrapper args" {
    var f = Fixture.init();
    defer f.deinit();

    const q = f.query();
    const ctr = try q.container(.{ .platform = .{ .value = "linux/arm64" } });

    const text = try ctr.selection.build(testing.allocator);
    defer testing.allocator.free(text);

    try testing.expectEqualStrings(
        \\query{container(platform:"linux/arm64")}
    , text);
}

test "empty options emit no arg list" {
    var f = Fixture.init();
    defer f.deinit();

    const q = f.query();
    const ctr = try q.container(.{});

    const text = try ctr.selection.build(testing.allocator);
    defer testing.allocator.free(text);

    try testing.expectEqualStrings(
        \\query{container}
    , text);
}

test "withExec serializes a string list argument" {
    var f = Fixture.init();
    defer f.deinit();

    const q = f.query();
    const ctr = try q.container(.{});
    const ran = try ctr.withExec(&.{ "echo", "hello" }, .{});

    const text = try ran.selection.build(testing.allocator);
    defer testing.allocator.free(text);

    try testing.expectEqualStrings(
        \\query{container{withExec(args:["echo","hello"])}}
    , text);
}

test "dockerBuild serializes input-object list args" {
    var f = Fixture.init();
    defer f.deinit();

    const q = f.query();
    const dir = try q.loadDirectoryFromID(.{ .value = "d1" });
    const ctr = try dir.dockerBuild(.{
        .dockerfile = "ci.Dockerfile",
        .buildArgs = &.{
            .{ .name = "GO_VERSION", .value = "1.26" },
            .{ .name = "TARGET", .value = "release" },
        },
        .noInit = true,
    });

    const text = try ctr.selection.build(testing.allocator);
    defer testing.allocator.free(text);

    try testing.expectEqualStrings(
        \\query{node(id:"d1"){... on Directory{dockerBuild(dockerfile:"ci.Dockerfile", buildArgs:[{name:"GO_VERSION",value:"1.26"},{name:"TARGET",value:"release"}], noInit:true)}}}
    , text);
}

test "asTarball serializes enum args as bare wire tags" {
    var f = Fixture.init();
    defer f.deinit();

    const q = f.query();
    const ctr = try q.loadContainerFromID(.{ .value = "c7" });
    const tarball = try ctr.asTarball(.{
        .forcedCompression = .zstd,
        .mediaTypes = .oCIMediaTypes,
    });

    const text = try tarball.selection.build(testing.allocator);
    defer testing.allocator.free(text);

    try testing.expectEqualStrings(
        \\query{node(id:"c7"){... on Container{asTarball(forcedCompression:Zstd, mediaTypes:OCIMediaTypes)}}}
    , text);
}
