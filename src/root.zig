//! # dagger-zig
//!
//! Zig SDK for the Dagger programmable CI/CD engine. Targets Zig 0.16+.
//!
//! ## Quick start (client only — calling existing modules)
//!
//! ```zig
//! const std = @import("std");
//! const dagger = @import("dagger_sdk");
//!
//! pub fn main(init: std.process.Init) !void {
//!     var client = try dagger.connect(init.gpa, init.io, .{});
//!     defer client.close();
//!
//!     const out = try client.dag()
//!         .container()
//!         .from("alpine:latest")
//!         .withExec(&.{ "echo", "hello from zig" })
//!         .stdout();
//!     defer init.gpa.free(out);
//!
//!     std.debug.print("{s}", .{out});
//! }
//! ```
//!
//! ## Authoring a module (v0.1 headline feature)
//!
//! ```zig
//! const std = @import("std");
//! const dagger = @import("dagger_sdk");
//!
//! const MyModule = struct {
//!     pub fn build(
//!         self: *MyModule,
//!         ctx: *dagger.Context,
//!         source: dagger.Directory,
//!     ) !dagger.Container {
//!         _ = self;
//!         return ctx.container()
//!             .from("golang:1.23-alpine")
//!             .withDirectory("/src", source)
//!             .withWorkdir("/src")
//!             .withExec(&.{ "go", "build", "-o", "/app", "./..." });
//!     }
//! };
//!
//! pub fn main(init: std.process.Init) !void {
//!     return dagger.module.serve(init, MyModule);
//! }
//! ```
//!
//! See `docs/ARCHITECTURE.md` for the full design.

const std = @import("std");

pub const errors = @import("errors.zig");
pub const querybuilder = @import("querybuilder.zig");
pub const core = struct {
    pub const connect_params = @import("core/connect_params.zig");
    pub const config = @import("core/config.zig");
    pub const engine = @import("core/engine.zig");
    pub const graphql_client = @import("core/graphql_client.zig");
    pub const cli_session = @import("core/cli_session.zig");
    pub const version = @import("core/version.zig");
};

/// Module authoring subsystem. See `src/module/` for the dispatch,
/// TypeDef builder, server loop, and (de)serialization.
pub const module = @import("module/mod.zig");

/// SPIFFE/SPIRE subsystem — Workload API client, SVID types, and helpers
/// for authenticating to external services (Vault, registries, etc.) with
/// short-lived workload identities. See `src/spiffe/mod.zig`.
///
/// v0.1.0 ships with a working `ShelloutSource` backend. v0.1.1 ships
/// with `NativeWorkloadAPISource` — pure-Zig gRPC, zero subprocess dep.
/// Same interface either way.
pub const spiffe = @import("spiffe/mod.zig");

/// Opt-in SPIFFE-to-Dagger glue (`spiffeRegistryAuth`, Vault cert-auth
/// provider). Separate from `spiffe` to keep the SPIFFE client usable as
/// a standalone library without pulling in the Dagger core dep graph.
pub const spiffe_integration = @import("spiffe/integration.zig");

pub const Config = core.config.Config;
pub const Logger = core.config.Logger;
pub const StdLogger = core.config.StdLogger;

// Re-export the generated (hand-written for now) API.
pub const api = @import("gen_sample.zig");

/// Engine-side API used by the module runtime: `currentFunctionCall`,
/// handle loaders (`loadContainerFromID`, etc.). Advanced users can call
/// these directly; typical module authors don't need to.
pub const module_api = @import("module_api.zig");

pub const Query = api.Query;
pub const Container = api.Container;
pub const Directory = api.Directory;
pub const File = api.File;
pub const Secret = api.Secret;
pub const CacheVolume = api.CacheVolume;
pub const ContainerID = api.ContainerID;
pub const DirectoryID = api.DirectoryID;
pub const FileID = api.FileID;
pub const SecretID = api.SecretID;
pub const CacheVolumeID = api.CacheVolumeID;

/// A live Dagger client. Holds:
///   - the subprocess (if we spawned one)
///   - the GraphQL HTTP client (carries the user's Io)
///   - an arena for the selection chain
///
/// Thread-safety: each client is not internally synchronised, but because
/// its operations go through `std.Io`, fan-out is done by the user via
/// `io.async`/`Group` — not by sharing the client. If you need parallel
/// queries, construct multiple clients OR share one client across tasks
/// where each task uses the client sequentially (this works because the
/// engine itself multiplexes concurrent requests over the same HTTP
/// connection).
pub const Client = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    params: core.connect_params.ConnectParams,
    session: ?core.cli_session.SessionProc,
    gql: core.graphql_client.GraphQLClient,
    arena: std.heap.ArenaAllocator,

    /// Get the root `Query` for building pipelines.
    pub fn dag(self: *Client) Query {
        return .{
            .allocator = self.allocator,
            .arena = self.arena.allocator(),
            .selection = &querybuilder.Selection.root,
            .gql = &self.gql,
        };
    }

    /// Tear down the session. Idempotent.
    pub fn close(self: *Client) void {
        if (self.session) |*s| {
            s.shutdown() catch |e| {
                std.debug.print("dagger: session shutdown failed: {s}\n", .{@errorName(e)});
            };
            self.session = null;
        }
        self.gql.deinit();
        self.params.deinit(self.allocator);
        self.arena.deinit();
    }

    /// Reset the internal arena, reclaiming memory while retaining the buffer capacity.
    /// Call this periodically for long-running clients to prevent unbounded memory growth.
    /// Only safe when no queries are in progress.
    pub fn resetArena(self: *Client) void {
        _ = self.arena.reset(.retain_capacity);
    }
};

/// Connect to a Dagger engine using the caller-supplied allocator and Io.
///
/// `io` must outlive the returned client. Typically you pass `init.io` from
/// `std.process.Init` (Juicy Main).
pub fn connect(
    allocator: std.mem.Allocator,
    io: std.Io,
    cfg: Config,
) !Client {
    const start = try core.engine.start(allocator, io, cfg);
    var gql = try core.graphql_client.GraphQLClient.init(allocator, io, start.params, cfg);
    errdefer gql.deinit();

    return .{
        .allocator = allocator,
        .io = io,
        .params = start.params,
        .session = start.session,
        .gql = gql,
        .arena = std.heap.ArenaAllocator.init(allocator),
    };
}

test {
    std.testing.refAllDecls(@This());
}
