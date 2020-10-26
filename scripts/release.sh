#!/usr/bin/env bash

set -e

source ${DAPPER_SOURCE}/scripts/lib/utils
source ${SCRIPTS_DIR}/lib/debug_functions

### Functions ###

function determine_org() {
    local origin_url=$(git config --get remote.origin.url)
    git config --get remote.origin.url | awk -F'[:/]' '{print $(NF-1)}'
}

function create_release() {
    local repo="$1"
    local files="${@:2}"
    local commit_ref=$(_git rev-parse --verify HEAD)

    gh config set prompt disabled
    gh release create "${release['version']}" $files --title "${release['name']}" --notes "${release['release-notes']}" --repo "${repo}" --target "$commit_ref"
}

### Main ###

file=$(readlink -f releases/target)
read_release_file
release_org=$(determine_org)
errors=0

create_release "${release_org}/releases" projects/submariner-operator/dist/subctl-* || errors=$((errors+1))

export GITHUB_TOKEN="${RELEASE_TOKEN}"

for project in ${PROJECTS[*]}; do
    clone_repo
    create_release "${release_org}/${project}" || errors=$((errors+1))
done

if [[ $errors > 0 ]]; then
    printerr "Encountered ${errors} errors while doing the release."
    exit 1
fi

