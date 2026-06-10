//! Hand-written reference of what the generated `gen.zig` should look like.
//!
//! This is NOT the generated file — it's a curated subset (Query, Container,
//! Directory, File, CacheVolume, Secret, a few IDs) used:
//!   1. As the compile-time target for the codegen emitter in `codegen/`.
//!   2. As a usable API for v0.1 before full codegen lands.
//!   3. As a testbed for the querybuilder + GraphQL client integration.
//!
//! ## Conventions
//!
//! Every generated type follows this shape:
//!
//!     pub const Foo = struct {
//!         allocator: std.mem.Allocator,
//!         arena: std.mem.Allocator,       // from Client — selections live here
//!         selection: *const Selection,
//!         gql: *GraphQLClient,
//!
//!         // Methods that drill further into the graph return a new `Foo` /
//!         // `Bar` with `.selection = self.selection.select(...).arg(...)`.
//!         //
//!         // Methods that execute (return a scalar) call `self.gql.query(...)`
//!         // and unpack the single leaf value from the JSON envelope.
//!     };
//!
//! This mirrors the Rust SDK's generated code 1:1. When you see a Rust method
//! like `fn stdout(&self) -> impl Future<Output = Result<String>>`, the Zig
//! equivalent is `fn stdout(self: Container) ![]u8`.

const std = @import("std");
const qb = @import("querybuilder.zig");
const gql = @import("core/graphql_client.zig");
const errs = @import("errors.zig");

const Selection = qb.Selection;
const GraphQLClient = gql.GraphQLClient;

// ─────────────────────────── opaque ID scalars ──────────────────────────────

pub const ContainerID = struct {
    value: []const u8, // owned

    pub fn deinit(self: *ContainerID, allocator: std.mem.Allocator) void {
        allocator.free(self.value);
    }
};

pub const DirectoryID = struct {
    value: []const u8,
    pub fn deinit(self: *DirectoryID, allocator: std.mem.Allocator) void {
        allocator.free(self.value);
    }
};

pub const FileID = struct {
    value: []const u8,
    pub fn deinit(self: *FileID, allocator: std.mem.Allocator) void {
        allocator.free(self.value);
    }
};

pub const SecretID = struct {
    value: []const u8,
    pub fn deinit(self: *SecretID, allocator: std.mem.Allocator) void {
        allocator.free(self.value);
    }
};

pub const CacheVolumeID = struct {
    value: []const u8,
    pub fn deinit(self: *CacheVolumeID, allocator: std.mem.Allocator) void {
        allocator.free(self.value);
    }
};

/// Opaque platform specifier, e.g. "linux/amd64".
pub const Platform = struct { value: []const u8 };

// ─────────────────────────── root Query ─────────────────────────────────────

/// The root of the Dagger API. Obtain from `Client.dag()`.
pub const Query = struct {
    allocator: std.mem.Allocator,
    arena: std.mem.Allocator,
    selection: *const Selection,
    gql: *GraphQLClient,

    pub fn container(self: Query) !Container {
        const s = try self.selection.select(self.arena, "container");
        return .{
            .allocator = self.allocator,
            .arena = self.arena,
            .selection = s,
            .gql = self.gql,
        };
    }

    pub fn directory(self: Query) !Directory {
        const s = try self.selection.select(self.arena, "directory");
        return .{
            .allocator = self.allocator,
            .arena = self.arena,
            .selection = s,
            .gql = self.gql,
        };
    }

    /// Load a named cache volume. Shared across runs.
    pub fn cacheVolume(self: Query, key: []const u8) !CacheVolume {
        const s1 = try self.selection.select(self.arena, "cacheVolume");
        const s2 = try s1.argStr(self.arena, "key", key);
        return .{
            .allocator = self.allocator,
            .arena = self.arena,
            .selection = s2,
            .gql = self.gql,
        };
    }

    /// Set a new secret from a plaintext value. Prefer env vars for real keys.
    pub fn setSecret(self: Query, name: []const u8, plaintext: []const u8) !Secret {
        const s1 = try self.selection.select(self.arena, "setSecret");
        const s2 = try s1.argStr(self.arena, "name", name);
        const s3 = try s2.argStr(self.arena, "plaintext", plaintext);
        return .{
            .allocator = self.allocator,
            .arena = self.arena,
            .selection = s3,
            .gql = self.gql,
        };
    }

    /// Load a git repository.
    pub fn git(self: Query, url: []const u8) !GitRepository {
        const s1 = try self.selection.select(self.arena, "git");
        const s2 = try s1.argStr(self.arena, "url", url);
        return .{
            .allocator = self.allocator,
            .arena = self.arena,
            .selection = s2,
            .gql = self.gql,
        };
    }

    /// Load the host filesystem.
    pub fn host(self: Query) !Host {
        const s = try self.selection.select(self.arena, "host");
        return .{
            .allocator = self.allocator,
            .arena = self.arena,
            .selection = s,
            .gql = self.gql,
        };
    }
};

