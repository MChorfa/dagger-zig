# Incident Response

This runbook covers the practical responses for the issues this repository can
actually hit: failing workflows, broken releases, security advisories, and
unexpected runtime regressions.

## Severity

| Level | Meaning | Examples |
| --- | --- | --- |
| P0 | Release or security integrity is at risk | Compromised signing, exposed secret, broken provenance |
| P1 | Mainline CI is blocked | Workflow failure, reproducible build breakage |
| P2 | Feature or docs quality is degraded | API drift, flaky test, broken examples |
| P3 | Low-impact cleanup | Broken links, stale wording, formatting issues |

## First Response

1. Freeze the scope.
2. Identify the last known good commit or release tag.
3. Capture the failing workflow run, log snippet, or repro command.
4. Decide whether the fix belongs in code, docs, CI, or release plumbing.

## CI Failure

When a GitHub Actions job fails:

1. Open the failing run and read the first error, not the last one.
2. Check whether the failure is in Dagger steps or workflow wiring.
3. Re-run the equivalent local command if the failure is reproducible.
4. Patch the smallest layer that owns the problem.

Useful commands:

```bash
gh run list --limit 5
gh run view <run-id> --log
zig build test
zig build bench
scripts/release-verify.sh v0.3.2
```

## Security Advisory

If a dependency or workflow advisory lands:

1. Confirm whether the vulnerable path is actually used.
2. Update the pinned dependency or workflow action.
3. Re-run the security workflow and release verification.
4. Update the changelog or security notes if the fix changes the public story.

## Broken Release

If a tagged release is missing provenance, signatures, or assets:

1. Verify the release workflow completed successfully.
2. Check the release assets and attestation attachments.
3. Re-run the verification script locally.
4. If the release is genuinely bad, cut a follow-up tag with a clear note.

## Documentation Regression

If the docs start describing behavior the code does not have:

1. Treat the docs as a bug.
2. Fix the docs to match the implementation or remove the claim.
3. Verify the README, docs hub, and reference page all agree.

## Post-Incident Note

Keep the postmortem short and operational:

- What failed
- What was affected
- What fixed it
- What should be automated next

## Related Pages

- [Compliance](compliance.md)
- [Build Guide](build.md)
- [Local CI Testing](local-ci-testing.md)
- [Observability](observability.md)
