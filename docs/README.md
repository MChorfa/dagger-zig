<p align="center">
  <img src="../assets/logo.svg" alt="dagger-zig logo" width="150" height="150">
</p>

# dagger-zig Documentation

A native Zig SDK for the [Dagger](https://dagger.io) programmable CI/CD engine.

> **🔗 Dagger Resources**: [Website](https://dagger.io) • [Docs](https://docs.dagger.io) • [GitHub](https://github.com/dagger/dagger) • [Discord](https://discord.gg/dagger)

## Overview

Zero external dependencies. Zig stdlib only. Authored against Zig 0.16.0 with `std.Io.async` support for parallel container operations.

**Enterprise Ready:** SLSA Level 4 provenance, Sigstore signing, SOC2/ISO27001 compliant, multi-architecture support
including Windows.

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

### ⚡ Advanced Features (v0.2.0)

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
| [Compliance](compliance.md)               | SOC2, ISO27001, PCI DSS, NIST CSF |
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

**v0.2.0** — Multi-platform support, async patterns, tracing, expanded API types

## Enterprise Feature Matrix

| Feature               | Status | Implementation                                 |
| --------------------- | ------ | ---------------------------------------------- |
| Supply Chain Security | ✅      | SLSA Level 4, Sigstore, SBOM (CycloneDX, SPDX) |
| Security Scanning     | ✅      | Semgrep, CodeQL, Trivy, GitLeaks               |
| Compliance            | ✅      | SOC2, ISO27001, PCI DSS, NIST CSF 2.0          |
| Multi-Platform        | ✅      | Linux, macOS, Windows + 8 architectures        |
| Async Operations      | ✅      | `dagger.async` module with QueryGroup          |
| Observability         | ✅      | OpenTelemetry tracing, structured logging      |
| Self-Hosting CI       | ✅      | SDK builds itself via `ci/` module             |
| Windows Support       | ✅      | Native Windows builds, cross-compilation       |
