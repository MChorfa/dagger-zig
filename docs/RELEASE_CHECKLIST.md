# v0.2.0 Release Checklist

Complete all items before tagging v0.2.0.

## Pre-Release Verification

### Build & Test

- [ ] Clean build succeeds: `zig build`
- [ ] Tests pass without SPIFFE: `zig build test`
- [ ] Tests pass with SPIFFE: `zig build test -Dspiffe-experimental`
- [ ] Module E2E tests pass: `zig build test-module`
- [ ] C library builds: `zig build c-lib`
- [ ] All examples build: `zig build run-first-pipeline` (and others)

### Cross-Platform

- [ ] Linux x86_64 build: `zig build -Dtarget=x86_64-linux-gnu`
- [ ] Linux aarch64 build: `zig build -Dtarget=aarch64-linux-gnu`
- [ ] macOS x86_64 build: `zig build -Dtarget=x86_64-macos-none`
- [ ] macOS aarch64 build: `zig build -Dtarget=aarch64-macos-none`
- [ ] Windows build: `zig build -Dtarget=x86_64-windows-gnu`

### Version Alignment

- [ ] `build.zig.zon` version is `0.2.0`
- [ ] `src/core/version.zig` sdk_version is `0.2.0`
- [ ] `src/core/version.zig` VERSION_MINOR is `2`

### Documentation

- [ ] README.md reflects v0.2.0 features
- [ ] ROADMAP.md shows v0.2.0 items as complete
- [ ] CHANGELOG.md has v0.2.0 entry
- [ ] docs/spiffe.md has experimental warning
- [ ] docs/windows.md exists and is accurate

## Release Process

### 1. Finalize Code

```bash
# Ensure clean working directory
git status

# Run final tests
zig build test
zig build test-module
```

### 2. Update Changelog

Create CHANGELOG.md entry for v0.2.0:

```markdown
## [0.2.0] - YYYY-MM-DD

### Added

- Windows support (cross-compilation and native builds)
- SPIFFE experimental feature flag (`-Dspiffe-experimental`)
- Cross-platform CI matrix (Linux, macOS, Windows)
- Documentation for Windows builds

### Changed

- SPIFFE/SPIRE support now requires explicit opt-in via build flag
- SDK version bumped to 0.2.0

### Security

- Supply chain: SLSA provenance attestation
- Supply chain: Cosign signing of SBOM and artifacts
```

### 3. Create Signed Tag

```bash
# Create annotated and signed tag
git tag -s v0.2.0 -m "Release v0.2.0 - Cross-platform production release"

# Push tag (triggers release workflow)
git push origin v0.2.0
```

### 4. Verify GitHub Release

- [ ] Release workflow triggered automatically
- [ ] All matrix builds completed successfully
- [ ] Artifacts uploaded:
  - [ ] `dagger-zig-x86_64-linux-gnu.tar.gz`
  - [ ] `dagger-zig-aarch64-linux-gnu.tar.gz`
  - [ ] `dagger-zig-x86_64-macos-none.tar.gz`
  - [ ] `dagger-zig-aarch64-macos-none.tar.gz`
- [ ] SBOM generated: `sbom.spdx.json`
- [ ] SBOM signature: `sbom.spdx.json.sig`

### 5. Verify SLSA Provenance

```bash
# Download attestation from GitHub release
gh release download v0.2.0 -p '*.intoto.jsonl'

# Verify using slsa-verifier (install from https://github.com/slsa-framework/slsa-verifier)
slsa-verifier verify-artifact \
  --provenance-path dagger-zig-x86_64-linux-gnu.intoto.jsonl \
  --source-uri github.com/MChorfa/dagger-zig \
  --source-tag v0.2.0 \
  dagger-zig-x86_64-linux-gnu.tar.gz
```

### 6. Verify Cosign Signature

```bash
# Download signature and certificate from release
gh release download v0.2.0 -p 'sbom.spdx.json.sig'
gh release download v0.2.0 -p 'sbom.spdx.json.cert'

# Verify with cosign
cosign verify-blob \
  --signature sbom.spdx.json.sig \
  --certificate sbom.spdx.json.cert \
  --certificate-identity-regexp 'MChorfa/dagger-zig' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  sbom.spdx.json
```

### 7. Post-Release

- [ ] Close v0.2.0 milestone on GitHub
- [ ] Announce on relevant channels
- [ ] Update documentation site (if separate)

## Rollback Procedure

If critical issues are found:

```bash
# Delete tag locally and remotely (use with caution)
git push --delete origin v0.2.0
git tag --delete v0.2.0

# Create v0.2.1 hotfix following same checklist
```

## Verification Commands Summary

```bash
# Build verification
zig build -Doptimize=ReleaseSafe

# Test verification
zig build test
zig build test-module

# Cross-compilation verification
for target in x86_64-linux-gnu aarch64-linux-gnu x86_64-macos-none aarch64-macos-none; do
  echo "Building for $target..."
  zig build -Dtarget=$target -Doptimize=ReleaseSafe || exit 1
done

# Version verification
grep version build.zig.zon
grep sdk_version src/core/version.zig
```