// ─────────────────────────── Container ──────────────────────────────────────

pub const Container = struct {
    allocator: std.mem.Allocator,
    arena: std.mem.Allocator,
    selection: *const Selection,
    gql: *GraphQLClient,

    pub fn from(self: Container, address: []const u8) !Container {
        const s1 = try self.selection.select(self.arena, "from");
        const s2 = try s1.argStr(self.arena, "address", address);
        return .{ .allocator = self.allocator, .arena = self.arena, .selection = s2, .gql = self.gql };
    }

    pub fn withExec(self: Container, argv: []const []const u8) !Container {
        const lit = try qb.serializeStringList(self.arena, argv);
        const s1 = try self.selection.select(self.arena, "withExec");
        const s2 = try s1.arg(self.arena, "args", .{ .eager = lit });
        return .{ .allocator = self.allocator, .arena = self.arena, .selection = s2, .gql = self.gql };
    }

    pub fn withWorkdir(self: Container, path: []const u8) !Container {
        const s1 = try self.selection.select(self.arena, "withWorkdir");
        const s2 = try s1.argStr(self.arena, "path", path);
        return .{ .allocator = self.allocator, .arena = self.arena, .selection = s2, .gql = self.gql };
    }

    pub fn withEnvVariable(self: Container, name: []const u8, value: []const u8) !Container {
        const s1 = try self.selection.select(self.arena, "withEnvVariable");
        const s2 = try s1.argStr(self.arena, "name", name);
        const s3 = try s2.argStr(self.arena, "value", value);
        return .{ .allocator = self.allocator, .arena = self.arena, .selection = s3, .gql = self.gql };
    }

    pub fn withDirectory(self: Container, path: []const u8, dir: Directory) !Container {
        // `dir` has to be resolved to its DirectoryID before we can send the
        // arg. In the Rust SDK this is done lazily; we resolve eagerly here
        // since we're synchronous. That means `withDirectory` triggers a
        // round-trip — which matches engine semantics.
        var dir_id = try dir.id();
        defer dir_id.deinit(self.allocator);
        const id_lit = try qb.serializeString(self.arena, dir_id.value);
        const s1 = try self.selection.select(self.arena, "withDirectory");
        const s2 = try s1.argStr(self.arena, "path", path);
        const s3 = try s2.arg(self.arena, "source", .{ .eager = id_lit });
        return .{ .allocator = self.allocator, .arena = self.arena, .selection = s3, .gql = self.gql };
    }

    pub fn withMountedCache(self: Container, path: []const u8, cache: CacheVolume) !Container {
        var cache_id = try cache.id();
        defer cache_id.deinit(self.allocator);
        const id_lit = try qb.serializeString(self.arena, cache_id.value);
        const s1 = try self.selection.select(self.arena, "withMountedCache");
        const s2 = try s1.argStr(self.arena, "path", path);
        const s3 = try s2.arg(self.arena, "cache", .{ .eager = id_lit });
        return .{ .allocator = self.allocator, .arena = self.arena, .selection = s3, .gql = self.gql };
    }

    /// Add a secret as a mounted file. The secret value is never exposed in logs.
    pub fn withSecret(self: Container, path: []const u8, secret: Secret) !Container {
        var secret_id = try secret.id();
        defer secret_id.deinit(self.allocator);
        const id_lit = try qb.serializeString(self.arena, secret_id.value);
        const s1 = try self.selection.select(self.arena, "withSecret");
        const s2 = try s1.argStr(self.arena, "path", path);
        const s3 = try s2.arg(self.arena, "secret", .{ .eager = id_lit });
        return .{ .allocator = self.allocator, .arena = self.arena, .selection = s3, .gql = self.gql };
    }

    /// Expose a secret as an environment variable. The secret value is never exposed in logs.
    pub fn withSecretVariable(self: Container, name: []const u8, secret: Secret) !Container {
        var secret_id = try secret.id();
        defer secret_id.deinit(self.allocator);
        const id_lit = try qb.serializeString(self.arena, secret_id.value);
        const s1 = try self.selection.select(self.arena, "withSecretVariable");
        const s2 = try s1.argStr(self.arena, "name", name);
        const s3 = try s2.arg(self.arena, "secret", .{ .eager = id_lit });
        return .{ .allocator = self.allocator, .arena = self.arena, .selection = s3, .gql = self.gql };
    }

    /// Add a service binding, making the service accessible to this container.
    pub fn withService(self: Container, alias: []const u8, svc: Service) !Container {
        var svc_id = try svc.id();
        defer svc_id.deinit(self.allocator);
        const id_lit = try qb.serializeString(self.arena, svc_id.value);
        const s1 = try self.selection.select(self.arena, "withService");
        const s2 = try s1.argStr(self.arena, "alias", alias);
        const s3 = try s2.arg(self.arena, "service", .{ .eager = id_lit });
        return .{ .allocator = self.allocator, .arena = self.arena, .selection = s3, .gql = self.gql };
    }

    /// Mount a file from the host or another container.
    pub fn withFile(self: Container, path: []const u8, source: File) !Container {
        var file_id = try source.id();
        defer file_id.deinit(self.allocator);
        const id_lit = try qb.serializeString(self.arena, file_id.value);
        const s1 = try self.selection.select(self.arena, "withFile");
        const s2 = try s1.argStr(self.arena, "path", path);
        const s3 = try s2.arg(self.arena, "source", .{ .eager = id_lit });
        return .{ .allocator = self.allocator, .arena = self.arena, .selection = s3, .gql = self.gql };
    }

    /// Create a new file with the given contents.
    pub fn withNewFile(self: Container, path: []const u8, contents: []const u8) !Container {
        const s1 = try self.selection.select(self.arena, "withNewFile");
        const s2 = try s1.argStr(self.arena, "path", path);
        const s3 = try s2.argStr(self.arena, "contents", contents);
        return .{ .allocator = self.allocator, .arena = self.arena, .selection = s3, .gql = self.gql };
    }

    /// Mount a directory from the host or another container.
    pub fn withMountedDirectory(self: Container, path: []const u8, source: Directory) !Container {
        var dir_id = try source.id();
        defer dir_id.deinit(self.allocator);
        const id_lit = try qb.serializeString(self.arena, dir_id.value);
        const s1 = try self.selection.select(self.arena, "withMountedDirectory");
        const s2 = try s1.argStr(self.arena, "path", path);
        const s3 = try s2.arg(self.arena, "source", .{ .eager = id_lit });
        return .{ .allocator = self.allocator, .arena = self.arena, .selection = s3, .gql = self.gql };
    }

    /// Expose a network port.
    pub fn withExposedPort(self: Container, port: u16) !Container {
        const s1 = try self.selection.select(self.arena, "withExposedPort");
        const port_str = try std.fmt.allocPrint(self.arena, "{d}", .{port});
        const s2 = try s1.arg(self.arena, "port", .{ .eager = port_str });
        return .{ .allocator = self.allocator, .arena = self.arena, .selection = s2, .gql = self.gql };
    }

    /// Set the entrypoint for the container.
    pub fn withEntrypoint(self: Container, entrypoint: []const []const u8) !Container {
        const lit = try qb.serializeStringList(self.arena, entrypoint);
        const s1 = try self.selection.select(self.arena, "withEntrypoint");
        const s2 = try s1.arg(self.arena, "args", .{ .eager = lit });
        return .{ .allocator = self.allocator, .arena = self.arena, .selection = s2, .gql = self.gql };
    }

    /// Remove the default entrypoint.
    pub fn withoutEntrypoint(self: Container) !Container {
        const s = try self.selection.select(self.arena, "withoutEntrypoint");
        return .{ .allocator = self.allocator, .arena = self.arena, .selection = s, .gql = self.gql };
    }

    /// Set the default command (CMD) for the container.
    pub fn withDefaultArgs(self: Container, args: []const []const u8) !Container {
        const lit = try qb.serializeStringList(self.arena, args);
        const s1 = try self.selection.select(self.arena, "withDefaultArgs");
        const s2 = try s1.arg(self.arena, "args", .{ .eager = lit });
        return .{ .allocator = self.allocator, .arena = self.arena, .selection = s2, .gql = self.gql };
    }

    /// Set the user for subsequent operations.
    pub fn withUser(self: Container, user: []const u8) !Container {
        const s1 = try self.selection.select(self.arena, "withUser");
        const s2 = try s1.argStr(self.arena, "name", user);
        return .{ .allocator = self.allocator, .arena = self.arena, .selection = s2, .gql = self.gql };
    }

    // ── terminal operations ──

    /// Return stdout of the last exec. Caller owns the returned slice.
    pub fn stdout(self: Container) ![]u8 {
        const s = try self.selection.select(self.arena, "stdout");
        return executeScalarString(self.allocator, s, self.gql);
    }

    pub fn stderr(self: Container) ![]u8 {
        const s = try self.selection.select(self.arena, "stderr");
        return executeScalarString(self.allocator, s, self.gql);
    }

    /// Force evaluation without returning a scalar — useful for "did this run?"
    pub fn sync(self: Container) !ContainerID {
        return self.id();
    }

    pub fn id(self: Container) !ContainerID {
        const s = try self.selection.select(self.arena, "id");
        const raw = try executeScalarString(self.allocator, s, self.gql);
        return .{ .value = raw };
    }

    pub fn publish(self: Container, address: []const u8) ![]u8 {
        const s1 = try self.selection.select(self.arena, "publish");
        const s2 = try s1.argStr(self.arena, "address", address);
        return executeScalarString(self.allocator, s2, self.gql);
    }

    /// Convert this container to a service (after exposing ports).
    pub fn asService(self: Container) !Service {
        const s = try self.selection.select(self.arena, "asService");
        return .{
            .allocator = self.allocator,
            .arena = self.arena,
            .selection = s,
            .gql = self.gql,
        };
    }

    /// Get a file from this container.
    pub fn file(self: Container, path: []const u8) !File {
        const s1 = try self.selection.select(self.arena, "file");
        const s2 = try s1.argStr(self.arena, "path", path);
        return .{
            .allocator = self.allocator,
            .arena = self.arena,
            .selection = s2,
            .gql = self.gql,
        };
    }

    /// Get a directory from this container.
    pub fn directory(self: Container, path: []const u8) !Directory {
        const s1 = try self.selection.select(self.arena, "directory");
        const s2 = try s1.argStr(self.arena, "path", path);
        return .{
            .allocator = self.allocator,
            .arena = self.arena,
            .selection = s2,
            .gql = self.gql,
        };
    }
};

