#!/usr/bin/env bash
set -euo pipefail

# Local CI/CD workflow testing
# Supports: GitHub Actions (via act) and GitLab CI (via glab)
# 
# Automatically uses authenticated CLI tools:
# - gh CLI (GitHub) - uses 'gh auth token' for automatic authentication
# - glab CLI (GitLab) - uses 'glab auth status' for automatic authentication
#
# Install:
#   macOS:    brew install act gh glab
#   Linux:    See docs/local-ci-testing.md

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Local CI/CD Testing ===${NC}"
echo "Project: ${PROJECT_ROOT}"
echo ""

# Check if act is installed
if ! command -v act &> /dev/null; then
    echo -e "${RED}❌ 'act' is not installed.${NC}"
    echo ""
    echo "Install options:"
    echo "  macOS:    brew install act"
    echo "  Linux:    curl -s https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash"
    echo "  Docker:   docker pull ghcr.io/catthehacker/ubuntu:act-latest"
    echo ""
    exit 1
fi

echo -e "${GREEN}✅ act is installed:${NC} $(act --version)"
echo ""

# Detect and configure authentication
GITHUB_TOKEN=""
GITLAB_TOKEN=""

# Try gh CLI for GitHub authentication
echo -e "${BLUE}=== Authentication Detection ===${NC}"
if command -v gh &> /dev/null; then
    echo -e "${GREEN}✅ gh CLI found${NC}"
    if gh auth status &> /dev/null; then
        GITHUB_TOKEN=$(gh auth token 2>/dev/null || echo "")
        if [[ -n "$GITHUB_TOKEN" ]]; then
            echo -e "${GREEN}✅ GitHub authenticated${NC} ($(gh api user -q .login 2>/dev/null || echo 'user'))"
            echo "   Token will be used for local workflow testing"
        fi
    else
        echo -e "${YELLOW}⚠️  gh CLI not authenticated${NC}"
        echo "   Run: gh auth login"
    fi
else
    echo -e "${YELLOW}⚠️  gh CLI not found${NC}"
    echo "   Install: brew install gh"
fi

echo ""

# Try glab CLI for GitLab authentication
if command -v glab &> /dev/null; then
    echo -e "${GREEN}✅ glab CLI found${NC}"
    if glab auth status 2>&1 | grep -q "Logged in"; then
        GITLAB_TOKEN=$(glab config get token 2>/dev/null || echo "")
        if [[ -n "$GITLAB_TOKEN" ]]; then
            GITLAB_HOST=$(glab config get host 2>/dev/null || echo "gitlab.com")
            echo -e "${GREEN}✅ GitLab authenticated${NC} ($GITLAB_HOST)"
        fi
    else
        echo -e "${YELLOW}⚠️  glab CLI not authenticated${NC}"
        echo "   Run: glab auth login"
    fi
else
    echo -e "${YELLOW}⚠️  glab CLI not found${NC}"
    echo "   Install: brew install glab"
fi

echo ""

# List available workflows
echo "Available workflows:"
ls -1 "${PROJECT_ROOT}/.github/workflows/" | sed 's/^/  - /'
echo ""

# Test each workflow locally (dry run first)
test_workflow() {
    local workflow=$1
    local event=$2
    
    echo "Testing: ${workflow}"
    echo "  Event: ${event}"
    
    # Dry run to validate syntax
    if act ${event} -W ".github/workflows/${workflow}" --dry-run 2>&1 | head -20; then
        echo "  ✅ Syntax valid"
    else
        echo "  ❌ Syntax error"
        return 1
    fi
    
    echo ""
}

# Quick validation of all workflow syntax
echo "=== Syntax Validation ==="
for workflow in "${PROJECT_ROOT}/.github/workflows/"*.yml; do
    wf_name=$(basename "${workflow}")
    
    # Skip workflows that require secrets we don't have locally
    case "${wf_name}" in
        "slsa.yml"|"release.yml")
            echo "⏭️  Skipping ${wf_name} (requires secrets)"
            continue
            ;;
    esac
    
    test_workflow "${wf_name}" "push"
done

echo ""
echo "=== Full Local Run (select workflows) ==="
echo ""
echo "To run a workflow locally with act:"
echo ""
echo "  # Run CI workflow locally"
echo "  act push -W .github/workflows/ci.yml"
echo ""
echo "  # Run security workflow (without secrets)"
echo "  act push -W .github/workflows/security.yml --secret GITHUB_TOKEN=mock"
echo ""
echo "  # Run multi-arch build"
echo "  act push -W .github/workflows/multi-arch.yml"
echo ""
echo "  # Run with specific runner image"
echo "  act push -P ubuntu-latest=catthehacker/ubuntu:act-latest"
echo ""
echo "  # Run specific job"
echo "  act push -W .github/workflows/ci.yml -j ci"
echo ""
echo "  # Dry run (validate only)"
echo "  act push -W .github/workflows/ci.yml --dry-run"
echo ""

echo "=== Environment Setup ==="
echo ""
if [[ -n "$GITHUB_TOKEN" ]] || [[ -n "$GITLAB_TOKEN" ]]; then
    echo -e "${GREEN}✅ Authentication detected - workflows can run with real tokens${NC}"
    echo ""
    echo "  GITHUB_TOKEN: $([[ -n $GITHUB_TOKEN ]] && echo '✅ Available' || echo '❌ Not available')"
    echo "  GITLAB_TOKEN: $([[ -n $GITLAB_TOKEN ]] && echo '✅ Available' || echo '❌ Not available')"
else
    echo -e "${YELLOW}⚠️  No CLI authentication detected${NC}"
    echo ""
    echo "To enable full workflow testing:"
    echo "  1. Install gh CLI:  brew install gh && gh auth login"
    echo "  2. Or set tokens manually in .env.local"
fi

echo ""
echo "Optional: Create .env.local for additional secrets:"
echo "  cp .env.local.example .env.local"
echo ""
