#!/bin/bash
set -e -o pipefail
SCRIPT_DIR="$(dirname -- "$( readlink -f -- "$0"; )")"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/../.github/actions/common/func.sh"

source_helper_file "helpers.sh"

set -u

init_console_output

test_get_distro_name_from_dockerfile() {
    distro_name=$(echo 'FROM alpine:3.22' | extract_distro_name_from_dockerfile)
    assertEquals "alpine3.22" "$distro_name"

    distro_name=$(echo 'FROM debian:bookworm-slim' | extract_distro_name_from_dockerfile)
    assertEquals "bookworm" "$distro_name"

    distro_name=$(echo 'FROM debian:bookworm' | extract_distro_name_from_dockerfile)
    assertEquals "bookworm" "$distro_name"
}

test_filter_major_release_version_branches() {
    local input
    input=$(cat <<INPUT
7109557d2a7612b292a6ff2712eba560dc5e70bc	refs/heads/release/8.0
25fa8c6dcbdbbac4b23524e384fd0732923f153b	refs/heads/release/8.2
84ad83bf94e39805cfb1ce3ef4f0b64b2bfb3890	refs/heads/release/8.2_automation
2891ed25b79cda20807aa7b687c9dcc35d3e81f2	refs/heads/release/8.22
285dce3d90263e11657278b251683016be9795c3 refs/heads/release/8.40
b79a605a600e647e75092eccc2d6406effa688f1	refs/heads/release/8.4_foo
1f1a12ebf5c305cc6725aa047834d1049ad882bf	refs/heads/release/8.4
INPUT
    )

    local expected
    expected=$(cat <<EXPECTED
refs/heads/release/8.40 285dce3d90263e11657278b251683016be9795c3
refs/heads/release/8.22 2891ed25b79cda20807aa7b687c9dcc35d3e81f2
refs/heads/release/8.4 1f1a12ebf5c305cc6725aa047834d1049ad882bf
refs/heads/release/8.2 25fa8c6dcbdbbac4b23524e384fd0732923f153b
refs/heads/release/8.0 7109557d2a7612b292a6ff2712eba560dc5e70bc
EXPECTED
    )

    output=$(echo "$input" | filter_major_release_version_branches 8)

    assertEquals "$expected" "$output"
}

test_generate_tags_list() {
    local tags
    tags=$(generate_tags_list 8.2.1 bookworm 1 1)
    assertEquals "8.2.1, 8.2, 8, 8.2.1-bookworm, 8.2-bookworm, 8-bookworm, latest, bookworm" "$tags"

    tags=$(generate_tags_list 8.2.1 "alpine alpine3.22" 1 "")
    assertEquals "8.2.1-alpine, 8.2-alpine, 8-alpine, 8.2.1-alpine3.22, 8.2-alpine3.22, 8-alpine3.22, alpine, alpine3.22" "$tags"

    tags=$(generate_tags_list 8.0-m03 "bookworm" "" 1)
    assertEquals "8.0-m03, 8.0-m03-bookworm" "$tags"

    tags=$(generate_tags_list 8.0-m03 "alpine alpine3.21" "" 1)
    assertEquals "8.0-m03, 8.0-m03-alpine, 8.0-m03-alpine3.21" "$tags"
}

