#!/usr/bin/env bash

## Process command line flags ##

source ${SCRIPTS_DIR}/lib/shflags
DEFINE_string 'version' '' "The version to release (semver compliant)"

FLAGS "$@" || exit $?
eval set -- "${FLAGS_ARGV}"

version="${FLAGS_version}"

set -e

source ${DAPPER_SOURCE}/scripts/lib/image_defs
source ${DAPPER_SOURCE}/scripts/lib/utils
source ${SCRIPTS_DIR}/lib/debug_functions

### Functions: General ###

function validate() {
    is_semver $version
}

function create_initial() {
    echo "Creating initial release file ${file}"
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
