#!/usr/bin/env bash

set -e

source ${DAPPER_SOURCE}/scripts/lib/utils

file=$(readlink -f releases/target)
read_release_file

gh release create v1.2.3 -d
