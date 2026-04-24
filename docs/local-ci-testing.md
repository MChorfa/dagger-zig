# Local CI Testing Guide

## Overview

Test GitHub Actions workflows locally before pushing to remote using `act` (https://github.com/nektos/act).

## Prerequisites

### Install Required Tools

```bash
# macOS - install all at once
brew install act gh glab

# Or individually:
# brew install act     # GitHub Actions local runner
# brew install gh      # GitHub CLI (for automatic auth)
# brew install glab    # GitLab CLI (for automatic auth)

# Linux
curl -s https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash
# See https://github.com/cli/cli for gh CLI
# See https://gitlab.com/gitlab-org/cli for glab CLI
```

Verify installation:
```bash
act --version      # Should show 0.2.x or later
gh --version       # GitHub CLI
glab --version     # GitLab CLI
```

### Automatic Authentication (Recommended)

The local CI tools automatically detect authentication from `gh` and `glab` CLIs:

```bash
# Authenticate with GitHub (one-time setup)
gh auth login

# Authenticate with GitLab (one-time setup)
glab auth login

# Check authentication status
make auth-status
```

**No manual token setup needed!** The Makefile and scripts automatically use:
- `gh auth token` for GitHub workflows
- `glab config get token` for GitLab workflows

### Manual Environment Configuration (Optional)

Only needed if you don't use gh/glab CLIs or need additional secrets:

```bash
# Copy example environment file
cp .env.local.example .env.local

# Edit .env.local with your test values (most are optional)
vim .env.local
```

**Note**: Never commit `.env.local` - it's gitignored by default.

## Quick Start

### Using Make (Recommended)

```bash
# List all available targets
make help

# Run CI workflow locally
make ci-local

# Run security workflow locally
make security-local

# Run multi-arch build locally
make multi-arch-local

# Validate all workflow syntax
make workflow-lint

# Dry-run all workflows
make test-local
```

### Using act directly

```bash
# Run CI workflow
act push -W .github/workflows/ci.yml

# Run with specific event (pull_request)
act pull_request -W .github/workflows/ci.yml

# Run specific job only
act push -W .github/workflows/ci.yml -j ci

# Dry run (validate syntax without executing)
act push -W .github/workflows/ci.yml --dry-run

# Run with environment file
act push -W .github/workflows/ci.yml --env-file .env.local

# Run with specific runner image
act push -P ubuntu-latest=catthehacker/ubuntu:act-latest
```

## Workflow-Specific Testing

### CI Workflow (`ci.yml`)

```bash
# Basic run
act push -W .github/workflows/ci.yml

# With Dagger Cloud token (for full pipeline)
act push -W .github/workflows/ci.yml \
  --secret DAGGER_CLOUD_TOKEN=test-token
```

**Local adaptations:**
- Dagger Cloud token is mocked
- Full pipeline runs with local source
- Artifacts are not uploaded to GitHub

### Security Workflow (`security.yml`)

```bash
# Run locally (some jobs may be skipped without real secrets)
act push -W .github/workflows/security.yml \
  --secret GITHUB_TOKEN=ghp_test \
  --secret FOSSA_API_KEY=test \
  --secret GITLEAKS_LICENSE=test
```

**Local adaptations:**
- GitLeaks license check may fail (expected)
- FOSSA scan requires real API key
- Semgrep runs in container (may be slow)
- Trivy works fully

### Multi-Architecture (`multi-arch.yml`)

```bash
# Run locally
act push -W .github/workflows/multi-arch.yml
```

**Local adaptations:**
- Only `ubuntu-latest` jobs run locally
- macOS jobs are skipped (no macOS runner in act)
- Cross-compilation jobs work fully

### SLSA / Release Workflows

⚠️ **These workflows require secrets and should not be run locally**

They require:
- Sigstore OIDC flow (needs real GitHub Actions OIDC)
- SLSA generator (needs GitHub Actions infrastructure)
- Real signing keys

**For local artifact testing:**
```bash
# Build artifacts without signing
act push -W .github/workflows/slsa.yml \
  -j build \
  --artifact-server-path /tmp/artifacts
```

## Troubleshooting

### "docker daemon is not running"

```bash
# macOS
docker context use default
docker ps  # Verify Docker is running

# Or use podman
act push --container-daemon-socket "unix://$(podman machine inspect --format '{{.ConnectionInfo.PodmanSocket.Path}}')"
```

### "403 Resource not accessible by integration"

Some workflows require real GitHub token with write permissions:
```bash
# Create fine-grained personal access token
# https://github.com/settings/tokens

act push -W .github/workflows/ci.yml \
  --secret GITHUB_TOKEN=ghp_xxxxx
```

### Slow performance

Use smaller runner images:
```bash
# Default (large, full tools)
act push

# Medium (faster, most tools)
act push -P ubuntu-latest=catthehacker/ubuntu:act-latest

# Slim (fastest, minimal tools)
act push -P ubuntu-latest=catthehacker/ubuntu:act-22.04
```

### Network timeouts

```bash
# Increase timeout
act push --timeout 30

# Use local registry mirror
act push --registry http://localhost:5000
```

## Best Practices

1. **Always test locally first**
   ```bash
   make ci-local  # Before git push
   ```

2. **Use dry-run for quick validation**
   ```bash
   act push --dry-run
   ```

3. **Test incrementally**
   ```bash
   # Test one workflow at a time
   act push -W .github/workflows/ci.yml
   act push -W .github/workflows/security.yml
   ```

4. **Check workflow syntax**
   ```bash
   # Use GitHub CLI for validation
   gh workflow view ci.yml --yaml | yamllint -
   
   # Or use act dry-run
   act push --dry-run
   ```

## CI Configuration

### `.actrc` (Auto-loaded by act)

```
# Image to use
-P ubuntu-latest=catthehacker/ubuntu:act-latest

# Show job outputs
--verbose

# Bind current directory
--bind

# Use environment file
--env-file .env.local
```

### Environment Variables

| Variable             | Required | Description                              |
| -------------------- | -------- | ---------------------------------------- |
| `GITHUB_TOKEN`       | Optional | GitHub API access                        |
| `DAGGER_CLOUD_TOKEN` | Optional | Dagger Cloud integration                 |
| `COSIGN_PASSWORD`    | Never    | Never use real signing passwords locally |
| `CI`                 | Yes      | Set to `true` for act compatibility      |

## Comparison: Local vs Remote

| Feature           | Local (act)   | Remote (GitHub)  |
| ----------------- | ------------- | ---------------- |
| Ubuntu jobs       | ✅ Works       | ✅ Works          |
| macOS jobs        | ❌ Skipped     | ✅ Works          |
| Windows jobs      | ❌ Skipped     | ✅ Works          |
| Container actions | ✅ Works       | ✅ Works          |
| OIDC/Sigstore     | ❌ Fails       | ✅ Works          |
| Artifact upload   | ✅ Local only  | ✅ GitHub storage |
| Caching           | ✅ Local       | ✅ GitHub cache   |
| Secrets           | Manual config | GitHub Secrets   |
| Performance       | Faster        | Variable         |

## Advanced Usage

### Test matrix combinations

```bash
# Test with different Zig versions
for version in 0.13.0 0.14.0-dev; do
  act push --env ZIG_VERSION=$version
done
```

### Debug workflow

```bash
# Step-by-step execution
act push --verbose

# Attach to running job
act push --verbose --reuse

# View container logs
act push --verbose --container-architecture linux/amd64
```

### Generate test events

```bash
# Create pull_request event payload
cat > /tmp/event.json << 'EOF'
{
  "pull_request": {
    "head": {"ref": "feature-branch"},
    "base": {"ref": "main"}
  }
}
EOF

act pull_request -e /tmp/event.json
```

## References

- [act documentation](https://nektosact.com/)
- [GitHub Actions workflow syntax](https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions)
- [catthehacker/act-images](https://github.com/catthehacker/docker_images)
