# CI Pipeline

Dagger-based CI/CD with SLSA L3 compliance and SSDLC security practices.

## Pipeline Story

The CI pipeline follows a 7-phase security-hardened build process:

| Phase | Name | Purpose | Output |
|-------|------|---------|--------|
| 1 | Code Quality | Validate Zig formatting | stdout |
| 2 | Functional Verification | Run test suite | stdout |
| 3 | Security Analysis | Vulnerability and secret scanning | vulnerability.sarif, secrets.sarif |
| 4 | SLSA L3 Build | Hermetic, reproducible compilation | Container with binaries |
| 5 | Container Security | Scan built artifacts | container-vuln.sarif |
| 6 | Supply Chain Attestation | Generate SBOM and provenance | provenance.json, sbom.*.json |
| 7 | Artifact Collection | Aggregate all outputs | Directory with all artifacts |

## Usage

```bash
# Run full pipeline locally
dagger call full-pipeline --source=.

# Run release pipeline with signing
dagger call release-pipeline --source=. --version=v0.1.0 --signing-key=env://COSIGN_KEY
```

## Structure

- `main.zig` - Pipeline orchestrator
- `build/hermetic.zig` - Reproducible builds
- `scan/vulnerability.zig` - Security scanning (Trivy, Gitleaks)
- `attest/provenance.zig` - SLSA provenance generation
- `attest/sbom.zig` - SBOM generation (CycloneDX, SPDX)
- `sign/cosign.zig` - Artifact signing with Sigstore

## Security

- All scans output SARIF format for GitLab/GitHub integration
- Builds use locked Alpine digest for reproducibility
- SOURCE_DATE_EPOCH ensures deterministic timestamps
- Cosign signing for supply chain integrity
