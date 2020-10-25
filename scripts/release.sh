#!/usr/bin/env bash

set -e

source ${DAPPER_SOURCE}/scripts/lib/image_defs
source ${DAPPER_SOURCE}/scripts/lib/utils
source ${SCRIPTS_DIR}/lib/debug_functions

### Functions ###

function determine_repo() {
    origin_url=$(git config --get remote.origin.url)
    if [[ "$origin_url" =~ ^https:.* ]]; then
        echo "$origin_url" | cut -f 4 -d'/'
    elif [[ "$origin_url" =~ ^git@.* ]]; then
        echo "$origin_url" | cut -f 4- -d'/' | cut -f 1 -d '.'
    else
        printerr "Can't parse origin URL to extract origin repo: ${origin_url}"
        return 1
    fi
}

function create_release() {
    gh config set prompt disabled
    gh release create "${release['version']}" projects/submariner-operator/dist/subctl-* --title "${release['name']}" --notes "${release['release-notes']}"
}

function release_project() {
    clone_repo
    commit_ref=$(_git rev-parse --verify HEAD)
    gh release create "${release['version']}" --title "${release['name']}" --notes "${release['release-notes']}" --repo "${release_repo}/${project}" --target "$commit_ref"
}

function tag_images() {
    images=""

    # Creating a local tag so that images are uploaded with it
    git tag -f "${release['version']}"

    for project in ${PROJECTS[*]}; do
        for image in ${project_images[${project}]}; do
            images+=" $image"
        done
    done

    make release RELEASE_ARGS="$images --tag ${release['version']}"
}

### Main ###

file=$(readlink -f releases/target)
read_release_file
release_repo=$(determine_repo)
errors=0

create_release || errors=$((errors+1))

export GITHUB_TOKEN="${RELEASE_TOKEN}"

for project in ${PROJECTS[*]}; do
    release_project || errors=$((errors+1))
done

tag_images || errors=$((errors+1))

if [[ $errors > 0 ]]; then
    printerr "Encountered ${errors} errors while doing the release."
    exit 1
fi

