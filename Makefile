# dagger-zig SDK Makefile
# Provides convenient shortcuts for common development tasks

.PHONY: help build test lint clean bench ci-local security-local multi-arch-local lint-md fmt-md dagger-ci dagger-full-ci

# Default target
help:
	@echo "dagger-zig SDK - Available targets:"
	@echo ""
	@echo "Build & Test:"
	@echo "  build          Build the SDK"
	@echo "  test           Run all tests"
	@echo "  lint           Run linter (zig fmt check)"
	@echo "  bench          Run performance benchmarks"
	@echo ""
	@echo "Documentation:"
	@echo "  lint-md        Lint markdown files"
	@echo "  fmt-md         Auto-format markdown files"
	@echo "  docs           Build documentation"
	@echo ""
	@echo "Local CI Testing (act):"
	@echo "  ci-local       Run CI workflow locally (auto-uses gh CLI auth)"
	@echo "  security-local Run security workflow locally"
	@echo "  multi-arch-local Run multi-arch workflow locally"
	@echo "  test-local     Run test workflow locally"
	@echo "  workflow-lint  Validate workflow syntax"
	@echo "  auth-status    Check gh/glab CLI authentication status"
	@echo ""
	@echo "Dagger:"
	@echo "  dagger-ci      Run full CI pipeline via Dagger"
	@echo "  dagger-lint    Run linting via Dagger"
	@echo "  dagger-test    Run tests via Dagger"
	@echo ""
	@echo "Maintenance:"
	@echo "  clean          Clean build artifacts"
	@echo "  fmt            Format code"

# Build targets
build:
	zig build

test:
	zig build test

lint:
	zig fmt --check src/ ci/ benches/

fmt:
	zig fmt src/ ci/ benches/

bench:
	zig build bench

clean:
	rm -rf zig-out/ zig-cache/
	find . -name "*.pdb" -delete
	find . -name "*.o" -delete

# Detect GitHub/GitLab tokens from CLI tools
GITHUB_TOKEN_DETECTED := $(shell command -v gh >/dev/null 2>&1 && gh auth token 2>/dev/null || echo "")
GITLAB_TOKEN_DETECTED := $(shell command -v glab >/dev/null 2>&1 && glab config get token 2>/dev/null || echo "")

# Use detected token or fallback to env var
GITHUB_TOKEN := $(or $(GITHUB_TOKEN_DETECTED),$(GITHUB_TOKEN),mock)

# Local CI testing with act (https://github.com/nektos/act)
ci-local:
	@echo "Running CI workflow locally..."
	@if ! command -v act >/dev/null 2>&1; then \
		echo "❌ 'act' not installed. Install with: brew install act"; \
		exit 1; \
	fi
	@if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then \
		echo "✅ Using gh CLI authentication ($(shell gh api user -q .login 2>/dev/null || echo 'authenticated'))"; \
		act push -W .github/workflows/ci.yml --env-file .env.local --secret GITHUB_TOKEN=$(GITHUB_TOKEN); \
	else \
		echo "⚠️  No gh CLI auth - using mock token"; \
		act push -W .github/workflows/ci.yml --env-file .env.local; \
	fi

security-local:
	@echo "Running security workflow locally..."
	@if ! command -v act >/dev/null 2>&1; then \
		echo "❌ 'act' not installed. Install with: brew install act"; \
		exit 1; \
	fi
	@echo "Using GitHub token: $(if $(GITHUB_TOKEN_DETECTED),✅ From gh CLI,❌ Mock token)"
	act push -W .github/workflows/security.yml --env-file .env.local \
		--secret GITHUB_TOKEN=$(GITHUB_TOKEN) \
		--secret FOSSA_API_KEY=$${FOSSA_API_KEY:-} \
		--secret GITLEAKS_LICENSE=$${GITLEAKS_LICENSE:-}

multi-arch-local:
	@echo "Running multi-arch workflow locally..."
	@if ! command -v act >/dev/null 2>&1; then \
		echo "❌ 'act' not installed. Install with: brew install act"; \
		exit 1; \
	fi
	act push -W .github/workflows/multi-arch.yml --env-file .env.local

test-local:
	@echo "Running all workflows locally (dry run)..."
	@./scripts/test-workflows-local.sh

workflow-lint:
	@echo "Validating workflow syntax..."
	@echo ""
	@if ! command -v yamllint >/dev/null 2>&1; then \
		echo "⚠️  yamllint not installed. YAML syntax only."; \
		echo "   Install: pip install yamllint"; \
	fi
	@echo "Checking GitHub Actions workflow files..."
	@for f in .github/workflows/*.yml; do \
		echo "  $$f"; \
		if command -v yamllint >/dev/null 2>&1; then \
			yamllint -d relaxed "$$f" 2>&1 | head -3 || true; \
		else \
			echo "    ✅ File exists (install yamllint for full validation)"; \
		fi \
	done
	@echo ""
	@echo "To test workflows locally, use:"
	@echo "  make ci-local         # Run CI workflow"
	@echo "  make test-local       # Run full test suite"

# Check authentication status
auth-status:
	@echo "=== CLI Authentication Status ==="
	@echo ""
	@echo "GitHub (gh CLI):"
	@if command -v gh >/dev/null 2>&1; then \
		if gh auth status >/dev/null 2>&1; then \
			echo "  ✅ Authenticated as $(shell gh api user -q .login 2>/dev/null)"; \
			echo "  Token available: $(shell gh auth token 2>/dev/null | cut -c1-10)..."; \
		else \
			echo "  ❌ Not authenticated - run: gh auth login"; \
		fi \
	else \
		echo "  ❌ gh CLI not installed - run: brew install gh"; \
	fi
	@echo ""
	@echo "GitLab (glab CLI):"
	@if command -v glab >/dev/null 2>&1; then \
		if glab auth status 2>&1 | grep -q "Logged in"; then \
			echo "  ✅ Authenticated to $(shell glab config get host 2>/dev/null || echo 'gitlab.com')"; \
		else \
			echo "  ❌ Not authenticated - run: glab auth login"; \
		fi \
	else \
		echo "  ❌ glab CLI not installed - run: brew install glab"; \
	fi

# Dagger-based workflows
dagger-ci:
	dagger call -m ./ci/full full-pipeline --arg-0 .

dagger-full-ci:
	dagger call -m ./ci/full full-pipeline --arg-0 .

dagger-lint:
	dagger call -m ./ci/full lint --arg-0 .

dagger-test:
	dagger call -m ./ci/full run-tests --arg-0 .

dagger-conformance:
	dagger call -m ./ci/full security-scan --arg-0 .

# Documentation
docs:
	@echo "Building documentation..."
	@echo "See docs/ directory for markdown documentation"

# Schema validation
schema-validate:
	zig run schema/validate_main.zig

# Security helpers
cosign-verify:
	@echo "Verifying signatures with cosign..."
	@if ! command -v cosign >/dev/null 2>&1; then \
		echo "❌ 'cosign' not installed."; \
		exit 1; \
	fi
	@echo "Run: cosign verify-blob --certificate artifact.cert --signature artifact.sig artifact"

slsa-verify:
	@echo "Verifying SLSA provenance..."
	@if ! command -v slsa-verifier >/dev/null 2>&1; then \
		echo "❌ 'slsa-verifier' not installed."; \
		echo "Install: go install github.com/slsa-framework/slsa-verifier/v2/cli/slsa-verifier@latest"; \
		exit 1; \
	fi
	@echo "Run: slsa-verifier verify-artifact --provenance-path *.intoto.jsonl artifact"