// ─────────────────────────── Directory ──────────────────────────────────────

pub const Directory = struct {
    allocator: std.mem.Allocator,
    arena: std.mem.Allocator,
    selection: *const Selection,
    gql: *GraphQLClient,

    pub fn id(self: Directory) !DirectoryID {
        const s = try self.selection.select(self.arena, "id");
        const raw = try executeScalarString(self.allocator, s, self.gql);
        return .{ .value = raw };
    }

    pub fn file(self: Directory, path: []const u8) !File {
        const s1 = try self.selection.select(self.arena, "file");
        const s2 = try s1.argStr(self.arena, "path", path);
        return .{ .allocator = self.allocator, .arena = self.arena, .selection = s2, .gql = self.gql };
    }

    pub fn entries(self: Directory) ![][]u8 {
        const s = try self.selection.select(self.arena, "entries");
        return executeScalarStringList(self.allocator, s, self.gql);
    }

    /// Create a new file with the given contents inside this directory.
    pub fn withNewFile(self: Directory, path: []const u8, contents: []const u8) !Directory {
        const s1 = try self.selection.select(self.arena, "withNewFile");
        const s2 = try s1.argStr(self.arena, "path", path);
        const s3 = try s2.argStr(self.arena, "contents", contents);
        return .{ .allocator = self.allocator, .arena = self.arena, .selection = s3, .gql = self.gql };
    }
};

