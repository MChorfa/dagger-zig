# Changelog

## [0.2.1] (2026-05-27)

### Bug Fixes

- **compatibility:** Fix type mismatch in SDK bootstrap layer - `dag.GeneratedCode()` now expects `*dagger.Directory` instead of `*dagger.Changeset` for Dagger CLI versions > v0.12.5
- **sdk/main.go:** Updated Codegen function to pass Directory directly to GeneratedCode constructor

## [0.2.0](https://github.com/MChorfa/dagger-zig/compare/v0.1.2...v0.2.0) (2026-05-02)

### Features

- Address all SDK gaps - Phase 1 & 2 ([a7d2879](https://github.com/MChorfa/dagger-zig/commit/a7d28795b4c9fbffcf9491142cc0a1054a6b713e))
- **SPIFFE:** Experimental support now behind `-Dspiffe-experimental` build flag
- **Windows:** Full cross-compilation support for Windows targets
- **CI:** Multi-platform CI matrix (Linux, macOS, Windows)
- **Docs:** Windows-specific build and usage guide

### Bug Fixes

- **examples:** resolve error union chaining and add missing API methods ([ea6a75f](https://github.com/MChorfa/dagger-zig/commit/ea6a75f2f35f89228ef43b99887c4e4530d0c011))
- **release:** address v0.2.0 critical blockers ([0b4170b](https://github.com/MChorfa/dagger-zig/commit/0b4170b293a26e884ca81ff5c978e0b976f6a8a5))
- **review:** address all PR review comments ([f33e1c8](https://github.com/MChorfa/dagger-zig/commit/f33e1c8d6ab3827d648000eafa8f5d4c71369d9d))
- **review:** address parallel_validation feedback in tracing.zig ([ca19188](https://github.com/MChorfa/dagger-zig/commit/ca1918888a9223c4f2ca7b6fc5174733f104fd9e))
- **slsa:** update Zig version from 0.13.0 to 0.16.0 ([2851002](https://github.com/MChorfa/dagger-zig/commit/285100224984920e3265cc7a25d68d10888b3360))
- **v0.2.0:** address critical release blockers ([868b5dd](https://github.com/MChorfa/dagger-zig/commit/868b5dd6e0ab889a61f4748113dd09f1d65dd8bc))

### Changes

- SPIFFE/SPIRE support is now opt-in via build flag (reduces default binary size)
- SDK version bumped to 0.2.0

### Security

- SLSA provenance attestation for all release artifacts
- Cosign signing of SBOM and release artifacts
- Verified supply chain security through GitHub Actions

## [0.1.2](https://github.com/MChorfa/dagger-zig/compare/v0.1.1...v0.1.2) (2026-04-25)

### Bug Fixes

- **release:** add tag trigger support for manual releases ([b9f3fbd](https://github.com/MChorfa/dagger-zig/commit/b9f3fbd1e08aa1d19789d7f85eb38b9654522486))
- **release:** add tag trigger support for manual releases ([c1bc1f4](https://github.com/MChorfa/dagger-zig/commit/c1bc1f402743cd19be44f424cbd4c85ca6107134))

## [0.1.1](https://github.com/MChorfa/dagger-zig/compare/v0.1.0...v0.1.1) (2026-04-25)

### Bug Fixes

- **release:** package binaries, libs, and headers with checksums ([7c875a0](https://github.com/MChorfa/dagger-zig/commit/7c875a0f482077f684e934455575cedf33b6c48a))
- **release:** package binaries, libs, and headers with checksums ([6e70fa3](https://github.com/MChorfa/dagger-zig/commit/6e70fa343c76b0b42e213d0ed585a24cb574f015))
- **scorecard:** add continue-on-error to tolerate findings ([30a20d3](https://github.com/MChorfa/dagger-zig/commit/30a20d3d9be943108e4a9f5c6239bb2cd974dfe3))
- **scorecard:** tolerate findings with continue-on-error ([ec94664](https://github.com/MChorfa/dagger-zig/commit/ec94664b8c78def97b7564689b1cbb1ab137cdbe))
- **security:** only upload Grype SARIF on success ([6765506](https://github.com/MChorfa/dagger-zig/commit/676550610e3bba90166f34516a6fdec441733a28))
- **security:** only upload Grype SARIF on success ([204448b](https://github.com/MChorfa/dagger-zig/commit/204448bfa03d483f954c86ae8ad95406cd1f4c50))
