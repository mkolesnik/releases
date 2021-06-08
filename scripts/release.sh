#!/usr/bin/env bash

## Process command line flags ##

source ${SCRIPTS_DIR}/lib/shflags
DEFINE_boolean 'dryrun' false "Set to 'true' to run without affecting any online repositories"
DEFINE_string 'version' '' "The version to release (semver compliant)"
DEFINE_string 'release_notes' '' "Release notes to include"

FLAGS "$@" || exit $?
eval set -- "${FLAGS_ARGV}"

[[ "${FLAGS_dryrun}" = "${FLAGS_TRUE}" ]] && dryrun=true || dryrun=false
version="${FLAGS_version}"
release_notes="${FLAGS_release_notes}"
declare -A next_status=( [branch]=shipyard [shipyard]=admiral [admiral]=projects [projects]=released )

set -e

source ${DAPPER_SOURCE}/scripts/lib/image_defs
source ${DAPPER_SOURCE}/scripts/lib/utils
source ${SCRIPTS_DIR}/lib/debug_functions

### Functions: General ###

function expect_env() {
    local env_var="$1"
    if [[ -z "${!env_var}" ]]; then
        printerr "Expected environment variable ${env_var@Q} is not set"
        exit 1
    fi
}

function validate() {
    is_semver "$version"
    expect_env "GITHUB_TOKEN"
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

function create_pr() {
    local branch="$1"
    local msg="$2"
    local base_branch="${release['branch']:-devel}"
    local project="$(basename $(pwd))"
    #local repo="submariner-io/${project}"
    local repo="mkolesnik/${project}"

    git add "${file}"
    git commit -s -m "${msg}"
    dryrun git push -f "https://${GITHUB_TOKEN}:x-oauth-basic@github.com/${ORG}/${project}.git" "HEAD:${branch}"
    local pr_to_review=$(dryrun gh pr create --repo "${repo}" --head "${branch}" --base "${base_branch}" --title "${msg}" --body "${msg}")
    dryrun gh pr merge --auto --repo "${repo}" --rebase "${pr_to_review}" \
        || echo "WARN: Failed to enable auto merge on ${pr_to_review}"
    echo "Created Pull Request: ${pr_to_review}"
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
    set_status "shipyard"
    advance_branch
}

function advance_branch() {
    write "components:"
    write_component "shipyard"
}

function advance_shipyard() {
    write_component "admiral"
}

function advance_admiral() {
    for project in ${OPERATOR_CONSUMES[*]}; do
        write_component
    done
}

function advance_projects() {
    write_component "submariner-operator"
    write_component "submariner-charts"
}

function advance_stage() {
    echo "Advancing release to the next stage (file=${file})"

    read_release_file
    case "${release['status']}" in
    branch|shipyard|admiral|projects)
        local next="${next_status[${release['status']}]}"
        set_status "${next}"
        advance_${release['status']}
        create_pr "releasing-${version}" "Advancing ${version} release to status: ${next}"
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
    create_pr "releasing-${version}" "Initiating release of ${version}"
else
    advance_stage
fi