// ─────────────────────────── File ───────────────────────────────────────────

pub const File = struct {
    allocator: std.mem.Allocator,
    arena: std.mem.Allocator,
    selection: *const Selection,
    gql: *GraphQLClient,

    pub fn contents(self: File) ![]u8 {
        const s = try self.selection.select(self.arena, "contents");
        return executeScalarString(self.allocator, s, self.gql);
    }

    pub fn id(self: File) !FileID {
        const s = try self.selection.select(self.arena, "id");
        const raw = try executeScalarString(self.allocator, s, self.gql);
        return .{ .value = raw };
    }
};

// ─────────────────────────── CacheVolume ────────────────────────────────────

pub const CacheVolume = struct {
    allocator: std.mem.Allocator,
    arena: std.mem.Allocator,
    selection: *const Selection,
    gql: *GraphQLClient,

    pub fn id(self: CacheVolume) !CacheVolumeID {
        const s = try self.selection.select(self.arena, "id");
        const raw = try executeScalarString(self.allocator, s, self.gql);
        return .{ .value = raw };
    }
};

// ─────────────────────────── Secret ─────────────────────────────────────────

pub const Secret = struct {
    allocator: std.mem.Allocator,
    arena: std.mem.Allocator,
    selection: *const Selection,
    gql: *GraphQLClient,

    pub fn id(self: Secret) !SecretID {
        const s = try self.selection.select(self.arena, "id");
        const raw = try executeScalarString(self.allocator, s, self.gql);
        return .{ .value = raw };
    }
};

