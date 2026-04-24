# Roadmap

## v0.1.0 — shipping now (RC)

The "we self-host" release. If `dagger call ci --source=.` passes, this
version is verified. Includes production-grade resilience and security.

- [x] Zig 0.16 native (std.Io everywhere, Juicy Main)
- [x] **Resilience patterns** — retry with exponential backoff + jitter, circuit breaker
- [x] **Cache fail-safe** — 4-tier policies (disabled/auto/required/read_only), graceful degradation
- [x] **Secret management** — secure memory, automatic log scrubbing, audit trails
- [x] Immutable querybuilder with arena-owned Selection chain
- [x] GraphQL client, three-tier CLI handshake, subprocess lifecycle
- [x] Hand-written API for Container, Directory, File, Secret, CacheVolume
- [x] C ABI (libdagger.{a,so,dylib} + header) — tested offline
- [x] Codegen emitter (scaffold; full coverage deferred)
- [x] Module authoring: comptime TypeDef mapping, dispatch table,
      specialized invoker shims, serde for args/returns, `serve()`
- [x] SPIFFE ID parser + SVID types + SvidSource vtable
- [x] Shellout SPIFFE backend (v0.1.0 working backend)
- [x] Native SPIFFE skeleton returning NotImplementedInV010 on network ops
- [x] Self-hosting `ci/main.zig` — Zig Dagger module that builds dagger-zig
- [x] Module SDK interface in `sdk/main.go` — the bootstrap layer
- [x] Offline module-runtime E2E test proving comptime plumbing

Known `NotImplementedInV010` in v0.1.0:

- `ShelloutSource.fetchX509SVID` → subprocess runs, DER parser is stub
- `ShelloutSource.fetchJWTSVID` / `fetchX509Bundle` → entirely stub
- `NativeWorkloadAPISource` all network ops
- `spiffe_integration.spiffeRegistryAuth` + `VaultCertAuthProvider`

## v0.1.1 — SPIFFE becomes real

Dependency bump for users. No source changes required.

- [ ] Pure-Zig HTTP/2 subset per `docs/SPIFFE_IMPL.md` (~800 LOC)
- [ ] gRPC length-prefix framing + status trailers (~200 LOC)
- [ ] Hand-transcribed protobuf codec for 9 Workload API messages (~400 LOC)
- [ ] X.509 DER chain parsing + PKCS#8 key parsing via `std.crypto.Certificate`
- [ ] Trust-domain pinning enforcement (already in Options; backend wires it)
- [ ] Vault cert-auth client (shares TLS layer with native SPIFFE)
- [ ] Full fixture-based test suite (bytes captured from real SPIRE agent)
- [ ] Shellout backend's DER parser lands too (shares cert parsing code)

## v0.2 — production-grade client

The resilience foundation laid in v0.1.0 enables this level of reliability.

- [ ] Complete codegen coverage
  - [ ] All scalar argument types (int/float/boolean/enum)
  - [ ] List-of-object arguments via lazy ID resolution batching
  - [ ] Optional args with GraphQL default-value handling
  - [ ] Object-list return types
- [ ] Lazy ID resolution via GraphQL variables
- [ ] Multi-field selection sets in querybuilder (current linear-chain
      limit; drop the raw-GraphQL escape hatch in `module_api.fetchArgList`)
- [ ] Streaming stdout/stderr for long-running containers
- [ ] Proper `DomainError` extensions parsing (path + locations)
- [ ] Connection-pool reuse across client instances
- [ ] `Container.directory(path)` + `Container.file(path)` → unblocks
      `ci.cLib` returning a Directory, which lights up `c_smoke` / `matrix`
- [ ] Real per-module codegen in `sdk/codegen/` (restrict schema to user deps)

## v0.3 — meta-SDK rewrite

- [ ] Replace `sdk/main.go` with `sdk/main.zig`. Safe by this point
      because v0.1–v0.2 prove the module runtime in production. Removes
      the last non-Zig line from the distribution.
- [ ] Pre-compiled module binaries as OCI artifacts → cold start <1s
- [ ] Conformance: `zig build test-conformance` runs the Rust SDK
      querybuilder suite verbatim and asserts byte-equality

## v1.0 — API stability

- [ ] Freeze public API (`Client`, `Query`, module authoring surface)
- [ ] Semver: breaking changes only on major bumps
- [ ] Published to Zig package registry (whichever wins)
- [ ] Upstream: propose as official Dagger community SDK

## Deliberately not on the roadmap

- **Browser/WASM target.** Dagger needs a localhost subprocess.
- **Alternative transport (Unix socket direct).** Engine exposes HTTP only.
- **Built-in LLM provider.** Dagger's `LLM` type handles this already.
- **Async-runtime swap-out.** `std.Io` is the runtime; Zig made the choice.
