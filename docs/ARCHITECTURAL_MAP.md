# dagger-zig Architectural Documentation

**Version**: v0.1.0-RC  
**Date**: 2026-04-24

---

## Overview

This SDK provides a native Zig interface to the Dagger CI/CD engine. The architecture follows structured separation of concerns:

1. **Operational observability** — All operations produce metrics and audit trails
2. **Security hardening** — Automatic secret scrubbing and secure memory handling
3. **Self-hosting validation** — CI pipeline uses the SDK itself for verification

---

## Architectural Layers

```mermaid
---
config:
  theme: neo
  layout: elk
  look: neo
---
flowchart TB
    subgraph Presentation["PRESENTATION SPACE — User-facing API"]
        Container["Container (fluent)"]
        Directory["Directory (fluent)"]
        File["File (fluent)"]
        SecretVol["Secret/CacheVolume (opaque IDs)"]
        QueryBuilder["QueryBuilder (immutable Selection chains)<br/>• Type-safe GraphQL via comptime<br/>• Arena-owned, zero-copy"]
    end

    subgraph Validation["VALIDATION SPACE — Resilience, Cache, Secrets"]
        Resilience["ResilientExecutor<br/>• Retry policy<br/>• Circuit breaker<br/>• Jitter/backoff"]
        Cache["CacheFailSafe<br/>• 4-tier policy<br/>• Fallback<br/>• Health metrics"]
        Secrets["SecretRegistry/Scrubber<br/>• Secure memory<br/>• Auto-scrub logs<br/>• Audit trails"]
        Config["Config (timeouts, logging, feature flags)"]
    end

    subgraph Kernel["KERNEL SPACE — Core Domain Logic"]
        GraphQLClient["GraphQLClient<br/>• HTTP transport via std.Io<br/>• JSON serialization<br/>• Error extraction"]
        Engine["Engine/CLI Session<br/>• Three-tier handshake<br/>• Subprocess lifecycle<br/>• Async pipe drainage"]
    end

    subgraph Infrastructure["INFRASTRUCTURE — Module Runtime & SPIFFE"]
        subgraph Module["Module Authoring"]
            TypeDef["TypeDef (comptime)"]
            Dispatch["Dispatch (vtable)"]
            Server["Server (serve())"]
            Serde["Serde (JSON)"]
        end
        subgraph SPIFFE["SPIFFE/SPIRE"]
            SVIDTypes["SVID Types"]
            SourceAPI["Source API (vtable)"]
            Shellout["Shellout Backend<br/>(v0.1.0 working)"]
            Native["Native gRPC<br/>(v0.1.1 planned)"]
        end
    end

    subgraph Interface["INTERFACE SPACE — FFI & C ABI"]
        CAPI["C API (libdagger.{a,so,dylib})<br/>• Handle-based memory<br/>• Thread-local errors<br/>• Arena reset"]
    end

    Presentation --> Validation
    Validation --> Kernel
    Kernel --> Infrastructure
    Infrastructure --> Interface
```

---

## Module Dependency Graph

```mermaid
---
config:
  theme: neo
  layout: elk
  look: neo
---
flowchart TB
    Root["src/root.zig<br/>Public API"]

    subgraph Core["core/*.zig — Client Kernel"]
        Config["config.zig"]
        Engine["engine.zig"]
        GraphQL["graphql_client.zig"]
        CLISession["cli_session.zig"]
        Resilience["resilience.zig"]
        CacheSafe["cache_safe.zig"]
        Secrets["secrets.zig"]
        Version["version.zig"]
    end

    subgraph Module["module/ — Authoring"]
        Mod["mod.zig"]
        Server["server.zig"]
        Dispatch["dispatch.zig"]
        TypeDef["typedef.zig"]
        Serde["serde.zig"]
    end

    subgraph SPIFFE["spiffe/ — Workload Identity"]
        SPIFFEFiles["..."]
    end

    Root --> Errors["src/errors.zig<br/>Error sets"]
    Root --> QueryBuilder["src/querybuilder.zig<br/>GraphQL DSL"]
    Root --> GenSample["src/gen_sample.zig<br/>Generated API"]

    Errors --> Core
    QueryBuilder --> Core
    GenSample --> Core

    Core --> Module
    Core --> SPIFFE
```

---

## Data Flow: Client Request

```mermaid
---
config:
  theme: neo
  layout: elk
  look: neo
---
sequenceDiagram
    participant User as User Code
    participant Fluent as Fluent API<br/>dag().container()...
    participant QB as QueryBuilder
    participant GC as GraphQLClient
    participant RE as ResilientExecutor
    participant HTTP as HTTP Transport
    participant Resp as Response Processing

    User->>Fluent: .dag().container().from("alpine").withExec(...).stdout()
    Fluent->>QB: Build Selection chain
    Note over QB: Immutable chains, arena-allocated

    QB->>GC: query(builder)
    Note over GC: Serialize to JSON

    GC->>RE: execute(operation)
    Note over RE: Check circuit breaker

    RE->>HTTP: POST with retry loop
    Note over HTTP: std.Io transport, timeouts
    HTTP-->>RE: Response

    RE->>RE: Record metrics<br/>(success/failure)
    RE-->>GC: Result

    GC->>Resp: Process response
    Note over Resp: JSON deserialize, error extraction
    Resp-->>GC: Parsed result

    GC-->>User: Return result
```

