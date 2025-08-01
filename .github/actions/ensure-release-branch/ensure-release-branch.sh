#!/bin/bash

# This script ensures that a release branch and release version branch exist for a given release tag.
# It creates and pushes both branches if they do not exist.
# It also checks out the release version branch at the end.
# https://redislabs.atlassian.net/wiki/spaces/RED/pages/5293342875/Redis+OSS+release+automation

set -e
#set -x

# shellcheck disable=SC2034
last_cmd_stdout=""
# shellcheck disable=SC2034
last_cmd_stderr=""
# shellcheck disable=SC2034
last_cmd_result=0
# shellcheck disable=SC2034
VERBOSITY=1

SCRIPT_DIR="$(dirname -- "$( readlink -f -- "$0"; )")"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/../common/helpers.sh"

# Input TAG is expected in $1
TAG="$1"

if [ -z "$TAG" ]; then
    echo "Error: TAG is required as first argument"
    exit 1
fi
# Define RELEASE_VERSION_BRANCH which is the same as TAG
RELEASE_VERSION_BRANCH="$TAG"

echo "TAG: $TAG"
echo "RELEASE_VERSION_BRANCH: $RELEASE_VERSION_BRANCH"

# Check if RELEASE_VERSION_BRANCH exists in origin
execute_command git ls-remote --heads origin "$RELEASE_VERSION_BRANCH"
if echo "$last_cmd_stdout" | grep -q "$RELEASE_VERSION_BRANCH"; then
    execute_command git fetch origin "$RELEASE_VERSION_BRANCH"
    execute_command git checkout "$RELEASE_VERSION_BRANCH"
    echo "Successfully checked out to $RELEASE_VERSION_BRANCH"
    exit 0
fi

echo "Branch $RELEASE_VERSION_BRANCH does not exist in origin"

# Detect RELEASE_BRANCH name (release/X.Y format)
RELEASE_BRANCH="release/$(echo "$TAG" | grep -Po '^\d+\.\d+')"
echo "RELEASE_BRANCH: $RELEASE_BRANCH"

# Check if RELEASE_BRANCH exists in origin
execute_command git ls-remote --heads origin "$RELEASE_BRANCH"
if echo "$last_cmd_stdout" | grep -q "$RELEASE_BRANCH"; then
    echo "Branch $RELEASE_BRANCH exists in origin"
    execute_command git fetch origin "$RELEASE_BRANCH"
    execute_command git checkout "$RELEASE_BRANCH"
else
    echo "Branch $RELEASE_BRANCH does not exist in origin, need to create it"

    # Detect base branch (previous existing branch for the version)
    MAJOR_MINOR=$(echo "$TAG" | grep -Po '^\d+\.\d+')
    MAJOR=$(echo "$MAJOR_MINOR" | cut -d. -f1)

    # Find the previous existing release branch
    execute_command git ls-remote --heads origin "release/$MAJOR.[0-9]"
    BASE_BRANCH=$(echo "$last_cmd_stdout" | grep -oP 'release/\d+\.\d+' | sort -V | tail -n 1)

    if [ -z "$BASE_BRANCH" ]; then
        echo "Error: Could not find a base branch for $RELEASE_BRANCH"
        exit 1
    fi

    echo "Using base branch: $BASE_BRANCH"

    # Create new branch based on base branch and push to origin
    execute_command git fetch origin "$BASE_BRANCH"
    execute_command git checkout -b "$RELEASE_BRANCH" "origin/$BASE_BRANCH"
    execute_command git push origin HEAD:"$RELEASE_BRANCH"
    echo "Created and pushed $RELEASE_BRANCH based on $BASE_BRANCH"
fi

# At this point, we should be on RELEASE_BRANCH
echo "Current branch: $(git branch --show-current)"

# Create RELEASE_VERSION_BRANCH based on RELEASE_BRANCH and push to origin
execute_command git checkout -b "$RELEASE_VERSION_BRANCH"
execute_command git push origin HEAD:"$RELEASE_VERSION_BRANCH"
echo "Created and pushed $RELEASE_VERSION_BRANCH based on $RELEASE_BRANCH"

echo "Successfully set up $RELEASE_VERSION_BRANCH - working directory now points to this branch"