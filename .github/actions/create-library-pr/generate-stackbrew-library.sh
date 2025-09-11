#!/bin/bash
set -e
set -o pipefail

# shellcheck disable=SC2034
last_cmd_stdout=""
# shellcheck disable=SC2034
last_cmd_stderr=""
# shellcheck disable=SC2034
last_cmd_result=0
# shellcheck disable=SC2034
if [ -z "$VERBOSITY" ]; then
    VERBOSITY=1
fi

SCRIPT_DIR="$(dirname -- "$( readlink -f -- "$0"; )")"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/../common/func.sh"

source_helper_file helpers.sh
source_helper_file github_helpers.sh

init_console_output

MAJOR_VERSION=""
REMOTE="origin"
while [[ $# -gt 0 ]]; do
    case $1 in
        --major-version)
            MAJOR_VERSION=$2
            shift
            shift
            ;;
        --remote)
            REMOTE=$2
            shift
            shift
            ;;
        *)
            echo "Error: Unknown option $1"
            exit 1
            ;;
    esac
done

if [ -z "$MAJOR_VERSION" ]; then
    echo "Error: --major-version M is required as argument"
    exit 1
fi

set -u
redis_versions=$(get_actual_major_redis_versions "$REMOTE" "$MAJOR_VERSION")
echo "$redis_versions" | git_fetch_unshallow_refs "$REMOTE"
echo "$redis_versions" | prepare_releases_list | generate_stackbrew_library