---

## Resilience Architecture

### Circuit Breaker State Machine

````mermaid
---
config:
  theme: neo
  layout: elk
  look: neo
---
stateDiagram-v2
    [*] --> Closed: Initialize

    Closed --> Closed: Success (reset counter)
    Closed --> Open: Failure count ≥ threshold

    Open --> HalfOpen: skip_requests elapsed
    Open --> Open: Requests blocked

    HalfOpen --> Closed: Success (success_threshold reached)
    HalfOpen --> Open: Failure (immediate)

    note right of Closed
        Normal operation
        Requests allowed
    end note

    note right of Open
        Circuit broken
        Requests blocked
        Skip counter running
    end note

    note right of HalfOpen
        Probing mode
        Limited requests
        Testing recovery
    end note

### Retry Pattern

```text
Attempt 0: Immediate (no delay)
Attempt 1: 100ms + jitter(±10%)
Attempt 2: 200ms + jitter(±10%)
Attempt 3: 400ms + jitter(±10%)
...
Max: 5000ms (capped)
````

**Input Validation**:

- NaN/Inf protection on jitter_factor
- Overflow protection on counter increments
- f32 precision guards (maximum representable: 2^24)
- Input validation caps (max_retries <= 100, max_backoff <= 1hr)

---

## Cache Fail-Safe Architecture

### Policy Matrix

| Policy    | Use Cache? | Write Cache? | Failure Behavior                               |
| --------- | ---------- | ------------ | ---------------------------------------------- |
| disabled  | No         | No           | N/A (skip)                                     |
| auto      | Yes        | Yes          | Fallback to uncached, increment fallback count |
| required  | Yes        | Yes          | Propagate error (cache is mandatory)           |
| read_only | Yes        | No           | Fallback to uncached (no writes)               |

### Health Monitoring

```mermaid
---
config:
  theme: neo
  layout: elk
  look: neo
---
mindmap
  root((CacheFailSafe))
    CircuitBreaker
      ::icon(fa-shield)
      Independent from GraphQL
    Metrics
      lookups
      hits
      misses
      fallbacks
      total_wait_ms
    Logger
      ::icon(fa-file-text)
      Optional operational visibility
```

---

## Secret Management Architecture

### Security Layers

```mermaid
---
config:
  theme: neo
  layout: elk
  look: neo
---
block-beta
    columns 4
    l1["Layer 1: Source Validation<br/>• fromEnv()<br/>• fromFile()<br/>• fromVault() (v0.1.1)"]
    l2["Layer 2: Secure Storage<br/>• Duped memory<br/>• Triple-pass zeroing<br/>• No JSON serialization"]
    l3["Layer 3: Leak Prevention<br/>• SecretScrubber<br/>• DoS limits (1K patterns)<br/>• Auto-scrub all output"]
    l4["Layer 4: Audit Trail<br/>• Source identifiers<br/>• TTL timestamps<br/>• Expiration checks"]

    l1 --> l2 --> l3 --> l4
```

---

## Module Authoring Architecture

### Comptime Type Mapping

```mermaid
---
config:
  theme: neo
  layout: elk
  look: neo
---
flowchart TB
    ZS["Zig Struct<br/>(Module Definition)"]
    TD["TypeDef.build()<br/>• Introspect at compile time<br/>• Build Dagger TypeDef JSON<br/>• Map methods → function defs"]
    DT["Dispatch Table<br/>• Method name → function pointer<br/>• Arg deserialization<br/>• Return serialization"]
    SL["Server Loop<br/>• Bind to stdin/stdout<br/>• JSON-RPC protocol<br/>• Graceful shutdown"]

    ZS -->|comptime introspection| TD
    TD -->|vtable generation| DT
    DT -->|runtime serve| SL
```

---

## SPIFFE/SPIRE Integration

### Architecture Pattern: Vtable + Backend

```mermaid
---
config:
  theme: neo
  layout: elk
  look: neo
---
flowchart TB
    subgraph Interface["SvidSource Interface"]
        Methods["fetchX509SVID()<br/>fetchJWTSVID()<br/>fetchX509Bundle()"]
    end

    subgraph v010["v0.1.0 — ShelloutSource"]
        Shellout["spire-agent subprocess<br/>(working)"]
        JWTStub["fetchJWTSVID()<br/>(NotImplementedInV010)"]
        BundleStub["fetchX509Bundle()<br/>(NotImplementedInV010)"]
    end

    subgraph v011["v0.1.1 — NativeWorkloadAPISource"]
        Native["Pure Zig HTTP/2<br/>gRPC framing<br/>Protobuf codec"]
    end

    Interface --> v010
    Interface --> v011

    style v010 fill:#e6f3ff
    style v011 fill:#e6ffe6
