<p align="center">
  <img src="../assets/logo.svg" alt="dagger-zig logo" width="150" height="150">
</p>

# dagger-zig Documentation

A native Zig SDK for the [Dagger](https://dagger.io) programmable CI/CD engine.

> **🔗 Dagger Resources**: [Website](https://dagger.io) • [Docs](https://docs.dagger.io) • [GitHub](https://github.com/dagger/dagger) • [Discord](https://discord.gg/dagger)

## Overview

Zero external dependencies — Zig stdlib only. Authored against Zig 0.16.0, with `std.Io.async` used for parallel container operations.

This is a single-maintainer SDK at **v0.2.1**: a POSIX synchronous client, module authoring, tracing, and experimental SPIFFE support. See [Current Status](#current-status) for what is and isn't done.

## Documentation Structure

### 🚀 Getting Started (Start Here)

| Document                              | Description                                |
| ------------------------------------- | ------------------------------------------ |
| [Getting Started](getting-started.md) | Your first dagger-zig project in 5 minutes |
| [Build Guide](build.md)               | Build options, targets, and configurations |
| [Examples](examples.md)               | Code examples and common patterns          |
| [IDE Setup](ide-setup.md)             | Zed, VS Code, Vim configuration            |

### 🏗️ Core Concepts

| Document                                  | Description                             |
| ----------------------------------------- | --------------------------------------- |
| [Architecture](architecture.md)           | Design rationale and internal mechanics |
| [ARCHITECTURAL_MAP](ARCHITECTURAL_MAP.md) | Visual architecture overview            |
| [Repository Layout](layout.md)            | Repository structure and conventions    |
| [Why Zig?](why-zig.md)                    | Why we chose Zig for this SDK           |

### 🔧 API Reference

| Document                                | Description                       |
| --------------------------------------- | --------------------------------- |
| [Client API](api-reference.md)          | Core API documentation            |
| [Module Authoring](module-authoring.md) | Create Dagger modules in Zig      |
| [Query Builder](query-builder.md)       | Building GraphQL queries          |
| [Error Handling](errors.md)             | Error types and handling patterns |
| [Type System](types.md)                 | Type definitions and conversions  |

### ⚡ Advanced Topics (v0.2.x)

| Document                            | Description                               |
| ----------------------------------- | ----------------------------------------- |
| [Async Patterns](async-patterns.md) | Concurrent operations with `dagger.async` |
| [Tracing](tracing.md)               | OpenTelemetry-compatible tracing          |
| [Windows Support](windows.md)       | Windows platform specifics                |
| [Cache Volumes](cache.md)           | Persistent caching strategies             |
| [Secret Management](secrets.md)     | Secure secret handling                    |

### 🔒 Security & Identity

| Document                                  | Description                |
| ----------------------------------------- | -------------------------- |
| [SPIFFE Integration](spiffe.md)           | Workload identity and mTLS |
| [Workload Identity](workload-identity.md) | SPIFFE/SPIRE integration   |
| [C FFI](c-api.md)                         | Foreign Function Interface |

### 🏢 Enterprise & Operations

| Document                                  | Description                       |
| ----------------------------------------- | --------------------------------- |
| [Compliance](compliance.md)               | Security practices (not a certification) |
| [Observability](observability.md)         | OpenTelemetry, logging, metrics   |
| [Incident Response](incident-response.md) | Runbooks and severity levels      |
| [Resilience Patterns](resilience.md)      | Fault tolerance and recovery      |
| [Local CI Testing](local-ci-testing.md)   | Test workflows locally            |

### 📝 Contributing & Reference

| Document                                  | Description                 |
| ----------------------------------------- | --------------------------- |
| [Contributing](contributing.md)           | Development guidelines      |
| [Migration Guide](migration.md)           | Version migration notes     |
| [Roadmap](roadmap.md)                     | Future plans and priorities |
| [Release Checklist](RELEASE_CHECKLIST.md) | Release process             |
| [Changelog](../CHANGELOG.md)              | Version history             |

## Current Status

**v0.2.1** — POSIX synchronous client SDK, module authoring, tracing, and experimental SPIFFE shellout support

## Feature Status

| Feature           | Status | Notes                                                              |
| ----------------- | ------ | ------------------------------------------------------------------ |
| Client SDK        | ✅     | POSIX, synchronous; zero external dependencies                     |
| Self-hosting CI   | ✅     | SDK builds itself via the `ci/pipeline` Dagger module             |
| SBOM              | ✅     | CycloneDX + SPDX generated by Syft in the build pipeline           |
| Security scanning | ✅     | Semgrep, GitLeaks, Grype run in CI                                 |
| Observability     | 🟡     | OpenTelemetry tracing + structured logging in the SDK              |
| SLSA provenance   | 🟡     | Generator exists (`ci/attest`) but is not yet wired into releases  |
| Artifact signing  | 🟡     | cosign tooling present (`ci/sign`) but not yet invoked in releases |
| Async operations  | 🟡     | Experimental; broader support deferred to v0.3.0                   |
| Windows support   | 🟡     | Planned for v0.3.0; current release is POSIX-only                  |

See [Security & Compliance Notes](compliance.md) for what the project actually does — it is **not** a certified or audited product.