// ─────────────────────────── execute helpers ────────────────────────────────

/// Execute a selection that returns a single `String` leaf. Unpacks the
/// GraphQL envelope `{data: {field: {...: "value"}}}` by walking single-key
/// nested objects until we find a string leaf.
fn executeScalarString(
    allocator: std.mem.Allocator,
    sel: *const Selection,
    client: *GraphQLClient,
) ![]u8 {
    const query_str = try sel.build(allocator);
    defer allocator.free(query_str);

    const body = try client.query(query_str);
    defer allocator.free(body);

    // Parse the envelope {"data": {...}} and walk to the string leaf.
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch
        return error.MalformedResponse;
    defer parsed.deinit();

    const root = parsed.value.object.get("data") orelse return error.InvalidEnvelope;
    const leaf = walkToStringLeaf(root) orelse return error.InvalidEnvelope;
    return allocator.dupe(u8, leaf);
}

fn executeScalarStringList(
    allocator: std.mem.Allocator,
    sel: *const Selection,
    client: *GraphQLClient,
) ![][]u8 {
    const query_str = try sel.build(allocator);
    defer allocator.free(query_str);

    const body = try client.query(query_str);
    defer allocator.free(body);

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch
        return error.MalformedResponse;
    defer parsed.deinit();

    const root = parsed.value.object.get("data") orelse return error.InvalidEnvelope;
    const arr = walkToArrayLeaf(root) orelse return error.InvalidEnvelope;

    var out = try allocator.alloc([]u8, arr.items.len);
    errdefer allocator.free(out);
    for (arr.items, 0..) |item, i| {
        const s = switch (item) {
            .string => |s| s,
            else => return error.InvalidEnvelope,
        };
        out[i] = try allocator.dupe(u8, s);
    }
    return out;
}

fn walkToStringLeaf(v: std.json.Value) ?[]const u8 {
    return switch (v) {
        .string => |s| s,
        .object => |o| blk: {
            if (o.count() != 1) break :blk null;
            var it = o.iterator();
            const entry = it.next() orelse break :blk null;
            break :blk walkToStringLeaf(entry.value_ptr.*);
        },
        else => null,
    };
}

fn walkToArrayLeaf(v: std.json.Value) ?std.json.Array {
    return switch (v) {
        .array => |a| a,
        .object => |o| blk: {
            if (o.count() != 1) break :blk null;
            var it = o.iterator();
            const entry = it.next() orelse break :blk null;
            break :blk walkToArrayLeaf(entry.value_ptr.*);
        },
        else => null,
    };
}

// ─────────────────────────── Service ──────────────────────────────────────────

