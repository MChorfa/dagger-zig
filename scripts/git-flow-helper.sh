#!/usr/bin/env bash
# Git Flow Helper Script
# Provides git-flow-like functionality without requiring git-flow installation

set -e

REMOTE="origin"
MASTER_BRANCH="main"
DEVELOP_BRANCH="develop"

show_help() {
    echo "Git Flow Helper for dagger-zig"
    echo ""
    echo "Usage: $0 <command> [args]"
    echo ""
    echo "Commands:"
    echo "  feature start <name>     Start a new feature branch"
    echo "  feature finish <name>    Finish a feature branch (merge to develop)"
    echo "  release start <version>  Start a new release branch"
    echo "  release finish <version> Finish a release (merge to main & develop)"
    echo "  hotfix start <name>      Start a hotfix branch from main"
    echo "  hotfix finish <name>     Finish a hotfix (merge to main & develop)"
    echo "  init                     Initialize git-flow branches"
    echo "  status                   Show current branch and status"
    echo ""
    echo "Examples:"
    echo "  $0 feature start add-oauth"
    echo "  $0 release start 0.2.0"
    echo "  $0 hotfix start fix-typo"
}

check_git() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo "Error: Not a git repository"
        exit 1
    fi
}

gitflow_init() {
    check_git
    
    echo "Initializing git-flow for dagger-zig..."
    
    # Configure git-flow settings
    git config gitflow.branch.master main
    git config gitflow.branch.develop develop
    git config gitflow.prefix.feature feature/
    git config gitflow.prefix.bugfix bugfix/
    git config gitflow.prefix.release release/
    git config gitflow.prefix.hotfix hotfix/
    git config gitflow.prefix.support support/
    git config gitflow.prefix.versiontag v
    
    # Ensure develop branch exists
    if ! git show-ref --verify --quiet refs/heads/develop; then
        echo "Creating develop branch..."
        git checkout -b develop main
        git push -u $REMOTE develop
    fi
    
    echo "✅ Git-flow initialized!"
    echo "   Main branch: main"
    echo "   Develop branch: develop"
}

feature_start() {
    local name=$1
    if [ -z "$name" ]; then
        echo "Error: Feature name required"
        exit 1
    fi
    
    check_git
    git checkout develop
    git pull $REMOTE develop
    git checkout -b feature/$name develop
    echo "✅ Feature branch feature/$name created from develop"
}

feature_finish() {
    local name=$1
    if [ -z "$name" ]; then
        echo "Error: Feature name required"
        exit 1
    fi
    
    check_git
    local branch="feature/$name"
    
    # Switch to develop and merge
    git checkout develop
    git pull $REMOTE develop
    git merge --no-ff $branch -m "Merge feature '$name' into develop"
    git push $REMOTE develop
    
    # Delete local and remote feature branch
    git branch -d $branch
    git push $REMOTE --delete $branch 2>/dev/null || true
    
    echo "✅ Feature '$name' merged into develop"
}

release_start() {
    local version=$1
    if [ -z "$version" ]; then
        echo "Error: Version required (e.g., 0.2.0)"
        exit 1
    fi
    
    check_git
    git checkout develop
    git pull $REMOTE develop
    git checkout -b release/$version develop
    echo "✅ Release branch release/$version created"
    echo "   Bump version numbers and update CHANGELOG"
}

release_finish() {
    local version=$1
    if [ -z "$version" ]; then
        echo "Error: Version required"
        exit 1
    fi
    
    check_git
    local branch="release/$version"
    local tag="v$version"
    
    # Merge to main
    git checkout main
    git pull $REMOTE main
    git merge --no-ff $branch -m "Release $version"
    git tag -a $tag -m "Release $tag"
    git push $REMOTE main
    git push $REMOTE $tag
    
    # Merge to develop
    git checkout develop
    git pull $REMOTE develop
    git merge --no-ff $branch -m "Merge release '$version' into develop"
    git push $REMOTE develop
    
    # Delete release branch
    git branch -d $branch
    git push $REMOTE --delete $branch 2>/dev/null || true
    
    echo "✅ Release $version complete!"
    echo "   Tagged: $tag"
    echo "   Merged to: main and develop"
}

hotfix_start() {
    local name=$1
    if [ -z "$name" ]; then
        echo "Error: Hotfix name required"
        exit 1
    fi
    
    check_git
    git checkout main
    git pull $REMOTE main
    git checkout -b hotfix/$name main
    echo "✅ Hotfix branch hotfix/$name created from main"
}

hotfix_finish() {
    local name=$1
    if [ -z "$name" ]; then
        echo "Error: Hotfix name required"
        exit 1
    fi
    
    check_git
    local branch="hotfix/$name"
    
    # Merge to main
    git checkout main
    git pull $REMOTE main
    git merge --no-ff $branch -m "Hotfix: $name"
    git push $REMOTE main
    
    # Merge to develop
    git checkout develop
    git pull $REMOTE develop
    git merge --no-ff $branch -m "Merge hotfix '$name' into develop"
    git push $REMOTE develop
    
    # Delete hotfix branch
    git branch -d $branch
    git push $REMOTE --delete $branch 2>/dev/null || true
    
    echo "✅ Hotfix '$name' merged to main and develop"
}

gitflow_status() {
    check_git
    echo "=== Git Flow Status ==="
    echo ""
    echo "Current branch: $(git branch --show-current)"
    echo ""
    echo "Branches:"
    git branch -a | grep -E "(main|develop|feature|release|hotfix)" || true
    echo ""
    echo "Recent commits:"
    git log --oneline -5
}

# Main
case $1 in
    init)
        gitflow_init
        ;;
    feature)
        case $2 in
            start) feature_start $3 ;;
            finish) feature_finish $3 ;;
            *) echo "Unknown feature command: $2"; show_help; exit 1 ;;
        esac
        ;;
    release)
        case $2 in
            start) release_start $3 ;;
            finish) release_finish $3 ;;
            *) echo "Unknown release command: $2"; show_help; exit 1 ;;
        esac
        ;;
    hotfix)
        case $2 in
            start) hotfix_start $3 ;;
            finish) hotfix_finish $3 ;;
            *) echo "Unknown hotfix command: $2"; show_help; exit 1 ;;
        esac
        ;;
    status)
        gitflow_status
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo "Unknown command: $1"
        show_help
        exit 1
        ;;
esac