test_redis_version_split() {
    local major minor patch suffix
    local version

    version="8.2.1"
    IFS=: read -r major minor patch suffix < <(redis_version_split "$version")
    assertEquals "return code for $version" "0" "$?"
    assertEquals "major of $version" "8" "$major"
    assertEquals "minor of $version" "2" "$minor"
    assertEquals "patch of $version" "1" "$patch"
    assertEquals "suffix of $version" "" "$suffix"

    version="v8.2.1"
    IFS=: read -r major minor patch suffix < <(redis_version_split "$version")
    assertEquals "return code for $version" "0" "$?"
    assertEquals "major of $version" "8" "$major"
    assertEquals "minor of $version" "2" "$minor"
    assertEquals "patch of $version" "1" "$patch"
    assertEquals "suffix of $version" "" "$suffix"

    version="8.0-m01"
    IFS=: read -r major minor patch suffix < <(redis_version_split "$version")
    assertEquals "return code for $version" "0" "$?"
    assertEquals "major of $version" "8" "$major"
    assertEquals "minor of $version" "0" "$minor"
    assertEquals "patch of $version" "" "$patch"
    assertEquals "suffix of $version" "-m01" "$suffix"

    version="v8.0-m01"
    IFS=: read -r major minor patch suffix < <(redis_version_split "$version")
    assertEquals "return code for $version" "0" "$?"
    assertEquals "major of $version" "8" "$major"
    assertEquals "minor of $version" "0" "$minor"
    assertEquals "patch of $version" "" "$patch"
    assertEquals "suffix of $version" "-m01" "$suffix"

    version="8.0.3-m03-int"
    IFS=: read -r major minor patch suffix < <(redis_version_split "$version")
    assertEquals "return code for $version" "0" "$?"
    assertEquals "major of $version" "8" "$major"
    assertEquals "minor of $version" "0" "$minor"
    assertEquals "patch of $version" "3" "$patch"
    assertEquals "suffix of $version" "-m03-int" "$suffix"

    version="v8.0.3-m03-int"
    IFS=: read -r major minor patch suffix < <(redis_version_split "$version")
    assertEquals "return code for $version" "0" "$?"
    assertEquals "major of $version" "8" "$major"
    assertEquals "minor of $version" "0" "$minor"
    assertEquals "patch of $version" "3" "$patch"
    assertEquals "suffix of $version" "-m03-int" "$suffix"
}

test_redis_version_split_fail() {
    IFS=: read -r major minor patch suffix < <(redis_version_split 8.x.x)
    assertNotEquals "return code" "0" "$?"
}


test_filter_actual_major_release_version() {
    version=$(cat <<TEXT
101262a8cf05b98137d88bc17e77db90c24cc783	refs/tags/v8.0.3
793b20619b66fa29a7e864e874b57c5ed9a7e862	refs/tags/v8.2.1
a13b78815d980881e57f15b9cf13cd2f26f3fab6	refs/tags/v8.2.2
4d09869b4eadb276c54eb3901945eb00429675b9	refs/tags/v8.4.2
3087284763f67e89bcee75c9614e4b53c327cf06	refs/tags/v8.4.1
TEXT
    )
    expected=$(cat <<TEXT
v8.4.2 4d09869b4eadb276c54eb3901945eb00429675b9
v8.2.2 a13b78815d980881e57f15b9cf13cd2f26f3fab6
v8.0.3 101262a8cf05b98137d88bc17e77db90c24cc783
TEXT
    )
    output=$(echo "$version" | filter_actual_major_redis_versions 8)
    assertEquals "$expected" "$output"
}

test_filter_actual_major_release_version_with_milestone() {
    version=$(cat <<TEXT
a6bd46f4af5a540d2fe80bc749d4ef71e9cdb240	refs/tags/v8.0.4-m01
101262a8cf05b98137d88bc17e77db90c24cc783	refs/tags/v8.0.3
cb939ad7def8436cf692d0cf33eaccfebbd00ea2	refs/tags/v8.2.2-m01
fd87823c98d9bbea6dc6516fe2acb2a37d85c5c1	refs/tags/v8.2.2-m03
a13b78815d980881e57f15b9cf13cd2f26f3fab6	refs/tags/v8.2.1
beda0429039786346c7bad8f218e423e8e4d370c	refs/tags/v8.2.1-m01
TEXT
    )
    expected=$(cat <<TEXT
v8.2.2-m03 fd87823c98d9bbea6dc6516fe2acb2a37d85c5c1
v8.2.1 a13b78815d980881e57f15b9cf13cd2f26f3fab6
v8.0.4-m01 a6bd46f4af5a540d2fe80bc749d4ef71e9cdb240
v8.0.3 101262a8cf05b98137d88bc17e77db90c24cc783
TEXT
    )
    output=$(echo "$version" | filter_actual_major_redis_versions 8)
    assertEquals "$expected" "$output"
}

