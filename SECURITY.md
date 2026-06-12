# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 0.3.x   | :white_check_mark: |
| < 0.3   | :x:                |

## Reporting a Vulnerability

**Please do not open public issues for security vulnerabilities.**

Instead, report security vulnerabilities via:

1. **GitHub Security Advisories**: [Report privately](https://github.com/mchorfa/dagger-zig/security/advisories/new)
2. **Email**: security@MChorfa.io

We will acknowledge receipt within 24 hours and provide a timeline for resolution within 72 hours.

### GPG Key

```
-----BEGIN PGP PUBLIC KEY BLOCK-----
Public key publication is pending. Use GitHub Security Advisories or email for now.
-----END PGP PUBLIC KEY BLOCK-----
```

## Security Features

### Supply Chain Security

- **SLSA Build Level 3** provenance attestations using in-toto
- **Sigstore** keyless signing with OIDC
- **SBOM** generation (SPDX + CycloneDX) for every release
- **Reproducible builds** with locked dependencies

### Runtime Security

- **mTLS** enforcement for all Dagger engine communication
- **SPIFFE/SPIRE** workload identity (see [SPIFFE_IMPL.md](./SPIFFE_IMPL.md))
- **Secret management** via Dagger secrets (never logged or persisted)
- **Capability-based** sandboxing

### Code Security

- **SAST**: Semgrep, CodeQL scanning on every PR
- **DAST**: Trivy vulnerability scanning for containers
- **Secret scanning**: GitLeaks for credential detection
- **Dependency audit**: Automated CVE monitoring via Dependabot

## Threat Model

### Assets

1. **Source Code** - Intellectual property, build logic
2. **Build Artifacts** - Compiled binaries, OCI images
3. **Credentials** - Signing keys, API tokens
4. **Provenance Data** - Attestations, SBOMs

### Threats

| Threat                        | Mitigation                            | Status |
| ----------------------------- | ------------------------------------- | ------ |
| Compromised build environment | Hermetic builds, SLSA Build L3        | ✅      |
| Malicious dependency          | SBOM scanning, lock files             | ✅      |
| Secret leakage                | GitLeaks, secret scanning             | ✅      |
| Replay attacks                | Signed timestamps, nonces             | ✅      |
| Supply chain tampering        | Sigstore signatures, transparency log | ✅      |
| Privilege escalation          | mTLS, workload identity               | 🔄      |
| Side-channel attacks          | Constant-time crypto (planned)        | ⏳      |

## Security Best Practices

### For SDK Users

```zig
// Always use secrets for sensitive data
const apiKey = ctx.secret("API_KEY");  // Never hardcode

// Enable SPIFFE workload identity when available
const client = try dagger.connectWithIdentity(.{
    .spiffe_id = "spiffe://trust-domain/workload",
});

// Verify provenance before using artifacts
const verified = try dagger.verifyProvenance(.{
    .subject = artifact,
    .expected_builder = "https://github.com/mchorfa/dagger-zig/.github/workflows/release.yml",
});
```

### For Contributors

1. **Never commit secrets** - Use Dagger secrets or environment variables
2. **Sign all commits** - Use GPG or SSH signing
3. **Follow least privilege** - Request minimal permissions in CI
4. **Report vulnerabilities privately** - See above

## Compliance

| Framework        | Controls                | Evidence               |
| ---------------- | ----------------------- | ---------------------- |
| SOC 2 CC6.1      | Logical access controls | RBAC, mTLS             |
| SOC 2 CC6.6      | Security infrastructure | SLSA Build L3, Sigstore|
| SOC 2 CC7.1      | Security detection      | SAST, DAST, monitoring |
| SOC 2 CC7.2      | Incident response       | Security advisories    |
| ISO 27001 A.12.1 | Operational security    | Hermetic builds        |
| ISO 27001 A.14.2 | System security testing | Conformance tests      |

## Security Hardening Checklist

- [ ] Enable 2FA for all maintainers
- [ ] Sign all commits with GPG/SSH
- [ ] Use Sigstore keyless signing
- [ ] Enable branch protection with required reviews
- [ ] Enable Dependabot for all ecosystems
- [ ] Configure CodeQL analysis
- [ ] Run weekly Trivy scans
- [ ] Maintain SBOM for every release
- [ ] Document incident response procedures
- [ ] Conduct annual penetration testing

## Acknowledgments

We thank the following security researchers who have responsibly disclosed vulnerabilities:

- _None yet - be the first!_

## License

Security policies and procedures are licensed under [CC-BY-4.0](https://creativecommons.org/licenses/by/4.0/).
