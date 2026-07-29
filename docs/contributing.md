# Contributing

Contributions are welcome. Keep changes small, verified, and aligned with the
current docs and release story.

## Before You Start

- Install Zig 0.16 or later
- Install the Dagger CLI
- Clone the repository
- Read the docs hub in `docs/README.md`

## Local Checks

```bash
zig build
zig build test
zig build test-module
zig build bench
```

If you are touching workflows or release plumbing, also run:

```bash
zig build test-integration
scripts/release-verify.sh v0.3.5
```

## Workflow

1. Add or update tests first.
2. Implement the smallest code change that fixes the issue.
3. Update docs when the public story changes.
4. Run the relevant local checks.

## Code Style

- Follow Zig naming conventions
- Keep public APIs documented
- Prefer explicit error handling
- Avoid widening scope when a narrow fix is enough

## Security

- Do not commit secrets
- Follow the repository security policy for reporting issues
- Treat workflow and release changes as supply-chain sensitive

## Commit Messages

Use conventional commits:

```text
feat(sdk): add support for cache volumes
fix(ci): resolve workflow race condition
docs(security): tighten release notes
```

## Getting Help

- [Architecture](architecture.md)
- [Local CI Testing](local-ci-testing.md)
- [Incident Response](incident-response.md)

## License

Apache-2.0. By contributing, you agree to license your contributions under the
same terms.