test_sort_version_tags() {
    version=$(cat <<TEXT
a6bd46f4af5a540d2fe80bc749d4ef71e9cdb240	refs/tags/v8.0.4-m01
101262a8cf05b98137d88bc17e77db90c24cc783	refs/tags/v8.0.3
cb939ad7def8436cf692d0cf33eaccfebbd00ea2	refs/tags/v8.2.2-m01
fd87823c98d9bbea6dc6516fe2acb2a37d85c5c1	refs/tags/v8.2.2-m03
a13b78815d980881e57f15b9cf13cd2f26f3fab6	refs/tags/v8.2.1
beda0429039786346c7bad8f218e423e8e4d370c	refs/tags/v8.2.1-m01
TEXT
    )
    expected=$(cat <<TEXT
v8.2.2-m03 fd87823c98d9bbea6dc6516fe2acb2a37d85c5c1
v8.2.2-m01 cb939ad7def8436cf692d0cf33eaccfebbd00ea2
v8.2.1-m01 beda0429039786346c7bad8f218e423e8e4d370c
v8.2.1 a13b78815d980881e57f15b9cf13cd2f26f3fab6
v8.0.4-m01 a6bd46f4af5a540d2fe80bc749d4ef71e9cdb240
v8.0.3 101262a8cf05b98137d88bc17e77db90c24cc783
TEXT
    )
    output=$(echo "$version" | sort_version_tags 8)
    assertEquals "$expected" "$output"
}

test_filter_out_eol_versions() {
    local versions expected
    versions=$(cat <<TEXT
v8.4.0-m03 fd87823c98d9bbea6dc6516fe2acb2a37d85c5c1
v8.2.1 beda0429039786346c7bad8f218e423e8e4d370c
v8.2.1 a13b78815d980881e57f15b9cf13cd2f26f3fab6
v8.0.4-eol a6bd46f4af5a540d2fe80bc749d4ef71e9cdb240
v8.0.3 101262a8cf05b98137d88bc17e77db90c24cc783
TEXT
    )
    expected=$(cat <<TEXT
v8.4.0-m03 fd87823c98d9bbea6dc6516fe2acb2a37d85c5c1
v8.2.1 beda0429039786346c7bad8f218e423e8e4d370c
v8.2.1 a13b78815d980881e57f15b9cf13cd2f26f3fab6
TEXT
    )

    output=$(echo "$versions" | filter_out_eol_versions 8)
    assertEquals "$expected" "$output"
}

test_filter_out_eol_versions_in_the_middle() {
    local versions
    versions=$(cat <<TEXT
v8.4.0-m03 fd87823c98d9bbea6dc6516fe2acb2a37d85c5c1
v8.2.1-eol beda0429039786346c7bad8f218e423e8e4d370c
v8.2.1 a13b78815d980881e57f15b9cf13cd2f26f3fab6
v8.0.4-m01 a6bd46f4af5a540d2fe80bc749d4ef71e9cdb240
v8.0.3 101262a8cf05b98137d88bc17e77db90c24cc783
TEXT
    )
    expected=$(cat <<TEXT
v8.4.0-m03 fd87823c98d9bbea6dc6516fe2acb2a37d85c5c1
v8.0.4-m01 a6bd46f4af5a540d2fe80bc749d4ef71e9cdb240
v8.0.3 101262a8cf05b98137d88bc17e77db90c24cc783
TEXT
    )
    output=$(echo "$versions" | filter_out_eol_versions 8)
    assertEquals "$expected" "$output"
}

