#!/bin/bash

# Sources a helper file from multiple possible locations (GITHUB_WORKSPACE, RELEASE_AUTOMATION_DIR, or relative path)
source_helper_file() {
    local helper_file="$1"
    local helper_errors=""
    for dir in "GITHUB_WORKSPACE:$GITHUB_WORKSPACE/redis-oss-release-automation" "RELEASE_AUTOMATION_DIR:$RELEASE_AUTOMATION_DIR" ":../redis-oss-release-automation"; do
        local var_name="${dir%%:*}"
        local dir="${dir#*:}"
        if [ -n "$var_name" ]; then
            var_name="\$$var_name"
        fi
        local helper_path="$dir/.github/actions/common/$helper_file"
        if [ -f "$helper_path" ]; then
            helper_errors=""
            # shellcheck disable=SC1090
            . "$helper_path"
            break
        else
            helper_errors=$(printf "%s\n  %s: %s" "$helper_errors" "$var_name" "$helper_path")
        fi
    done
    if [ -n "$helper_errors" ]; then
        echo "Error: $helper_file not found in any of the following locations: $helper_errors" >&2
        exit 1
    fi
}

# Lists remote release branches for a specific major version (e.g., release/8.*)
git_ls_remote_major_release_version_branches() {
    local remote="$1"
    local major_version="$2"
    execute_command --no-std -- git ls-remote --heads "$remote" "release/$major_version.*"
    if [ -z "$last_cmd_stdout" ]; then
        console_output 0 red "Error: No release branches found for major_version=$major_version"
        return 1
    fi
    echo "$last_cmd_stdout"
}

# Lists remote tags for a specific major version (e.g., v8.*)
git_ls_remote_tags() {
    local remote="$1"
    local major_version="$2"
    execute_command --no-std -- git ls-remote --refs --tags "$remote" "refs/tags/v$major_version.*"
    if [ -z "$last_cmd_stdout" ]; then
        console_output 0 red "Error: No tags found for major_version=$major_version"
        return 1
    fi
    echo "$last_cmd_stdout"
}

# Filters and sorts release branches by major version in reverse version order
filter_major_release_version_branches() {
    local major_version="$1"
    while read -r line; do
        local ref="$(echo "$line" | awk '{print $2}')"
        local commit="$(echo "$line" | awk '{print $1}')"
        if echo "$ref" | grep -q "release/$major_version\.[0-9][0-9]*$"; then
            echo "$ref $commit"
        fi
    done | sort -Vr
}

# Sorts version tags in reverse version order for a specific major version
# stdin: commit ref (git ls-remote)
# stdout: version commit (vX.X.X sha1) - sorted by version
sort_version_tags() {
    local major_version="$1"
    local version_tag commit ref
    while read -r commit ref; do
        version_tag="$(echo "$ref" | grep -o "v$major_version\.[0-9][0-9]*\.[0-9][0-9]*.*" || :)"
        if [ -z "$version_tag" ]; then
            console_output 2 red "Incorrect reference format: $ref"
            return 1
        fi
        printf "%s %s\n" "$version_tag" "$commit"
    done  | sort -Vr
}

# Filters out end-of-life (EOL) versions by skipping entire minor version series marked with -eol suffix
# stdin: version commit (vX.X.X sha1) - must be sorted by version
# stdout: version commit (vX.X.X sha1)
filter_out_eol_versions() {
    local major_version="$1"
    local version_tag commit
    local last_minor="" skip_minor="" minors=""
    local major minor patch suffix
    local versions

    mapfile -t versions
    for line in "${versions[@]}"; do
        read -r version_tag commit < <(echo "$line")
        IFS=: read -r major minor patch suffix < <(redis_version_split "$version_tag")

        if [ "$minor" != "$last_minor" ] && [ -n "$last_minor" ]; then
            if [ -z "$skip_minor" ]; then
                printf "%s" "$minors"
            else
                console_output 2 gray "Skipping minor version $major_version.$last_minor.* due to EOL"
            fi
            minors=""
            skip_minor=""
        fi
        last_minor="$minor"

        printf -v minors "%s%s\n" "$minors" "$version_tag $commit"

        if echo "$suffix" | grep -qi "-eol$"; then
            skip_minor="$minor"
        fi
    done
    if [ -z "$skip_minor" ]; then
        printf "%s" "$minors"
    else
        console_output 2 gray "Skipping minor version $major_version.$last_minor.* due to EOL"
    fi
}

