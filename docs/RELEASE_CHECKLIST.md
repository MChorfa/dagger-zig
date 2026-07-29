# Release Checklist

Use this before cutting a tagged release.

## Scope

This checklist is for the current SDK line, not a historical version. The exact
tag changes from release to release, but the required checks stay the same.

## Before Tagging

- `git status` is clean or only contains intentional release changes.
- `zig build` succeeds.
- `zig build test` succeeds.
- `zig build test-module` succeeds.
- `zig build bench` succeeds.
- `zig build flamegraph` succeeds or is documented as optional if profiling is not available.
- `zig build test-suite` succeeds when the platform allows it.
- `docs/compliance.md` matches the current release pipeline.
- `README.md` and `docs/README.md` describe the same shipped features.
- Any deprecated claims have been removed from docs.

## Version Alignment

- `build.zig.zon` version matches the intended tag.
- `src/core/version.zig` matches the intended tag.
- Release notes or changelog entries exist for the new tag.

## Supply Chain

- SBOM generation runs in CI.
- SLSA provenance is attached to the release.
- GitHub attestation is attached to the release.
- Cosign signature and bundle are attached to the release.
- Release assets are uploaded for every supported target.

## Tagging

```bash
git tag -s v0.3.5 -m "Release v0.3.5"
git push origin v0.3.5
```

Replace `v0.3.5` with the next release tag when you are preparing a new cut.

## Post-Release

- Verify the GitHub release page has every expected asset.
- Verify provenance with `scripts/release-verify.sh <tag>`.
- Verify the changelog entry is linked from the release page.
- Confirm the docs landing page still matches the shipped behavior.

## Verification Commands

```bash
zig build
zig build test
zig build test-module
zig build bench
scripts/release-verify.sh v0.3.5
```
