#!/usr/bin/env bash

set -e

source ${DAPPER_SOURCE}/scripts/lib/utils
source ${SCRIPTS_DIR}/lib/debug_functions

### Functions ###

function validate_release_fields() {
    local missing=0

    function _validate() {
        local key=$1

        if [[ -z "${release[$key]}" ]]; then
            printerr "Missing value for ${key@Q}"
            missing=$((missing+1))
        fi
    }

    _validate 'version'
    _validate 'name'
    _validate 'release-notes'
    _validate 'status'
    _validate 'components'

    case "${release['status']}" in
    shipyard)
        _validate "components.shipyard"
        ;;
    admiral)
        _validate "components.admiral"
        ;;
    projects)
        for project in ${OPERATOR_CONSUMES[*]}; do
            _validate "components.${project}"
        done
        ;;
    released)
        for project in ${PROJECTS[*]}; do
            _validate "components.${project}"
        done
        ;;
    *)
        printerr "Status '${release['status']}' should be one of: 'shipyard', 'admiral', 'projects' or 'released'."
        return 2
        ;;
    esac

    if [[ $missing -gt 0 ]]; then
        printerr "Missing values for ${missing} fields"
        return 1
    fi
}

function validate_admiral_consumers() {
    local expected_version="$1"
    for project in ${ADMIRAL_CONSUMERS[*]}; do
        local actual_version=$(grep admiral "projects/${project}/go.mod" | cut -f2 -d' ')
        if [[ "${expected_version}" != "${actual_version}" ]]; then
            printerr "Expected Admiral version ${expected_version} but found ${actual_version} in ${project}"
            return 1
        fi
    done
}

function validate_shipyard_consumers() {
    local expected_version="$1"
    for project in ${SHIPYARD_CONSUMERS[*]}; do
        local actual_version=$(head -1 "projects/${project}/Dockerfile.dapper" | cut -f2 -d':')
        if [[ "${expected_version}" != "${actual_version}" ]]; then
            printerr "Expected Shipyard version ${expected_version} but found ${actual_version} in ${project}"
            return 1
        fi
    done
}

function validate_release() {
    validate_release_fields

    local version=${release['version']}
    if ! git check-ref-format "refs/tags/${version}"; then
        printerr "Version ${version@Q} is not a valid tag name"
        return 1
    fi

    local pre_release="${release['pre-release']}"
    if [[ "$pre_release" = "true" ]] && [[ ! "$version" =~ -[0-9a-z\.]+$ ]]; then
        printerr "Version ${version@Q} should have a hyphen followed by identifiers as it's marked as pre-release"
        return 1
    fi

    if [[ "$pre_release" != "true" ]] && [[ "$version" =~ - ]]; then
        printerr "Version ${version@Q} should not have a hyphen as it isn't marked as pre-release"
        return 1
    fi

    case "${release['status']}" in
    shipyard)
        clone_repo shipyard
    admiral)
        clone_repo admiral
    projects)
        for project in ${OPERATOR_CONSUMES[*]}; do
            clone_repo
        done
        ;;
    released)
        for project in ${PROJECTS[*]}; do
            clone_repo
        done
        ;;
    esac

# TODO: Uncomment once we're using automated release which makes sure these are in sync
#    validate_admiral_consumers "${release["components.admiral"]}"
#    validate_shipyard_consumers "${release["components.shipyard"]#v}"
}

### Main ###

for file in $(find releases -type f); do
    read_release_file
    validate_release
done
