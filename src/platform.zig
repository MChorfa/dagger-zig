//! Platform-specific abstractions for cross-platform compatibility.
//!
//! This module provides:
//! - Path separator normalization
//! - Shell execution wrappers
//! - File system operations that vary by OS

const std = @import("std");

/// Platform detection
pub const is_windows = @import("builtin").os.tag == .windows;
pub const is_posix = !is_windows;

/// Path separator for the current platform
pub const path_sep = if (is_windows) '\\' else '/';
pub const path_sep_str = if (is_windows) "\\" else "/";

/// Normalize a path string to use platform-native separators
pub fn normalizePath(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    if (is_posix) {
        // POSIX: just return a copy, forward slashes are native
        return allocator.dupe(u8, path);
    }

    // Windows: convert forward slashes to backslashes
    const normalized = try allocator.alloc(u8, path.len);
    for (path, 0..) |c, i| {
        normalized[i] = if (c == '/') '\\' else c;
    }
    return normalized;
}

/// Get the user's home directory
pub fn homeDir(allocator: std.mem.Allocator) ?[]u8 {
    if (is_windows) {
        const home = std.process.getEnvVarOwned(allocator, "USERPROFILE") catch return null;
        return home;
    } else {
        const home = std.process.getEnvVarOwned(allocator, "HOME") catch return null;
        return home;
    }
}

/// Get the default Dagger config directory
pub fn daggerConfigDir(allocator: std.mem.Allocator) !?[]u8 {
    const home = homeDir(allocator) orelse return null;
    defer allocator.free(home);

    const subdir = if (is_windows) "\\.dagger" else "/.dagger";
    const path = try std.fmt.allocPrint(allocator, "{s}{s}", .{ home, subdir });

    // Ensure directory exists
    std.fs.makeDirAbsolute(path) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    return path;
}

/// Shell command wrapper - handles platform differences
pub const Shell = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Shell {
        return .{ .allocator = allocator };
    }

    /// Execute a command and return output
    pub fn exec(self: Shell, cmd: []const []const u8) ![]u8 {
        if (is_windows) {
            // On Windows, use cmd.exe /c
            var args = std.ArrayList([]const u8).init(self.allocator);
            defer args.deinit();

            try args.append("cmd.exe");
            try args.append("/c");
            for (cmd) |arg| {
                try args.append(arg);
            }

            const result = try std.process.Child.run(.{
                .allocator = self.allocator,
                .argv = args.items,
            });

            if (result.term.Exited != 0) {
                self.allocator.free(result.stderr);
                self.allocator.free(result.stdout);
                return error.CommandFailed;
            }

            self.allocator.free(result.stderr);
            return result.stdout;
        } else {
            // POSIX: execute directly
            const result = try std.process.Child.run(.{
                .allocator = self.allocator,
                .argv = cmd,
            });

            if (result.term.Exited != 0) {
                self.allocator.free(result.stderr);
                self.allocator.free(result.stdout);
                return error.CommandFailed;
            }

            self.allocator.free(result.stderr);
            return result.stdout;
        }
    }
};

/// Environment variable name normalization
pub fn envVarName(comptime name: []const u8) []const u8 {
    // Windows is case-insensitive, but we preserve case
    // This function allows for platform-specific env var names if needed
    return name;
}

/// Get the platform-specific null device
pub const null_device = if (is_windows) "NUL" else "/dev/null";

/// Check if a file is executable (considers .exe extension on Windows)
pub fn isExecutable(path: []const u8) bool {
    if (is_windows) {
        const ext = std.fs.path.extension(path);
        return std.mem.eql(u8, ext, ".exe") or
            std.mem.eql(u8, ext, ".bat") or
            std.mem.eql(u8, ext, ".cmd");
    } else {
        // On POSIX, check execute permission via access
        std.posix.access(path, std.posix.X_OK) catch return false;
        return true;
    }
}

/// Join paths using platform separator
pub fn joinPath(allocator: std.mem.Allocator, parts: []const []const u8) ![]u8 {
    return try std.fs.path.join(allocator, parts);
}
