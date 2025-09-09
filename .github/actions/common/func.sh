#!/bin/bash

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

git_ls_remote_tags() {
    local remote="$1"
    local major_version="$2"
    execute_command git ls-remote --refs --tags "$remote" "refs/tags/v$major_version.*"
}

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

filter_actual_major_redis_versions() {
    local major_version="$1"
    local last_minor="" last_is_milestone=""
    local ref commit version_tag

    while read -r commit ref; do
        version_tag="$(echo "$ref" | grep -o "v$major_version\.[0-9][0-9]*\.[0-9][0-9]*.*")"
        echo "$version_tag $ref $commit"
    done | sort -Vr | while read -r version_tag ref commit; do
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

get_major_release_version_branches () {
    local remote="$1"
    local major_version="$2"
    execute_command git_ls_remote_major_release_version_branches "$remote" "$major_version" | execute_command filter_major_release_version_branches "$major_version"
}

get_actual_major_redis_versions() {
    local remote="$1"
    local major_version="$2"
    execute_command git_ls_remote_tags "$remote" "$major_version" | execute_command filter_actual_major_redis_versions "$major_version"
}

git_fetch_unshallow_refs() {
    local remote="$1"
    local refs_to_fetch
    while read -r line; do
        local ref="$(echo "$line" | awk '{print $1}')"
        refs_to_fetch="$refs_to_fetch $ref"
    done
    # shellcheck disable=SC2086
    execute_command --no-std -- git_fetch_unshallow "$remote" $refs_to_fetch
}

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

extract_redis_version_from_dockerfile() {
    increase_indent_level
    console_output 2 gray "Extracting redis version from dockerfile"
    local redis_version
    redis_version=$(grep -m1 -i '^ENV REDIS_DOWNLOAD_URL.*https*:.*tar' \
        | sed 's/ENV.*REDIS_DOWNLOAD_URL.*[-/]\([1-9][0-9]*\..*\)\.tar\.gz/\1/g' \
        | grep -E '^[1-9][0-9]*\.'
        )
    console_output 2 gray "redis_version=$redis_version"
    if [ -z "$redis_version" ]; then
        console_output 0 red "Error: Failed to extract redis version from dockerfile"
        decrease_indent_level
        return 1
    fi
    echo "$redis_version"
    decrease_indent_level
}

redis_version_split() {
    local version
    local numerics
    # shellcheck disable=SC2001
    version=$(echo "$1" | sed 's/^v//')

    numerics=$(echo "$version" | grep -Po '^[1-9][0-9]*\.[0-9]+(\.[0-9]+|)')
    if [ -z "$numerics" ]; then
        console_output 2 red "Cannot split version '$version', incorrect version format"
        return 1
    fi
    local major minor patch suffix
    IFS=. read -r major minor patch < <(echo "$numerics")
    suffix=${version:${#numerics}}
    printf "%s:%s:%s:%s\n" "$major" "$minor" "$patch" "$suffix"
}


git_show_file_from_ref() {
    local ref=$1
    local file=$2
    execute_command git show "$ref:$file"
}

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

    versions=("$redis_version" "$mainline_version")
    if [ "$is_latest" = 1 ]; then
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

    if [ "$is_latest" = 1 ]; then
        if [ "$is_default" = 1 ]; then
            tags+=("latest")
        fi
        # shellcheck disable=SC2206
        tags+=($distro_names)
    fi
    # shellcheck disable=SC2001
    echo "$(IFS=, ; echo "${tags[*]}" | sed 's/,/, /g')"
}

generate_stackbrew_library() {
    local commit redis_version distro distro_version
    local is_latest="unset" is_default

    local stackbrew_content

    while read -r commit redis_version distro distro_version; do
        local major minor patch suffix
        IFS=: read -r major minor patch suffix < <(redis_version_split "$redis_version")

        # assigning latest to the first non milestone (empty suffix) version from top
        if [ "$is_latest" = "unset" ]; then
            if [ -z "$suffix" ]; then
                is_latest=1
            fi
        else
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

prepare_releases_list() {
    local redis_version commit
    local debug_output version_line
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