pub const Service = struct {
    allocator: std.mem.Allocator,
    arena: std.mem.Allocator,
    selection: *const Selection,
    gql: *GraphQLClient,

    /// Start the service and return a running service reference.
    pub fn up(self: Service) !Service {
        const s = try self.selection.select(self.arena, "up");
        return .{
            .allocator = self.allocator,
            .arena = self.arena,
            .selection = s,
            .gql = self.gql,
        };
    }

    /// Get the endpoint URL for connecting to this service.
    pub fn endpoint(self: Service) ![]u8 {
        const s = try self.selection.select(self.arena, "endpoint");
        return executeScalarString(self.allocator, s, self.gql);
    }

    /// Get the hostname for connecting to this service.
    pub fn hostname(self: Service) ![]u8 {
        const s = try self.selection.select(self.arena, "hostname");
        return executeScalarString(self.allocator, s, self.gql);
    }

    /// Stop the service.
    pub fn stop(self: Service) !void {
        const s = try self.selection.select(self.arena, "stop");
        _ = try executeScalarString(self.allocator, s, self.gql);
    }

    /// Expose a port on this service.
    pub fn withExposedPort(self: Service, port: u16) !Service {
        const s1 = try self.selection.select(self.arena, "withExposedPort");
        const s2 = try s1.arg(self.arena, "port", .{ .eager = try std.fmt.allocPrint(self.arena, "{d}", .{port}) });
        return .{
            .allocator = self.allocator,
            .arena = self.arena,
            .selection = s2,
            .gql = self.gql,
        };
    }

    pub fn id(self: Service) !ServiceID {
        const s = try self.selection.select(self.arena, "id");
        const raw = try executeScalarString(self.allocator, s, self.gql);
        return .{ .value = raw };
    }
};

pub const ServiceID = struct {
    value: []const u8,
    pub fn deinit(self: *ServiceID, allocator: std.mem.Allocator) void {
        allocator.free(self.value);
    }
};

// ─────────────────────────── GitRepository ──────────────────────────────────

pub const GitRepository = struct {
    allocator: std.mem.Allocator,
    arena: std.mem.Allocator,
    selection: *const Selection,
    gql: *GraphQLClient,

    /// Get a reference to a specific branch.
    pub fn branch(self: GitRepository, name: []const u8) !GitRef {
        const s1 = try self.selection.select(self.arena, "branch");
        const s2 = try s1.argStr(self.arena, "name", name);
        return .{
            .allocator = self.allocator,
            .arena = self.arena,
            .selection = s2,
            .gql = self.gql,
        };
    }

    /// Get a reference to a specific tag.
    pub fn tag(self: GitRepository, name: []const u8) !GitRef {
        const s1 = try self.selection.select(self.arena, "tag");
        const s2 = try s1.argStr(self.arena, "name", name);
        return .{
            .allocator = self.allocator,
            .arena = self.arena,
            .selection = s2,
            .gql = self.gql,
        };
    }

    /// Get the default branch (usually main/master).
    pub fn head(self: GitRepository) !GitRef {
        const s = try self.selection.select(self.arena, "head");
        return .{
            .allocator = self.allocator,
            .arena = self.arena,
            .selection = s,
            .gql = self.gql,
        };
    }

    pub fn id(self: GitRepository) !GitRepositoryID {
        const s = try self.selection.select(self.arena, "id");
        const raw = try executeScalarString(self.allocator, s, self.gql);
        return .{ .value = raw };
    }
};

pub const GitRepositoryID = struct {
    value: []const u8,
    pub fn deinit(self: *GitRepositoryID, allocator: std.mem.Allocator) void {
        allocator.free(self.value);
    }
};

// ─────────────────────────── GitRef ─────────────────────────────────────────────

pub const GitRef = struct {
    allocator: std.mem.Allocator,
    arena: std.mem.Allocator,
    selection: *const Selection,
    gql: *GraphQLClient,

    /// Get the filesystem tree at this ref.
    pub fn tree(self: GitRef) !Directory {
        const s = try self.selection.select(self.arena, "tree");
        return .{
            .allocator = self.allocator,
            .arena = self.arena,
            .selection = s,
            .gql = self.gql,
        };
    }

    /// Get the commit message.
    pub fn commitMessage(self: GitRef) ![]u8 {
        const s = try self.selection.select(self.arena, "commitMessage");
        return executeScalarString(self.allocator, s, self.gql);
    }

    /// Get the commit SHA.
    pub fn commit(self: GitRef) ![]u8 {
        const s = try self.selection.select(self.arena, "commit");
        return executeScalarString(self.allocator, s, self.gql);
    }

    pub fn id(self: GitRef) !GitRefID {
        const s = try self.selection.select(self.arena, "id");
        const raw = try executeScalarString(self.allocator, s, self.gql);
        return .{ .value = raw };
    }
};

pub const GitRefID = struct {
    value: []const u8,
    pub fn deinit(self: *GitRefID, allocator: std.mem.Allocator) void {
        allocator.free(self.value);
    }
};

// ─────────────────────────── Host ─────────────────────────────────────────────

