//! SPIFFE subsystem — public surface.
//!
//! ```zig
//! const spiffe = @import("dagger_sdk").spiffe;
//!
//! // v0.1.0: use the shellout backend
//! var shell = try spiffe.ShelloutSource.init(gpa, io, .{}, null);
//! defer shell.deinit();
//!
//! const src = shell.source(); // a SvidSource
//! var svid = try src.fetchX509SVID(gpa);
//! defer svid.deinit();
//! ```
//!
//! In v0.1.1, swap `ShelloutSource` for `NativeWorkloadAPISource`. No other
//! code changes. Same methods, same types, same error set.
//!
//! See `docs/SPIFFE.md` for integration patterns (Vault cert-auth, registry
//! credentials, etc.) and `docs/SPIFFE_IMPL.md` for the wire-level spec of
//! the native backend.

pub const SpiffeID = @import("spiffe_id.zig").SpiffeID;
pub const X509SVID = @import("svid.zig").X509SVID;
pub const JWTSVID = @import("svid.zig").JWTSVID;
pub const TrustBundle = @import("svid.zig").TrustBundle;

pub const source = @import("source.zig");
pub const SvidSource = source.SvidSource;
pub const SocketConfig = source.SocketConfig;
pub const Options = source.Options;

pub const ShelloutSource = @import("shellout.zig").ShelloutSource;
pub const NativeWorkloadAPISource = @import("native.zig").NativeWorkloadAPISource;

// Note: `integration.zig` (which wires SPIFFE SVIDs into Dagger
// Container.withRegistryAuth via Vault cert-auth) is deliberately NOT
// re-exported here. That file imports `../root.zig` and would pull the
// whole Dagger client into the SPIFFE graph — users who need it import
// it explicitly:
//
//     const spiffe_dagger = @import("dagger_sdk").spiffe_integration;

pub const errors = @import("errors.zig");
pub const SpiffeError = errors.SpiffeError;
//
// Keeps the core SPIFFE client usable as a standalone workload-identity
// library with zero Dagger coupling.
