# Contributing

Thank you for your interest in contributing to dagger-zig! This project welcomes contributions from the community.

## Development Setup

### Prerequisites

1. **Install Zig 0.16.0 or later**
2. **Install Dagger CLI** (`dagger` on PATH)
3. **Clone the repository**

### Optional Tools (Recommended)

For local CI testing:

```shell
# macOS
brew install act gh glab

# act: Local GitHub Actions runner
# gh: GitHub CLI (auto-authentication for local testing)
# glab: GitLab CLI (auto-authentication for local testing)
```

## Build & Test

```shell
# Build the SDK
make build
# or: zig build

# Run tests
make test
# or: zig build test

# Run benchmarks
make bench

# Format code
make fmt
```

## Local CI Testing

Test workflows locally before pushing:

```shell
# Check authentication status
make auth-status

# Run CI workflow locally (uses gh CLI auth automatically)
make ci-local

# Run security workflow locally
make security-local

# Test multi-arch builds
make multi-arch-local

# Validate workflow syntax
make workflow-lint
```

See [Local CI Testing Guide](local-ci-testing.md) for detailed setup.

## Code Style

- Follow Zig naming conventions
- Use `gpa` for General Purpose Allocator variable names
- Document public APIs with doc comments
- Keep `unreachable` out of library code — all errors must be handled
- Follow enterprise security patterns for new features

## Adding Features

1. **Add tests first** — All code must have tests
2. **Implement feature** — Follow existing patterns
3. **Update documentation** — README, docs/, and inline comments
4. **Test locally** — `make workflow-lint && make ci-local`
5. **Run full CI** — `dagger call ci --source=.`

## Security

- Never commit secrets — Use Dagger secrets or environment variables
- Follow the [Security Policy](../SECURITY.md) for vulnerability reporting
- Ensure new code passes security scanning (Semgrep, CodeQL)

## Enterprise Considerations

When contributing, consider:

- **Supply chain security** — All builds must be reproducible
- **Observability** — Add OpenTelemetry spans for new operations
- **Compliance** — Document any security-relevant changes
- **Multi-arch support** — Code should work on all supported platforms

## CI/CD

The project uses:
- **Self-hosting CI**: `ci/main.zig` — Zig Dagger module that builds dagger-zig
- **GitHub Actions**: For public CI and security scanning
- **Local testing**: `act` for pre-push validation
- **Documentation CI**: Dagger-based mdBook rendering to GitHub Pages

## Documentation

All documentation is linted and rendered automatically via Dagger:

```shell
# Lint markdown files (Dagger-native)
dagger call -m ci lint-docs --source=. export --path ./reports

# Build documentation site locally
dagger call -m ci build-docs --source=. export --path ./_site

# Serve docs locally (after building)
cd _site && python3 -m http.server 8000
```

The documentation is automatically deployed to GitHub Pages on every push to main.

## Getting Help

- [Architecture](architecture.md) — Design rationale
- [Local CI Testing](local-ci-testing.md) — Testing workflows locally
- [Incident Response](incident-response.md) — If something goes wrong

## License

Apache-2.0. By contributing, you agree to license your contributions under the same license.
