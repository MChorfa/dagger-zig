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

## Release provenance & signing

Tagged releases carry build provenance and a keyless signature, wired in `release.yml`
(this applies to releases cut after this change):

- **SLSA build provenance** — `actions/attest-build-provenance` attaches GitHub-native
  provenance to each release tarball.
- **Keyless signature** — each tarball is signed with cosign (Sigstore bundle, OIDC; no
  long-term keys), and the `.bundle` is published with the release.

> The older `ci/attest` / `ci/sign` Zig modules (a `provenance/v0.2` predicate generator
> and cosign blob helpers) are not used by the release flow — it uses the GitHub-native
> attestation + cosign actions above instead.

### Verifying a release

```bash
# Verify the keyless Sigstore signature (requires cosign)
cosign verify-blob \
  --bundle dagger-zig-<tag>-<target>.tar.gz.bundle \
  --certificate-identity "https://github.com/MChorfa/dagger-zig/.github/workflows/release.yml@refs/tags/<tag>" \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  dagger-zig-<tag>-<target>.tar.gz

# Verify the SLSA build provenance (requires gh CLI)
gh attestation verify dagger-zig-<tag>-<target>.tar.gz --repo MChorfa/dagger-zig
```

## Framework mapping

Earlier revisions of this page mapped controls to SOC 2 / ISO 27001 / PCI DSS / NIST CSF.
That mapping was removed: the SDK does not implement those frameworks, and presenting the
mapping as "compliance" was misleading. Use the table above as the source of truth for what
the project provides.