# Filters Redis versions to keep only the latest patch version (and optionally the latest milestone) for each minor version
# stdin: version commit (vX.X.X sha1) - must be sorted by version
# stdout: version commit (vX.X.X sha1)
filter_actual_major_redis_versions() {
    local major_version="$1"
    local last_minor="" last_is_milestone=""
    local ref commit version_tag
    console_output 2 gray "filter_actual_major_redis_versions"
    while read -r version_tag commit; do
        local major minor patch suffix is_milestone
        IFS=: read -r major minor patch suffix < <(redis_version_split "$version_tag")

        if [ -n "$suffix" ]; then
            is_milestone=1
        else
            is_milestone=""
        fi

        if [ "$last_minor" = "$minor" ] && [ "$last_is_milestone" = "$is_milestone" ]; then
            console_output 2 gray "Skipping $version_tag, already have minor=$last_minor is_milestone=$last_is_milestone"
            continue
        fi
        last_minor="$minor"
        last_is_milestone="$is_milestone"

        console_output 2 gray "$version_tag $commit"
        echo "$version_tag $commit"
    done
}

# Gets and filters actual Redis versions (tags) from a remote repository for a major version
get_actual_major_redis_versions() {
    local remote="$1"
    local major_version="$2"
    execute_command git_ls_remote_tags "$remote" "$major_version" \
    | execute_command sort_version_tags "$major_version" \
    | execute_command filter_out_eol_versions "$major_version" \
    | execute_command filter_actual_major_redis_versions "$major_version"
}

# Fetches unshallow refs from a remote repository for the provided list of references
git_fetch_unshallow_refs() {
    local remote="$1"
    local refs_to_fetch=""
    while read -r line; do
        local ref="$(echo "$line" | awk '{print $1}')"
        refs_to_fetch="$refs_to_fetch $ref"
    done
    # shellcheck disable=SC2086
    execute_command --no-std -- git_fetch_unshallow "$remote" $refs_to_fetch
}