```

**Note**: Same interface, different backends. Users can upgrade from shellout to native without source changes.

---

## C FFI Architecture

### Memory Model

```mermaid
---
config:
  theme: neo
  layout: elk
  look: neo
---
sequenceDiagram
    participant C as C Caller
    participant Z as Zig SDK
    participant CH as ClientHandle
    participant COH as ContainerHandle

    C->>Z: dagger_connect()
    Z-->>C: ClientHandle created
    Note over CH: ├─ arena allocator<br/>├─ io.Threaded<br/>└─ dagger.Client

    C->>Z: dagger_query_container()
    Z-->>C: ContainerHandle created
    Note over COH: ├─ parent arena<br/>└─ Container ref

    C->>Z: dagger_client_reset_arena()
    Note right of Z: For long-running<br/>clients — safe memory<br/>reclamation

    C->>Z: dagger_client_close()
    Note right of Z: Cleanup all<br/>resources
```

### Safety Guarantees

1. **Handle validity**: Post-close use is UB (documented)
2. **Thread-local errors**: `dagger_last_error()` per thread
3. **Arena reset**: Safe memory reclamation without freeing
4. **No panics**: All Zig errors caught and mapped to codes

---

## Build System Architecture

### Target Matrix

| Build Step       | Purpose                                 |
| ---------------- | --------------------------------------- |
| lib (default)    | `@import("dagger_sdk")` module          |
| test             | Offline unit tests (41 tests)           |
| test-module      | Comptime module E2E                     |
| test-integration | Live engine tests                       |
| c-lib            | libdagger.{a,so,dylib} + headers        |
| c_smoke          | C client against live engine            |
| matrix           | Cross-compile (5 targets)               |
| sbom             | CycloneDX via syft                      |
| slsa             | SLSA v1.0 provenance                    |
| ci               | Full pipeline (lint→test→c_lib→c_smoke) |

### Self-Hosting CI

```mermaid
---
config:
  theme: neo
  layout: elk
  look: neo
---
flowchart LR
    GHA["GitHub Actions"]
    DC["dagger call ci"]
    ZDM["Zig Dagger Module<br/>(this repo's CI)"]
    CI["Ci struct"]
    Lint["lint()"]
    Test["test()"]
    TestM["testModule()"]
    CLib["cLib()"]
    CSmoke["cSmoke()"]

    GHA -->|triggers| DC
    DC -->|invokes| ZDM
    ZDM --> CI
    CI --> Lint
    CI --> Test
    CI --> TestM
    CI --> CLib
    CI --> CSmoke

    style GHA fill:#f9f9f9
    style ZDM fill:#e6f3ff
```

The CI pipeline uses the Zig module runtime for self-validation.

---

## Evidence-Native Engineering

Every meaningful operation produces evidence:

| Component  | Evidence Produced | Format                                                   |
| ---------- | ----------------- | -------------------------------------------------------- |
| Resilience | ResilienceMetrics | Struct (total_requests, failed, retried, circuit_events) |
| Cache      | CacheMetrics      | Struct (lookups, hits, misses, fallbacks)                |
| Secrets    | AuditSource       | String (vault:kv/data/db#password)                       |
| Build      | SBOM              | CycloneDX JSON                                           |
| Build      | Provenance        | SLSA v1.0 predicate                                      |
| CI         | Pipeline logs     | Structured, secret-scrubbed                              |

---

## Risk Assessment

| Risk                 | Mitigation                               | Status      |
| -------------------- | ---------------------------------------- | ----------- |
| Zig 0.16 API drift   | COMPILE_STATUS.md tracks all speculation | Verified    |
| Memory leaks         | Arena allocator, resetArena() API        | Protected   |
| Secret leaks         | Auto-scrubbing, secure zeroing           | Hardened    |
| Retry storms         | Jitter, circuit breaker, max_backoff     | Hardened    |
| Cache unavailability | 4-tier policies, graceful degradation    | Implemented |

1. **Comptime Type Safety**: GraphQL queries validated at compile time
2. **Zero-Copy Where Possible**: Arena allocation for Selection chains
3. **Vtable Pattern**: SPIFFE backends swappable without source changes
4. **Self-Hosting**: CI validates the module runtime in production
5. **Observability**: All resilience decisions produce metrics

---

## Recommended Reading Order for Reviewers

1. **src/root.zig** — Public API surface
2. **src/core/resilience.zig** — Resilience patterns
3. **src/core/cache_safe.zig** — Cache fail-safe
4. **src/core/secrets.zig** — Security architecture
5. **ci/main.zig** — Self-hosting validation
6. **src/c_api.zig** — FFI implementation

---

## Conclusion

The dagger-zig SDK provides a complete implementation with structured resilience patterns, automatic secret management, and cache fail-safe mechanisms. The self-hosting CI pipeline validates all functionality end-to-end.

**Status**: Ready for technical review.
