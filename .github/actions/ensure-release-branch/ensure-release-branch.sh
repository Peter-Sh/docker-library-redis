#!/bin/bash
set -e

# Input TAG is expected in $1
TAG="$1"

if [ -z "$TAG" ]; then
    echo "Error: TAG is required as first argument"
    exit 1
fi

# Configure Git to use GITHUB_TOKEN for authentication
if [ -n "$GITHUB_TOKEN" ]; then
    echo "Configuring Git with GITHUB_TOKEN..."
    git config --global url."https://x-access-token:${GITHUB_TOKEN}@github.com/".insteadOf "https://github.com/"

    # Set Git user for commits (required for GitHub Actions)
    git config --global user.name "github-actions[bot]"
    git config --global user.email "github-actions[bot]@users.noreply.github.com"
else
    echo "Warning: GITHUB_TOKEN not found. Git operations may fail if authentication is required."
fi

# Define RELEASE_VERSION_BRANCH which is the same as TAG
RELEASE_VERSION_BRANCH="$TAG"

echo "TAG: $TAG"
echo "RELEASE_VERSION_BRANCH: $RELEASE_VERSION_BRANCH"

# Check if RELEASE_VERSION_BRANCH exists in origin
if git ls-remote --heads origin "$RELEASE_VERSION_BRANCH" | grep -q "$RELEASE_VERSION_BRANCH"; then
    echo "Branch $RELEASE_VERSION_BRANCH exists in origin, checking out..."
    git fetch origin "$RELEASE_VERSION_BRANCH"
    git checkout "$RELEASE_VERSION_BRANCH"
    echo "Successfully checked out to $RELEASE_VERSION_BRANCH"
    exit 0
fi

echo "Branch $RELEASE_VERSION_BRANCH does not exist in origin"

# Detect RELEASE_BRANCH name (release/X.Y format)
RELEASE_BRANCH="release/$(echo "$TAG" | grep -Po '^\d+\.\d+')"
echo "RELEASE_BRANCH: $RELEASE_BRANCH"

# Check if RELEASE_BRANCH exists in origin
if git ls-remote --heads origin "$RELEASE_BRANCH" | grep -q "$RELEASE_BRANCH"; then
    echo "Branch $RELEASE_BRANCH exists in origin"
    git fetch origin "$RELEASE_BRANCH"
    git checkout "$RELEASE_BRANCH"
else
    echo "Branch $RELEASE_BRANCH does not exist in origin, need to create it"

    # Detect base branch (previous existing branch for the version)
    MAJOR_MINOR=$(echo "$TAG" | grep -Po '^\d+\.\d+')
    MAJOR=$(echo "$MAJOR_MINOR" | cut -d. -f1)
    MINOR=$(echo "$MAJOR_MINOR" | cut -d. -f2)

    # Find the previous existing release branch
    BASE_BRANCH=$(git ls-remote --heads origin "release/$MAJOR.[0-9]" | grep -oP 'release/\d+\.\d+' | sort -V | tail -n 1)
    echo git ls-remote --heads origin "release/$MAJOR.[0-9]"

    if [ -z "$BASE_BRANCH" ]; then
        echo "Error: Could not find a base branch for $RELEASE_BRANCH"
        exit 1
    fi

    echo "Using base branch: $BASE_BRANCH"

    # Create new branch based on base branch and push to origin
    git fetch origin "$BASE_BRANCH"
    git checkout -b "$RELEASE_BRANCH" "origin/$BASE_BRANCH"
    git push origin "$RELEASE_BRANCH"
    echo "Created and pushed $RELEASE_BRANCH based on $BASE_BRANCH"
fi

# At this point, we should be on RELEASE_BRANCH
echo "Current branch: $(git branch --show-current)"

# Create RELEASE_VERSION_BRANCH based on RELEASE_BRANCH and push to origin
git checkout -b "$RELEASE_VERSION_BRANCH"
git push origin "$RELEASE_VERSION_BRANCH"
echo "Created and pushed $RELEASE_VERSION_BRANCH based on $RELEASE_BRANCH"

echo "Successfully set up $RELEASE_VERSION_BRANCH - working directory now points to this branch"