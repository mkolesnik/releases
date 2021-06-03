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
    if [[ -z "${release['status']}" ]]; then
        write "status: $1"
        return
    fi

    sed -i -E "s/(status: ).*/\1$1/" $file
}

function write_component() {
    local project=${1:-${project}}
    clone_repo
    checkout_project_branch
    write "  ${project}: $(_git rev-parse HEAD)"
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

    # We're not branching, so just move on to shipyard
    advance_branch
}

function advance_branch() {
    set_status "shipyard"
    write "components:"
    write_component "shipyard"
}

function advance_shipyard() {
    set_status "admiral"
    write_component "admiral"
}

function advance_admiral() {
    set_status "projects"
    for project in ${OPERATOR_CONSUMES[*]}; do
        write_component
    done
}

function advance_projects() {
    set_status "released"
    write_component "submariner-operator"
    write_component "submariner-charts"
}

function advance_stage() {
    echo "Advancing release to the next stage (file=${file})"

    read_release_file
    case "${release['status']}" in
    branch|shipyard|admiral|projects)
        advance_${release['status']}
        ;;
    released)
        echo "The release ${version} has been released, nothing to do."
        ;;
    *)
        printerr "Unknown status '${release['status']}'"
        exit 1
        ;;
    esac
}

validate
extract_semver "$version"
file="releases/v${version}.yaml"
if [[ ! -f "${file}" ]]; then
    create_initial
else
    advance_stage
fi