pub const Host = struct {
    allocator: std.mem.Allocator,
    arena: std.mem.Allocator,
    selection: *const Selection,
    gql: *GraphQLClient,

    /// Access a directory on the host.
    pub fn directory(self: Host, path: []const u8) !Directory {
        const s1 = try self.selection.select(self.arena, "directory");
        const s2 = try s1.argStr(self.arena, "path", path);
        return .{
            .allocator = self.allocator,
            .arena = self.arena,
            .selection = s2,
            .gql = self.gql,
        };
    }

    /// Access a file on the host.
    pub fn file(self: Host, path: []const u8) !File {
        const s1 = try self.selection.select(self.arena, "file");
        const s2 = try s1.argStr(self.arena, "path", path);
        return .{
            .allocator = self.allocator,
            .arena = self.arena,
            .selection = s2,
            .gql = self.gql,
        };
    }

    /// Access a Unix socket on the host.
    pub fn unixSocket(self: Host, path: []const u8) !Socket {
        const s1 = try self.selection.select(self.arena, "unixSocket");
        const s2 = try s1.argStr(self.arena, "path", path);
        return .{
            .allocator = self.allocator,
            .arena = self.arena,
            .selection = s2,
            .gql = self.gql,
        };
    }

    /// Access an environment variable.
    pub fn envVariable(self: Host, name: []const u8) ![]u8 {
        const s1 = try self.selection.select(self.arena, "envVariable");
        const s2 = try s1.argStr(self.arena, "name", name);
        return executeScalarString(self.allocator, s2, self.gql);
    }

    pub fn id(self: Host) !HostID {
        const s = try self.selection.select(self.arena, "id");
        const raw = try executeScalarString(self.allocator, s, self.gql);
        return .{ .value = raw };
    }
};

pub const HostID = struct {
    value: []const u8,
    pub fn deinit(self: *HostID, allocator: std.mem.Allocator) void {
        allocator.free(self.value);
    }
};

pub const Socket = struct {
    allocator: std.mem.Allocator,
    arena: std.mem.Allocator,
    selection: *const Selection,
    gql: *GraphQLClient,

    pub fn id(self: Socket) !SocketID {
        const s = try self.selection.select(self.arena, "id");
        const raw = try executeScalarString(self.allocator, s, self.gql);
        return .{ .value = raw };
    }
};

pub const SocketID = struct {
    value: []const u8,
    pub fn deinit(self: *SocketID, allocator: std.mem.Allocator) void {
        allocator.free(self.value);
    }
};

// ─────────────────────────── tests (offline) ────────────────────────────────

const testing = std.testing;

test "container from/withExec chain builds correct GraphQL" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // Dummy client — we won't hit it; we only inspect the query.
    var io_impl: std.Io.Threaded = .init(testing.allocator, undefined);
    defer io_impl.deinit();
    const io = io_impl.io();
    var client: GraphQLClient = .{
        .allocator = testing.allocator,
        .io = io,
        .endpoint = "unused",
        .endpoint_uri = std.Uri.parse("http://127.0.0.1:1/query") catch unreachable,
        .auth_header = "unused",
        .connect_timeout_ms = 0,
        .execute_timeout_ms = null,
        .retry_policy = .{},
        .circuit_breaker = null,
    };
    // prevent deinit from free-ing unused literals
    _ = &client;

    const root = &Selection.root;
    const q: Query = .{
        .allocator = testing.allocator,
        .arena = arena.allocator(),
        .selection = root,
        .gql = &client,
    };

    const c1 = try q.container();
    const c2 = try c1.from("alpine:latest");
    const c3 = try c2.withExec(&.{ "echo", "hello" });

    // Add a terminal stdout to check the full shape.
    const terminal = try c3.selection.select(arena.allocator(), "stdout");

    const query_str = try terminal.build(testing.allocator);
    defer testing.allocator.free(query_str);

    try testing.expectEqualStrings(
        \\query{container{from(address:"alpine:latest"){withExec(args:["echo","hello"]){stdout}}}}
    , query_str);
}

test "walk to string leaf through single-key nested objects" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const json_str =
        \\{"container":{"from":{"withExec":{"stdout":"hello\n"}}}}
    ;
    const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, json_str, .{});
    defer parsed.deinit();

    const leaf = walkToStringLeaf(parsed.value).?;
    try testing.expectEqualStrings("hello\n", leaf);
}
