#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -euo pipefail

source ../common--source.sh

HOST_UID="XXXXX"
HOST_GID="XXXXX"

# Cross-shell PWD : Detect MSYS/Git Bash and convert to Windows path
CURRENT_PATH=$(pwd)
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
    # pwd -W returns C:/Users/... instead of /c/Users/...
    CURRENT_PATH="$(pwd -W)"
fi

HERE="$CURRENT_PATH"
VERSION="$(cat ../../version.txt)"

function realpath() {
  local target="$1"
  (
    if [ -d "$target" ]; then
      cd -- "$target" 2>/dev/null || { printf '%s\n' "$target"; exit 0; }
      pwd -P
    else
      local dir base
      dir=$(dirname -- "$target")   || { printf '%s\n' "$target"; exit 0; }
      base=$(basename -- "$target") || { printf '%s\n' "$target"; exit 0; }
      cd -- "$dir" 2>/dev/null      || { printf '%s\n' "$target"; exit 0; }
      printf '%s/%s\n' "$(pwd -P)" "$base"
    fi
  )
}


ACTUAL=$(run_coding_booth --verbose --dryrun | grep -E '^[A-Z_]+:' | sort)

EXPECT="\
BUILD_ARGS: 
CB_VERSION:     $VERSION
CMDS:       
CODE_PATH:      $HERE
CODE_PORT:      10000
CONFIG_FILE:    
CONTAINER_ENV_FILE: 
CONTAINER_NAME: dryrun
DAEMON:         false
DIND:           false
DOCKER_FILE:    
DO_PULL:        false
DRYRUN:         true
HOST_GID:       $HOST_GID
HOST_PORT:      10000
HOST_UID:       $HOST_UID
IMAGE_MODE:     PREBUILT
IMAGE_NAME:     nawaman/codingbooth:base-$VERSION
KEEPALIVE:      false
LOCAL_BUILD:    false
PORT_GENERATED: true
PREBUILD_REPO:  nawaman/codingbooth
RUN_ARGS:   
SCRIPT_DIR:     $(realpath "$HERE/../..")
SCRIPT_NAME:    coding-booth
VARIANT:        base
VERSION:        $VERSION"

if diff -u <(echo "$EXPECT" | normalize_output) <(echo "$ACTUAL" | normalize_output); then
  print_test_result "true" "$0" "1" "Expected default variables"
else
  print_test_result "false" "$0" "1" "Expected default variables"
  echo "-------------------------------------------------------------------------------"
  echo "Expected: "
  echo "$EXPECT"
  echo "-------------------------------------------------------------------------------"
  echo "Actual: "
  echo "$ACTUAL"
  echo "-------------------------------------------------------------------------------"
  exit 1
fi

cat > test--.env <<EOF
EOF

cat > test--config.toml <<EOF
daemon = true
dind = true
dockerfile = "test--config.toml"
dryrun = true
env-file = "test--.env"
keep-alive = true
name = "test-container"
pull = true
variant = "base"
verbose = true
version = "$VERSION"
run-args = "-p;10005"
EOF



ACTUAL=$(run_coding_booth --config test--config.toml | grep -E '^[A-Z_]+:' | sort)

EXPECT="\
BUILD_ARGS: 
CB_VERSION:     ${VERSION}
CMDS:       
CODE_PATH:      $HERE
CODE_PORT:      10000
CONFIG_FILE:    $HERE/test--config.toml
CONTAINER_ENV_FILE: test--.env
CONTAINER_NAME: test-container
DAEMON:         true
DIND:           true
DOCKER_FILE:    test--config.toml
DO_PULL:        true
DRYRUN:         true
HOST_GID:       $HOST_GID
HOST_PORT:      10000
HOST_UID:       $HOST_UID
IMAGE_MODE:     LOCAL-BUILD
IMAGE_NAME:     codingbooth-local:dryrun-base-$VERSION
KEEPALIVE:      true
LOCAL_BUILD:    true
PORT_GENERATED: true
PREBUILD_REPO:  nawaman/codingbooth
RUN_ARGS:    \"-p\" \"10005\"
SCRIPT_DIR:     $(realpath "$HERE/../..")
SCRIPT_NAME:    coding-booth
VARIANT:        base
VERSION:        ${VERSION}"

if diff -u <(echo "$EXPECT" | normalize_output) <(echo "$ACTUAL" | normalize_output); then
  print_test_result "true" "$0" "2" "Override variables"
else
  print_test_result "false" "$0" "2" "Override variables"
  echo "-------------------------------------------------------------------------------"
  echo "Expected: "
  echo "$EXPECT"
  echo "-------------------------------------------------------------------------------"
  echo "Actual: "
  echo "$ACTUAL"
  echo "-------------------------------------------------------------------------------"
  exit 1
fi
