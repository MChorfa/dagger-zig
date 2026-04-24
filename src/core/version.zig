//! Pinned Dagger engine version. Matches the SKILL.md dagger-api-version.
//!
//! When bumping:
//!   1. Update `engine_version` here.
//!   2. Re-run `zig build codegen` against the new engine.
//!   3. Commit the regenerated `src/gen.zig`.
//!   4. Bump the SDK minor version.

pub const engine_version: [:0]const u8 = "v0.20.6";

/// SDK version for `--label dagger.io/sdk.version:x.y.z` metadata.
/// Kept in sync with build.zig.zon by hand (no file-embed in zon).
pub const sdk_version: [:0]const u8 = "0.1.0";

pub const sdk_name: []const u8 = "zig";
