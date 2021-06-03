#!/usr/bin/env bash

## Process command line flags ##

source ${SCRIPTS_DIR}/lib/shflags
DEFINE_string 'version' '' "The version to release (semver compliant)"
DEFINE_string 'release_notes' '' "Release notes to include"

FLAGS "$@" || exit $?
eval set -- "${FLAGS_ARGV}"

version="${FLAGS_version}"
release_notes="${FLAGS_release_notes}"

set -e

source ${DAPPER_SOURCE}/scripts/lib/image_defs
source ${DAPPER_SOURCE}/scripts/lib/utils
source ${SCRIPTS_DIR}/lib/debug_functions

### Functions: General ###

function validate() {
    is_semver "$version"
}

function write() {
    echo "$*" >> ${file}
}

function set_stable_branch() {
    write "branch: release-${semver['major']}.${semver['minor']}"
}

function set_status() {
    write "status: $1"
}

function init_components() {
    local project=shipyard
    clone_repo
    checkout_project_branch
    write "components:"
    write "  shipyard: $(_git rev-parse HEAD)"
}

function create_initial() {
    declare -gA release
    echo "Creating initial release file ${file}"
    cat > ${file} <<EOF
---
version: v${version}
name: ${version}
release-notes: ${release_notes}
EOF

    extract_semver "$version"
 
    # On GA we'll branch out first
    if [[ -z "${semver['pre']}" ]]; then
        set_stable_branch
        set_status "branch"
        return
    fi

    # Detect stable branch and set it if necessary
    if git rev-parse "v${semver['major']}.${semver['minor']}.0" 2&> /dev/null ; then
        release['branch']="release-${semver['major']}.${semver['minor']}"
        set_stable_branch
    fi

    set_status "shipyard"
    init_components
}

function advance_stage() {
    echo "Advancing release to the next stage (file=${file})"
}

validate
file="releases/v${version}.yaml"
if [[ ! -f "${file}" ]]; then
    create_initial
else
    advance_stage
fi
