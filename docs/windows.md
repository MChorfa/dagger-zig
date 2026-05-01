# Windows Support

> **Status:** v0.2.0 — Experimental but functional. Report issues on GitHub.

dagger-zig supports Windows as a build target and development platform. This guide covers Windows-specific considerations.

## Quick Start (Windows)

Prerequisites:
- Zig 0.16.0+ for Windows
- Git for Windows
- Dagger CLI (Windows build from [releases](https://github.com/dagger/dagger/releases))

```powershell
# Clone and build
git clone https://github.com/MChorfa/dagger-zig.git
cd dagger-zig
zig build

# Run tests
zig build test
```

## Platform Differences

### Socket Types

| Platform         | Default                      | Notes                |
| ---------------- | ---------------------------- | -------------------- |
| Linux/macOS      | Unix domain socket           | Full feature support |
| Windows 10 1803+ | Unix domain socket (AF_UNIX) | When available       |
| Windows <1803    | Named pipes                  | Fallback transport   |
| All platforms    | TCP loopback                 | Emergency fallback   |

### Path Handling

Windows uses different path conventions:

```zig
// Cross-platform path building
const cache_path = try std.fs.path.join(allocator, &.{ cache_dir, "layer.tar.gz" });
// Windows: C:\Users\...\AppData\Local\...\layer.tar.gz
// Linux: /home/.../.cache/.../layer.tar.gz
```

### Container Runtime

On Windows, Dagger uses either:
- **WSL2 backend** (recommended): Linux containers via WSL2
- **Windows containers**: Native Windows container support (limited)

The SDK itself is agnostic to the container runtime — it communicates via the Dagger engine's GraphQL API.

## Building for Windows

### Native Build (Windows host)

```powershell
zig build
```

### Cross-compilation from Linux/macOS

```bash
# Windows x86_64 (GNU ABI)
zig build -Dtarget=x86_64-windows-gnu

# Windows x86_64 (MSVC ABI — requires Windows headers)
zig build -Dtarget=x86_64-windows-msvc
```

### CI Matrix

The GitHub Actions workflow tests Windows builds:

```yaml
strategy:
  matrix:
    os: [ubuntu-latest, windows-latest, macos-latest]
```

## Known Limitations

1. **Unix socket paths**: On Windows, socket paths are limited to ~260 characters (MAX_PATH). The SDK handles this by
   using shorter temp directory paths.

2. **Signal handling**: Windows doesn't support Unix signals. The SDK uses `GenerateConsoleCtrlEvent` for subprocess management.

3. **File permissions**: Windows ACLs don't map 1:1 to Unix permissions. Container `withExec` operations that rely on
   specific permissions may behave differently.

4. **Line endings**: Git's `core.autocrlf` can cause issues with scripts inside containers. Use `.gitattributes` to
   force LF:

```gitattributes
* text=auto eol=lf
*.zig text eol=lf
```

## Debugging on Windows

Enable debug logging:

```zig
var client = try dagger.connect(allocator, io, .{
    .logger = .{ .level = .debug },
});
```

Check the Dagger engine logs:

```powershell
# With Dagger CLI
dagger run --debug -- zig build run-first-pipeline
```

## Troubleshooting

### "Connection refused" errors

Usually means the Dagger CLI session isn't active:

```powershell
# Start a session first
dagger run -- powershell
then run your commands
```

### Long path issues

Enable Windows long path support:

```powershell
# Run as Administrator
New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" `
  -Name "LongPathsEnabled" -Value 1 -PropertyType DWORD -Force
```

### WSL2 vs Windows containers

The SDK doesn't directly control this, but your Dagger engine setup does. Check your Dagger context:

```powershell
dagger context list
dagger context use wsl-engine  # or docker-engine, etc.
```

## Testing

Run the full test suite on Windows:

```powershell
# Unit tests (no Dagger session required)
zig build test

# Module E2E tests
zig build test-module

# Integration tests (requires Dagger session)
dagger run -- zig build test-integration
```

## See Also

- [Main README](../README.md) — General quickstart
- [ARCHITECTURE.md](./ARCHITECTURE.md) — Design details
- [Dagger Windows docs](https://docs.dagger.io) — Upstream Windows support
