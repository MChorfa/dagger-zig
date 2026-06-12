# Windows Support

Windows is supported as a build target, but it is not the primary shipped
runtime path.

## Status

- Windows appears in the build matrix
- Core filesystem and path handling are cross-platform
- Some engine/session behaviors are still less exercised than Linux/macOS
- SPIFFE, C ABI, and other experimental paths should not be assumed ready on Windows

## What Works

- Building the SDK on Windows
- Running the offline test suite
- Cross-platform path joins
- Generated API usage that stays within supported Zig abstractions

## What Needs Care

- Long paths
- Shell quoting
- Line endings in scripts
- Any workflow that assumes a Unix-only transport or environment

## Build

```powershell
zig build
zig build test
zig build test-module
```

## Notes

- Prefer short checkout paths.
- Keep `.gitattributes` enforcing LF for Zig and shell scripts.
- When debugging workflow failures, compare Windows behavior against Linux/macOS
  instead of assuming the same environment.

## Related Pages

- [Architecture](architecture.md)
- [Roadmap](roadmap.md)
- [Local CI Testing](local-ci-testing.md)
