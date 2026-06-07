# CI Pipeline

Dagger-based CI/CD with SLSA L3 compliance and SSDLC security practices.

## Pipeline Story

The CI pipeline follows a 7-phase security-hardened build process:

| Phase | Name                     | Purpose                            | Output                             |
| ----- | ------------------------ | ---------------------------------- | ---------------------------------- |
| 1     | Code Quality             | Validate Zig formatting            | stdout                             |
| 2     | Functional Verification  | Run test suite                     | stdout                             |
| 3     | Security Analysis        | Vulnerability and secret scanning  | vulnerability.sarif, secrets.sarif |
| 4     | SLSA L3 Build            | Hermetic, reproducible compilation | Container with binaries            |
| 5     | Container Security       | Scan built artifacts               | container-vuln.sarif               |
| 6     | Supply Chain Attestation | Generate SBOM and provenance       | provenance.json, sbom.\*.json      |
| 7     | Artifact Collection      | Aggregate all outputs              | Directory with all artifacts       |

## Usage

```bash
# Run the full proof pipeline locally
dagger call -m ./ci/full full-pipeline --arg-0 .

# Inspect the available proof functions
dagger functions -m ./ci/full
```

## Structure

- `full/main.zig` - Self-contained proof pipeline orchestrator
- `full/build.zig` - Module runtime wrapper for the proof module

## Security

- All scans output SARIF format for GitLab/GitHub integration
- Builds use locked Alpine digest for reproducibility
- SOURCE_DATE_EPOCH ensures deterministic timestamps
- Cosign signing for supply chain integrity
