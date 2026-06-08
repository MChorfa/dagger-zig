# Security & Compliance Notes

> **This is a single-maintainer open-source SDK, not a certified or audited product.**
> Nothing here is a SOC 2, ISO 27001, PCI DSS, or NIST attestation. This page lists the
> security practices the project actually runs so that *you* can map them to your own
> framework controls if you need to.

## What the project actually does

| Area                   | How                                                      | Where                                              |
| ---------------------- | -------------------------------------------------------- | -------------------------------------------------- |
| Dependency footprint   | Zero third-party dependencies (Zig stdlib only)          | `build.zig.zon` (`.dependencies = .{}`)            |
| SBOM                   | CycloneDX + SPDX, generated with Syft                    | `ci/build` (`generateSBOM`)                        |
| Static analysis        | Semgrep                                                  | `ci/security`, `.github/workflows/security.yml`    |
| Secret scanning        | GitLeaks                                                 | `ci/security`                                      |
| Dependency scanning    | Grype                                                    | `ci/security`                                      |
| Vulnerability reporting | Coordinated disclosure                                  | `SECURITY.md`                                      |
| Change control         | Required PR review + CI checks + branch protection       | GitHub repository settings                         |

## Not yet wired

These exist in the tree but are **not** part of the release flow today. Don't rely on them:

- **SLSA provenance** — a `slsa.dev/provenance/v0.2` predicate generator lives in `ci/attest/provenance.zig`, but no workflow attaches provenance to releases.
- **Artifact signing** — cosign helpers live in `ci/sign`, and `release.yml` installs cosign, but no release artifact is actually signed yet.

These are tracked on the [roadmap](roadmap.md).

## Framework mapping

Earlier revisions of this page mapped controls to SOC 2 / ISO 27001 / PCI DSS / NIST CSF.
That mapping was removed: the SDK does not implement those frameworks, and presenting the
mapping as "compliance" was misleading. Use the table above as the source of truth for what
the project provides.