# Extracts the distribution name from a Dockerfile's FROM statement (supports Alpine and Debian)
extract_distro_name_from_dockerfile() {
    local base_img
    base_img="$(grep -m1 -i '^from' | awk '{print $2}')"

    increase_indent_level
    console_output 2 gray "Extracting distro from dockerfile"

    if echo "$base_img" | grep -q 'alpine:'; then
        distro="$(echo "$base_img" | tr -d ':')"
    elif echo "$base_img" | grep -q 'debian:'; then
        distro="$(echo "${base_img//-slim/}" | awk -F: '{print $2}')"
    else
        console_output 0 red "Error: Unknown base image $base_img"
        decrease_indent_level
        return 1
    fi
    console_output 2 gray "distro=$distro"
    decrease_indent_level
    echo "$distro"
}

# Splits a Redis version string into major:minor:patch:suffix components
redis_version_split() {
    local version
    local numerics
    # shellcheck disable=SC2001
    version=$(echo "$1" | sed 's/^v//')

    numerics=$(echo "$version" | grep -Po '^[1-9][0-9]*\.[0-9]+(\.[0-9]+|)' || :)
    if [ -z "$numerics" ]; then
        console_output 2 red "Cannot split version '$version', incorrect version format"
        return 1
    fi
    local major minor patch suffix
    IFS=. read -r major minor patch < <(echo "$numerics")
    suffix=${version:${#numerics}}
    printf "%s:%s:%s:%s\n" "$major" "$minor" "$patch" "$suffix"
}

# Shows a file from a specific git reference (commit/branch/tag)
git_show_file_from_ref() {
    local ref=$1
    local file=$2
    execute_command git show "$ref:$file"
}

# Generates a comma-separated list of Docker tags for a Redis version and distribution
# args: redis_version distro_names is_latest is_default
# is_latest empty for non-latest, otherwise latest
# is_default 1 for default distro, otherwise not default
generate_tags_list() {
    local redis_version=$1
    local distro_names=$2
    local is_latest=$3
    local is_default=$4

    local tags versions

    local major minor patch suffix
    IFS=: read -r major minor patch suffix < <(redis_version_split "$redis_version")

    local mainline_version
    mainline_version="$major.$minor"

    versions=("$redis_version")
    #  generate mainline version tag only for GA releases, e.g 8.2 and 8.2-distro
    #  tags will be generated only for 8.2.1 but not for 8.2.1-m01
    if [ -z "$suffix" ]; then
        versions+=("$mainline_version")
    fi
    if [ "$is_latest" != "" ]; then
        versions+=("$major")
    fi

    if [ "$is_default" = 1 ]; then
        tags=("${versions[@]}")
    fi

    for distro_name in $distro_names; do
        for v in "${versions[@]}"; do
            tags+=("$v-$distro_name")
        done
    done

    if [ "$is_latest" != "" ]; then
        if [ "$is_default" = 1 ]; then
            tags+=("latest")
        fi
        # shellcheck disable=SC2206
        tags+=($distro_names)
    fi
    # shellcheck disable=SC2001
    echo "$(IFS=, ; echo "${tags[*]}" | sed 's/,/, /g')"
}

# Generates stackbrew library content (for specific major version)
# stdin: commit redis_version distro distro_version (sha1 vX.X.X alpine alpine3.21)
generate_stackbrew_library() {
    local commit redis_version distro distro_version
    local is_latest="" is_latest_unset=1 is_default

    local stackbrew_content=""

    mapfile -t releases
    for line in "${releases[@]}"; do
        read -r commit redis_version distro distro_version < <(echo "$line")

        local major minor patch suffix
        IFS=: read -r major minor patch suffix < <(redis_version_split "$redis_version")

        # assigning latest to the first non milestone (empty suffix) version from top
        if [ "$is_latest_unset" = 1 ]; then
            if [ -z "$suffix" ]; then
                is_latest="$minor"
                is_latest_unset=""
            fi
        elif [ "$is_latest" != "$minor" ]; then
            is_latest=""
        fi

        if echo "$distro" | grep -q 'alpine'; then
            is_default=""
            distro_names="$distro $distro_version"
        else
            is_default=1
            distro_names="$distro_version"
        fi

        local tags
        tags=$(generate_tags_list "$redis_version" "$distro_names" "$is_latest" "$is_default")
        printf -v stackbrew_content "%s%s\n" "$stackbrew_content" "$tags"
    done
    printf %s "$stackbrew_content"
    console_output 2 gray "$stackbrew_content"
}

# Prepares a list of releases with commit, Redis version, distro, and distro version information
# stdin: redis_version commit
prepare_releases_list() {
    local redis_version commit
    local debug_output="" version_line
    while read -r redis_version commit; do
        for distro in debian alpine; do
            local dockerfile distro_version redis_version
            dockerfile=$(git_show_file_from_ref "$commit" "$distro/Dockerfile")
            console_output 3 gray "$dockerfile"

            distro_version=$(echo "$dockerfile" | extract_distro_name_from_dockerfile)
            # validate version
            redis_version_split "$redis_version" >/dev/null

            printf -v version_line "%s %s %s %s\n" "$commit" "$redis_version" "$distro" "$distro_version"
            printf "%s" "$version_line"
            printf -v debug_output "%s%s" "$debug_output" "$version_line"
        done
    done
    console_output 2 gray "Final Releases list:"
    increase_indent_level
    console_output 2 gray "$debug_output"
    decrease_indent_level
}

slack_format_docker_image_urls_message() {
    # Parse the image URLs from JSON array
    local image_urls formatted_urls release_tag footer
    image_urls=$(cat)
    release_tag=$1
    footer=$2

    # Create formatted list of image URLs
    formatted_urls=$(echo "$image_urls" | jq -j '.[] | "\\n• \(.)"')

# Create Slack message payload
    cat << EOF
{
"text": "🐳 Docker Images Published for Release $release_tag",
"blocks": [
    {
    "type": "header",
    "text": {
        "type": "plain_text",
        "text": "🐳 Docker Images Published for Release $release_tag"
    }
    },
    {
    "type": "section",
    "text": {
        "type": "mrkdwn",
        "text": "The following Docker images have been successfully published:\n\n$formatted_urls"
    }
    },
    {
    "type": "context",
    "elements": [
        {
        "type": "mrkdwn",
        "text": "f$footer"
        }
    ]
    }
]
}
EOF
}