#!/bin/bash

# Version Management Script for BuildRoot Linux OS
# This script helps manage version numbers and prepare releases

set -e

# Default values
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CURRENT_VERSION=""
NEW_VERSION=""
BUMP_TYPE=""
CREATE_TAG=false
PUSH_CHANGES=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Help function
show_help() {
    cat << EOF
Version Management Script

Usage: $0 [OPTIONS]

Options:
    -h, --help           Show this help message
    -v, --version        Show current version
    -b, --bump TYPE    Bump version: major, minor, or patch
    -s, --set VERSION   Set specific version (e.g., v1.2.3)
    -t, --tag           Create git tag after version change
    -p, --push          Push changes and tags to remote

Examples:
    $0 -v                          # Show current version
    $0 -b patch                     # Bump patch version
    $0 -b minor -t -p              # Bump minor version, create tag and push
    $0 -s v2.0.0 -t -p         # Set specific version, create tag and push

EOF
}

# Get current version from git tags
get_current_version() {
    if git rev-parse --git-dir > /dev/null 2>&1; then
        CURRENT_VERSION=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")
    else
        echo "Not in a git repository"
        exit 1
    fi
}

# Validate version format
validate_version() {
    local version=$1
    if [[ ! "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "❌ Invalid version format: $version"
        echo "Expected format: v1.2.3"
        exit 1
    fi
}

# Bump version
bump_version() {
    local bump_type=$1
    local version=${CURRENT_VERSION#v}  # Remove 'v' prefix
    
    # Split version into parts
    IFS='.' read -ra PARTS <<< "$version"
    local major=${PARTS[0]}
    local minor=${PARTS[1]}
    local patch=${PARTS[2]}
    
    case "$bump_type" in
        "major")
            ((major++))
            minor=0
            patch=0
            ;;
        "minor")
            ((minor++))
            patch=0
            ;;
        "patch")
            ((patch++))
            ;;
        *)
            echo "❌ Invalid bump type: $bump_type"
            echo "Use: major, minor, or patch"
            exit 1
            ;;
    esac
    
    NEW_VERSION="v$major.$minor.$patch"
    echo "📈 Bumping $bump_type version: $CURRENT_VERSION → $NEW_VERSION"
}

# Set specific version
set_version() {
    local version=$1
    validate_version "$version"
    NEW_VERSION="$version"
    echo "📝 Setting version: $CURRENT_VERSION → $NEW_VERSION"
}

# Update version in configuration files
update_version_files() {
    echo "📄 Updating version in configuration files..."
    
    # Update README.md version examples
    if [[ -f "README.md" ]]; then
        sed -i "s/$CURRENT_VERSION/$NEW_VERSION/g" README.md
        echo "✅ Updated README.md"
    fi
    
    # Update version in Makefile
    if [[ -f "Makefile" ]]; then
        sed -i "s/VERSION := .*/VERSION := $NEW_VERSION/" Makefile
        echo "✅ Updated Makefile"
    fi
    
    # Update version in build script
    if [[ -f "build.sh" ]]; then
        sed -i "s/VERSION=.*/VERSION=\"$NEW_VERSION\"/" build.sh
        echo "✅ Updated build.sh"
    fi
    
    echo "✅ All version files updated"
}

# Create git tag
create_git_tag() {
    echo "🏷️  Creating git tag..."
    
    # Create tag with message
    git tag -a "$NEW_VERSION" -m "Release $NEW_VERSION

Changes:
$(git log --oneline $(git describe --tags --abbrev=0 2>/dev/null)..HEAD | sed 's/^/- /')"

    echo "✅ Git tag $NEW_VERSION created"
}

# Push changes
push_changes() {
    echo "📤 Pushing changes to remote..."
    
    # Push commits
    git push origin main
    
    # Push tags
    git push origin "$NEW_VERSION"
    
    echo "✅ Changes and tags pushed to remote"
}

# Update changelog
update_changelog() {
    local changelog_file="CHANGELOG.md"
    
    if [[ ! -f "$changelog_file" ]]; then
        echo "# Changelog" > "$changelog_file"
        echo "" >> "$changelog_file"
    fi
    
    local date=$(date +%Y-%m-%d)
    local temp_file=$(mktemp)
    
    # Create new changelog entry
    echo "## [$NEW_VERSION] - $date" > "$temp_file"
    echo "" >> "$temp_file"
    echo "### Added" >> "$temp_file"
    echo "- Automated release build" >> "$temp_file"
    echo "" >> "$temp_file"
    echo "### Changed" >> "$temp_file"
    echo "- Version bump from $CURRENT_VERSION" >> "$temp_file"
    echo "" >> "$temp_file"
    echo "### Fixed" >> "$temp_file"
    echo "- Version management improvements" >> "$temp_file"
    echo "" >> "$temp_file"
    echo "---" >> "$temp_file"
    echo "" >> "$temp_file"
    
    # Append existing changelog
    tail -n +3 "$changelog_file" >> "$temp_file"
    
    # Replace original file
    mv "$temp_file" "$changelog_file"
    
    echo "✅ Updated CHANGELOG.md"
}

# Main function
main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--version)
                get_current_version
                echo "Current version: $CURRENT_VERSION"
                exit 0
                ;;
            -b|--bump)
                BUMP_TYPE="$2"
                shift 2
                ;;
            -s|--set)
                NEW_VERSION="$2"
                shift 2
                ;;
            -t|--tag)
                CREATE_TAG=true
                shift
                ;;
            -p|--push)
                PUSH_CHANGES=true
                shift
                ;;
            *)
                echo "❌ Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Get current version
    get_current_version
    echo "🔍 Current version: $CURRENT_VERSION"
    
    # Determine new version
    if [[ -n "$BUMP_TYPE" ]]; then
        bump_version "$BUMP_TYPE"
    elif [[ -n "$NEW_VERSION" ]]; then
        set_version "$NEW_VERSION"
    else
        echo "ℹ️  No version change requested"
        exit 0
    fi
    
    # Validate new version
    validate_version "$NEW_VERSION"
    
    # Update files
    update_version_files
    update_changelog
    
    # Commit changes
    echo "📝 Committing version changes..."
    git add .
    git commit -m "chore: bump version to $NEW_VERSION"
    echo "✅ Changes committed"
    
    # Create tag if requested
    if [[ "$CREATE_TAG" == true ]]; then
        create_git_tag
    fi
    
    # Push if requested
    if [[ "$PUSH_CHANGES" == true ]]; then
        push_changes
    fi
    
    echo ""
    echo "🎉 Version update complete!"
    echo "📍 New version: $NEW_VERSION"
    echo "📋 Next steps:"
    if [[ "$CREATE_TAG" != true ]]; then
        echo "   - Create tag: $0 --bump patch --tag"
    fi
    if [[ "$PUSH_CHANGES" != true ]]; then
        echo "   - Push changes: $0 --bump patch --tag --push"
    fi
    echo "   - Create release: Trigger GitHub Actions or run manually"
    echo ""
    echo "📦 To create a release now:"
    echo "   git push origin $NEW_VERSION"
    echo "   # Or trigger GitHub Actions manually"
}

# Check if we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "❌ This script must be run from within a git repository"
    exit 1
fi

# Run main function with all arguments
main "$@"