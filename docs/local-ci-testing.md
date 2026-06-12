# Local CI Testing

Use local workflow runs to catch regressions before pushing.

## Recommended Path

1. Run the Dagger-backed checks first:

```bash
zig build test
zig build test-module
zig build bench
```

2. Validate the workflow wiring:

```bash
act push -W .github/workflows/ci.yml --dry-run
act push -W .github/workflows/security.yml --dry-run
act push -W .github/workflows/release.yml --dry-run
```

3. Run the closest local workflow you can reproduce:

```bash
act push -W .github/workflows/ci.yml
```

## What `act` Is Good For

- syntax and job-graph validation
- environment variable checks
- reproducing simple workflow failures

## What `act` Is Not Good For

- GitHub OIDC
- Sigstore signing
- release provenance generation
- macOS and Windows runners

Those checks must happen in GitHub Actions or through the release verification
path in [Compliance](compliance.md).

## Practical Notes

- Use the smallest workflow that reproduces the failure.
- Prefer `--dry-run` before full local execution.
- Keep secrets out of local runs unless a job really needs them.

## Example Commands

```bash
act push -W .github/workflows/ci.yml
act push -W .github/workflows/security.yml
act push -W .github/workflows/multi-arch.yml
```

## Related Pages

- [Build Guide](build.md)
- [Compliance](compliance.md)
- [Incident Response](incident-response.md)
