#!/bin/bash
set -e

# This script updates Redis version in Dockerfiles using environment variables
# REDIS_ARCHIVE_URL and REDIS_ARCHIVE_SHA, then commits changes if any were made.

# Input TAG is expected in $1
TAG="$1"

if [ -z "$TAG" ]; then
    echo "Error: TAG is required as first argument"
    exit 1
fi

# Check if required environment variables are set
if [ -z "$REDIS_ARCHIVE_URL" ]; then
    echo "Error: REDIS_ARCHIVE_URL environment variable is not set"
    exit 1
fi

if [ -z "$REDIS_ARCHIVE_SHA" ]; then
    echo "Error: REDIS_ARCHIVE_SHA environment variable is not set"
    exit 1
fi

echo "TAG: $TAG"
echo "REDIS_ARCHIVE_URL: $REDIS_ARCHIVE_URL"
echo "REDIS_ARCHIVE_SHA: $REDIS_ARCHIVE_SHA"

# Function to update Dockerfile
update_dockerfile() {
    local dockerfile="$1"
    local updated=false

    if [ ! -f "$dockerfile" ]; then
        echo "Warning: $dockerfile not found, skipping"
        return 1
    fi

    echo "Updating $dockerfile..."

    # Update REDIS_DOWNLOAD_URL
    if grep -q "^ENV REDIS_DOWNLOAD_URL=" "$dockerfile"; then
        sed -i "s|^ENV REDIS_DOWNLOAD_URL=.*|ENV REDIS_DOWNLOAD_URL=$REDIS_ARCHIVE_URL|" "$dockerfile"
        updated=true
        echo "  Updated REDIS_DOWNLOAD_URL"
    fi

    # Update REDIS_DOWNLOAD_SHA
    if grep -q "^ENV REDIS_DOWNLOAD_SHA=" "$dockerfile"; then
        sed -i "s|^ENV REDIS_DOWNLOAD_SHA=.*|ENV REDIS_DOWNLOAD_SHA=$REDIS_ARCHIVE_SHA|" "$dockerfile"
        updated=true
        echo "  Updated REDIS_DOWNLOAD_SHA"
    fi

    if [ "$updated" = true ]; then
        echo "  $dockerfile updated successfully"
        return 0
    else
        echo "  No changes needed in $dockerfile"
        return 1
    fi
}

# Track if any files were modified
files_modified=false

# Update debian/Dockerfile
if update_dockerfile "debian/Dockerfile"; then
    files_modified=true
fi

# Update alpine/Dockerfile
if update_dockerfile "alpine/Dockerfile"; then
    files_modified=true
fi

# Commit changes if any files were modified
if [ "$files_modified" = true ]; then
    echo "Files were modified, committing changes..."
    git config user.email "relesase-bot@redis.com"
    git config user.name "Release Bot"
    git add debian/Dockerfile alpine/Dockerfile
    git commit -m "$TAG"
    echo "Changes committed with message: $TAG"
else
    echo "No files were modified, nothing to commit"
fi

echo "Docker version update completed"
