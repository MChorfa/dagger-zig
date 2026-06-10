# Changelog

## [0.3.2](https://github.com/MChorfa/dagger-zig/compare/v0.3.1...v0.3.2) (2026-06-09)

### Features

- **bench:** add real offline `zig build bench` step — query-builder and serialization throughput ([28e1349](https://github.com/MChorfa/dagger-zig/commit/28e1349dc10550c313dea4d26316ad761deacc61))
- **bench:** print per-stage breakdown to the terminal ([fbbf6a8](https://github.com/MChorfa/dagger-zig/commit/fbbf6a88d0783727229d1815b3acebac0dce7db5))
- **bench:** add `zig build flamegraph` target (external profiler, fails loud if tooling absent) ([9d7413b](https://github.com/MChorfa/dagger-zig/commit/9d7413b2c2ddb0b02f151458617a98b9cd439963))
- **parallel:** real concurrency via `std.Io.Group` + `Client.branch()` ([0565bec](https://github.com/MChorfa/dagger-zig/commit/0565bec04c49a8d0c3ac0d02936f146ad11a8281))
- **ci:** SLSA v1 provenance, Syft SBOM (CycloneDX + SPDX), Cosign keyless attestation, OPA/Rego governance gate ([94b4b5d](https://github.com/MChorfa/dagger-zig/commit/94b4b5de553385c0cb03c14451d58705374c5ba6))

### Bug Fixes

- **zig-0.16:** replace removed `std.time` timestamp APIs with `std.c.clock_gettime(CLOCK.MONOTONIC)` in telemetry and test suite ([be80542](https://github.com/MChorfa/dagger-zig/commit/be80542a921512b147a510493b5cab7c4350e57f))
- **zig-0.16:** fix removed `std.Io.Threaded.init_single_threaded` → `.init(gpa, .{})` with `defer deinit()` in bench ([be80542](https://github.com/MChorfa/dagger-zig/commit/be80542a921512b147a510493b5cab7c4350e57f))
- **test-suite:** fix phantom error types (`errors.ClientError`, `ConnectionFailed`, `QueryFailed`) → correct `errors.QueryError` / `HandshakeFailed` / `TransportFailed` members ([be80542](https://github.com/MChorfa/dagger-zig/commit/be80542a921512b147a510493b5cab7c4350e57f))

### Documentation

- **why-zig:** remove unverified comparative claims ([29c86cf](https://github.com/MChorfa/dagger-zig/commit/29c86cf20f57a375beebaffcc5a788ab541b3633))

---

## [0.2.1] (2026-05-27)

### Bug Fixes

- **compatibility:** Fix type mismatch in SDK bootstrap layer - `dag.GeneratedCode()` now expects `*dagger.Directory` instead of `*dagger.Changeset` for Dagger CLI versions > v0.12.5
- **sdk/main.go:** Updated Codegen function to pass Directory directly to GeneratedCode constructor
- **repository:** Fix all repository references from ckodex/dagger-zig to MChorfa/dagger-zig
- **docs:** Fix Font Awesome icon and action version in documentation workflow
- **zig:** Update server.zig for Zig 0.16 ArrayList and Writer compatibility

## [0.2.0](https://github.com/MChorfa/dagger-zig/compare/v0.1.2...v0.2.0) (2026-05-02)

### Features

- Address all SDK gaps - Phase 1 & 2 ([a7d2879](https://github.com/MChorfa/dagger-zig/commit/a7d28795b4c9fbffcf9491142cc0a1054a6b713e))
- **api:** add comprehensive Container methods ([7aa4e50](https://github.com/MChorfa/dagger-zig/commit/7aa4e508d9d89e061eb9d2bb91858d4d2f4ed427))
- **api:** add Service, GitRepository, GitRef, Host, Socket types ([434f37d](https://github.com/MChorfa/dagger-zig/commit/434f37d4524f97d3b976f390fcb433f2aa31d155))
- **dev:** add VS Code IDE configuration ([f4bca03](https://github.com/MChorfa/dagger-zig/commit/f4bca03a15d0ead9f96ad4d86888f56d8029a2f0))
- **docs:** Phase 1 - new examples, IDE setup, migration guide, why-zig doc ([c25617c](https://github.com/MChorfa/dagger-zig/commit/c25617c2b602e776aa139422ee1ecf69d10278b0))
- **phase3:** add Windows support and observability ([4657901](https://github.com/MChorfa/dagger-zig/commit/4657901494d2f84bdd716680a1a610aed6998c36))
- **phase4:** add comprehensive test suite ([81a01b7](https://github.com/MChorfa/dagger-zig/commit/81a01b780cc173d00e6d3603d1ccade50c354b0e))

### Bug Fixes

- **build:** add link_libc to all modules using dagger_sdk ([3b7c55d](https://github.com/MChorfa/dagger-zig/commit/3b7c55d220999167d90391f6a7d699613d87539a))
- **ci:** correct security claims and add OpenSSF Scorecard ([92e5000](https://github.com/MChorfa/dagger-zig/commit/92e5000a08b12c9b8cb30f34c1e83d5be279ab4f))
- **ci:** make workflows work without secrets ([a6633f1](https://github.com/MChorfa/dagger-zig/commit/a6633f19417bc6389bae6dd675184003cad96eeb))
- **ci:** update all workflows to work without secrets ([1f136f0](https://github.com/MChorfa/dagger-zig/commit/1f136f02401ceddd2efbc3952564cbcf390bad54))
- **docs:** correct book.toml configuration ([2b0f3d9](https://github.com/MChorfa/dagger-zig/commit/2b0f3d9a36b27ade3cab4ebc9ce07768d8c4e8e0))
- **examples:** resolve error union chaining and add missing API methods ([ea6a75f](https://github.com/MChorfa/dagger-zig/commit/ea6a75f2f35f89228ef43b99887c4e4530d0c011))
- **release:** add tag trigger support for manual releases ([b9f3fbd](https://github.com/MChorfa/dagger-zig/commit/b9f3fbd1e08aa1d19789d7f85eb38b9654522486))
- **release:** add tag trigger support for manual releases ([c1bc1f4](https://github.com/MChorfa/dagger-zig/commit/c1bc1f402743cd19be44f424cbd4c85ca6107134))
- **release:** address v0.2.0 critical blockers ([0b4170b](https://github.com/MChorfa/dagger-zig/commit/0b4170b293a26e884ca81ff5c978e0b976f6a8a5))
- **release:** package binaries, libs, and headers with checksums ([7c875a0](https://github.com/MChorfa/dagger-zig/commit/7c875a0f482077f684e934455575cedf33b6c48a))
- **release:** package binaries, libs, and headers with checksums ([6e70fa3](https://github.com/MChorfa/dagger-zig/commit/6e70fa343c76b0b42e213d0ed585a24cb574f015))
- **review:** address all PR review comments ([f33e1c8](https://github.com/MChorfa/dagger-zig/commit/f33e1c8d6ab3827d648000eafa8f5d4c71369d9d))
- **review:** address parallel_validation feedback in tracing.zig ([ca19188](https://github.com/MChorfa/dagger-zig/commit/ca1918888a9223c4f2ca7b6fc5174733f104fd9e))
- **scorecard:** add continue-on-error to tolerate findings ([30a20d3](https://github.com/MChorfa/dagger-zig/commit/30a20d3d9be943108e4a9f5c6239bb2cd974dfe3))
- **scorecard:** tolerate findings with continue-on-error ([ec94664](https://github.com/MChorfa/dagger-zig/commit/ec94664b8c78def97b7564689b1cbb1ab137cdbe))
- **security:** only upload Grype SARIF on success ([6765506](https://github.com/MChorfa/dagger-zig/commit/676550610e3bba90166f34516a6fdec441733a28))
- **security:** only upload Grype SARIF on success ([204448b](https://github.com/MChorfa/dagger-zig/commit/204448bfa03d483f954c86ae8ad95406cd1f4c50))
- **security:** update CodeQL to use C language and refresh CI workflows ([ef0a509](https://github.com/MChorfa/dagger-zig/commit/ef0a509106af8ab83d310f5db1038417633604da))
- **slsa:** update Zig version from 0.13.0 to 0.16.0 ([2851002](https://github.com/MChorfa/dagger-zig/commit/285100224984920e3265cc7a25d68d10888b3360))
- type mismatch in GeneratedCode constructor for CLI &gt; v0.12.5 ([#25](https://github.com/MChorfa/dagger-zig/issues/25)) ([77a4cff](https://github.com/MChorfa/dagger-zig/commit/77a4cffaeee485a3b69d5e3be19f99345e85403e))
- **v0.2.0:** address critical release blockers ([868b5dd](https://github.com/MChorfa/dagger-zig/commit/868b5dd6e0ab889a61f4748113dd09f1d65dd8bc))
- **workflows:** add continue-on-error and fix security configs ([619903d](https://github.com/MChorfa/dagger-zig/commit/619903d63f8792d07e833e026b7c11dfe91d130a))
- **workflows:** correct all GitHub Action SHAs ([3657270](https://github.com/MChorfa/dagger-zig/commit/365727050af5244893d0ff7df7f87c263e916e50))
- **workflows:** correct remaining action SHAs ([dcdab29](https://github.com/MChorfa/dagger-zig/commit/dcdab299530e32d36c94ac31b5f6dce4d57e1133))
- **workflows:** remove continue-on-error, add debug output ([7dc3463](https://github.com/MChorfa/dagger-zig/commit/7dc34632271a717b5549b11a4176ba5d33e7d088))
- **workflows:** revert to Zig 0.16.0, fix benchmark step ([29130f8](https://github.com/MChorfa/dagger-zig/commit/29130f8eaed6795e1687c0dbcc31ea07860fab2a))
- **workflows:** update to Zig 0.16.1, add verification steps ([7f52a3d](https://github.com/MChorfa/dagger-zig/commit/7f52a3d4495a0fcb3ae511bf9ef166c3f2ba61e7))
- **workflows:** use dagger run instead of dagger call -m ci ([a43465d](https://github.com/MChorfa/dagger-zig/commit/a43465d91ffc0c3d7392851963e235170a20e49c))
- **workflows:** use native Zig instead of Dagger ([a4c026f](https://github.com/MChorfa/dagger-zig/commit/a4c026f8ec94bffa058ab81148f53400721f31b8))
- **workflows:** use Zig 0.17.0 (0.16.1 doesn't exist) ([b67c5f7](https://github.com/MChorfa/dagger-zig/commit/b67c5f76011cd415103faaf64e1a1bba47945d2b))

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
