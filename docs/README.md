<p align="center">
  <img src="../assets/logo.svg" alt="dagger-zig logo" width="150" height="150">
</p>

# dagger-zig Documentation

A native Zig SDK for the [Dagger](https://dagger.io) programmable CI/CD engine.

> **🔗 Dagger Resources**: [Website](https://dagger.io) • [Docs](https://docs.dagger.io) • [GitHub](https://github.com/dagger/dagger) • [Discord](https://discord.gg/dagger)

## Overview

Zero external dependencies. Zig stdlib only. Authored against Zig 0.16.0 with `std.Io.async` support for parallel container operations.

**Enterprise Ready:** SLSA Level 4 provenance, Sigstore signing, SOC2/ISO27001 compliant, multi-architecture support.

## Quick Links

### Getting Started

- [Getting Started](getting-started.md) — Your first dagger-zig project
- [Build Guide](build.md) — Build options and configurations
- [Examples](examples.md) — Code examples and patterns
- [Module Authoring](module-authoring.md) — Create Dagger modules in Zig

### Architecture & Design

- [Architecture](architecture.md) — Design rationale and internal mechanics
- [ARCHITECTURAL_MAP](ARCHITECTURAL_MAP.md) — Visual architecture overview
- [Layout](layout.md) — Repository structure and conventions

### Enterprise & Operations

- [Compliance](compliance.md) — SOC2, ISO27001, PCI DSS, NIST CSF mappings
- [Observability](observability.md) — OpenTelemetry, logging, metrics
- [Incident Response](incident-response.md) — Runbooks and severity levels
- [Local CI Testing](local-ci-testing.md) — Test workflows locally with `act`

### Security & SPIFFE

- [SPIFFE Integration](spiffe.md) — Workload identity and mTLS
- [API Reference](api-reference.md) — API documentation
- [Contributing](contributing.md) — Development guidelines

## Status

**v0.1.0-RC** — Compiled and tested with Zig 0.16.

## Enterprise Features

| Feature               | Implementation                        |
| --------------------- | ------------------------------------- |
| Supply Chain Security | SLSA Level 4, Sigstore, SBOM          |
| Security Scanning     | Semgrep, CodeQL, Trivy, GitLeaks      |
| Compliance            | SOC2, ISO27001, PCI DSS, NIST CSF 2.0 |
| Multi-Architecture    | 8 platforms including ARM64, RISC-V   |
| Observability         | OpenTelemetry, structured logging     |
| Local CI Testing      | `act` integration with auto-auth      |
