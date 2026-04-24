# OpenSSF Scorecard Improvement Plan

## Current Status

### ✅ Completed (Automated)
| Check | Status | Notes |
|-------|--------|-------|
| **Pinned-Dependencies** | Fixed | All 30+ GitHub Actions pinned to verified SHAs |
| **Dangerous-Workflow** | Fixed | No more floating version tags |
| **Binary-Artifacts** | Clean | No committed binaries (only .DS_Store in gitignore) |
| **Token-Permissions** | Set | All workflows have explicit `permissions:` blocks |

### ⏳ Remaining (Requires Your Action)

#### 🔴 Critical - Do These Now

1. **Branch-Protection** (0/10 → 8/10)
   - Go to: https://github.com/MChorfa/dagger-zig/settings/branches
   - Click "Add rule" for `main` branch
   - Enable:
     - [ ] Require a pull request before merging
     - [ ] Require approvals (1)
     - [ ] Dismiss stale PR approvals when new commits are pushed
     - [ ] Require status checks to pass before merging
     - [ ] Require branches to be up to date before merging
     - Select status checks: `ci`, `build`, `test`
   - Impact: **+8 points**

2. **Code-Review** (0/10 → 10/10)
   - Same as above - requires PR reviews
   - Ensure at least 1 reviewer required
   - Impact: **+10 points**

3. **Signed-Releases** (0/10 → 10/10)
   - Create a signed release tag:
   ```bash
   git tag -s v0.1.0 -m "Release v0.1.0"
   git push origin v0.1.0
   ```
   - The SLSA workflow will auto-generate provenance
   - Impact: **+10 points**

4. **CII-Best-Practices** (0/10 → 5/10)
   - Visit: https://bestpractices.coreinfrastructure.org/
   - Sign in with GitHub
   - Add project: `github.com/MChorfa/dagger-zig`
   - Answer the self-assessment questions
   - Impact: **+5 points**

#### 🟡 Medium Priority

5. **Security-Policy** (0/10 → 10/10)
   - Create `SECURITY.md` with vulnerability reporting process
   - Template provided below
   - Impact: **+10 points**

6. **Dependency-Update-Tool** (0/10 → 10/10)
   - Enable Dependabot:
   - Create `.github/dependabot.yml`
   - Impact: **+10 points**

7. **Fuzzing** (N/A → 10/10)
   - Add OSS-Fuzz integration for Zig code
   - Lower priority (requires upstream Zig support)

### 📊 Expected Score Improvements

| Current | With Fixes | Target |
|---------|------------|--------|
| 3.0 | ~7.5 | 8.5+ |

## Security Policy Template

Create `SECURITY.md`:

```markdown
# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 0.1.x   | :white_check_mark: |
| < 0.1.0 | :x:                |

## Reporting a Vulnerability

Please report security vulnerabilities to **security@mchorfa.com** or via GitHub Security Advisories.

DO NOT open a public issue for security vulnerabilities.

We will respond within 48 hours and work to resolve critical issues within 7 days.

## Security Measures

- All releases are signed with Sigstore/cosign
- SLSA Level 3 provenance generated for all builds
- Automated security scanning with Semgrep, CodeQL, Trivy
- Dependency vulnerability scanning with FOSSA
```

## Dependabot Configuration

Create `.github/dependabot.yml`:

```yaml
version: 2
updates:
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
    commit-message:
      prefix: "chore(deps)"
    open-pull-requests-limit: 10

  - package-ecosystem: "npm"
    directory: "/"
    schedule:
      interval: "weekly"
    commit-message:
      prefix: "chore(deps)"

  - package-ecosystem: "docker"
    directory: "/"
    schedule:
      interval: "monthly"
```

## Quick Actions Checklist

- [ ] Enable branch protection for `main`
- [ ] Require PR reviews (1 approval minimum)
- [ ] Require status checks before merge
- [ ] Create and push signed release tag `v0.1.0`
- [ ] Apply for CII Best Practices badge
- [ ] Create `SECURITY.md`
- [ ] Create `.github/dependabot.yml`
- [ ] Enable "Private vulnerability reporting" in Security settings

## Links

- [OpenSSF Scorecard Results](https://api.securityscorecards.dev/projects/github.com/MChorfa/dagger-zig)
- [GitHub Security Tab](https://github.com/MChorfa/dagger-zig/security)
- [Branch Protection Settings](https://github.com/MChorfa/dagger-zig/settings/branches)