test_generate_stackbrew_library_with_head_milestone() {
    local releases output expected
    releases=$(cat <<LIST
8d4437bdd0443189f9b3ba5943fdf793f821e8e2 v8.2.2-m01-int1 debian bookworm
8d4437bdd0443189f9b3ba5943fdf793f821e8e2 v8.2.2-m01-int1 alpine alpine3.22
a13b78815d980881e57f15b9cf13cd2f26f3fab6 v8.2.1 debian bookworm
a13b78815d980881e57f15b9cf13cd2f26f3fab6 v8.2.1 alpine alpine3.22
101262a8cf05b98137d88bc17e77db90c24cc783 v8.0.3 debian bookworm
101262a8cf05b98137d88bc17e77db90c24cc783 v8.0.3 alpine alpine3.21
LIST
    )

    expected=$(cat <<TEXT
v8.2.2-m01-int1, v8.2.2-m01-int1-bookworm
v8.2.2-m01-int1-alpine, v8.2.2-m01-int1-alpine3.22
v8.2.1, 8.2, 8, v8.2.1-bookworm, 8.2-bookworm, 8-bookworm, latest, bookworm
v8.2.1-alpine, 8.2-alpine, 8-alpine, v8.2.1-alpine3.22, 8.2-alpine3.22, 8-alpine3.22, alpine, alpine3.22
v8.0.3, 8.0, v8.0.3-bookworm, 8.0-bookworm
v8.0.3-alpine, 8.0-alpine, v8.0.3-alpine3.21, 8.0-alpine3.21

TEXT
    )

    output=$(generate_stackbrew_library < <(echo "$releases"))
    assertEquals "$expected" "$output"
}

test_generate_stackbrew_library_with_tail_milestone() {
    local releases output expected

    releases=$(cat <<LIST
25fa8c6dcbdbbac4b23524e384fd0732923f153b 8.2.0 debian bookworm
25fa8c6dcbdbbac4b23524e384fd0732923f153b 8.2.0 alpine alpine3.22
7109557d2a7612b292a6ff2712eba560dc5e70bc 8.0-m03 debian bookworm
7109557d2a7612b292a6ff2712eba560dc5e70bc 8.0-m03 alpine alpine3.21
LIST
    )
    expected=$(cat <<TEXT
8.2.0, 8.2, 8, 8.2.0-bookworm, 8.2-bookworm, 8-bookworm, latest, bookworm
8.2.0-alpine, 8.2-alpine, 8-alpine, 8.2.0-alpine3.22, 8.2-alpine3.22, 8-alpine3.22, alpine, alpine3.22
8.0-m03, 8.0-m03-bookworm
8.0-m03-alpine, 8.0-m03-alpine3.21
TEXT
    )

    output=$(generate_stackbrew_library < <(echo "$releases"))
    assertEquals "$expected" "$output"
}

test_generate_stackbrew_library_without_milestone() {
    local releases output expected
    releases=$(cat <<LIST
3bc60241b8fb65eca27ab910caec65ecf84c476b v8.4.0 debian bookworm
3bc60241b8fb65eca27ab910caec65ecf84c476b v8.4.0 alpine alpine3.22
8d4437bdd0443189f9b3ba5943fdf793f821e8e2 v8.2.2 debian bookworm
8d4437bdd0443189f9b3ba5943fdf793f821e8e2 v8.2.2 alpine alpine3.22
101262a8cf05b98137d88bc17e77db90c24cc783 v8.0.3 debian bookworm
101262a8cf05b98137d88bc17e77db90c24cc783 v8.0.3 alpine alpine3.21
LIST
    )

    expected=$(cat <<TEXT
v8.4.0, 8.4, 8, v8.4.0-bookworm, 8.4-bookworm, 8-bookworm, latest, bookworm
v8.4.0-alpine, 8.4-alpine, 8-alpine, v8.4.0-alpine3.22, 8.4-alpine3.22, 8-alpine3.22, alpine, alpine3.22
v8.2.2, 8.2, v8.2.2-bookworm, 8.2-bookworm
v8.2.2-alpine, 8.2-alpine, v8.2.2-alpine3.22, 8.2-alpine3.22
v8.0.3, 8.0, v8.0.3-bookworm, 8.0-bookworm
v8.0.3-alpine, 8.0-alpine, v8.0.3-alpine3.21, 8.0-alpine3.21
TEXT
    )

    output=$(generate_stackbrew_library < <(echo "$releases"))
    assertEquals "$expected" "$output"
}


# shellcheck disable=SC1091
. "$SCRIPT_DIR/shunit2"