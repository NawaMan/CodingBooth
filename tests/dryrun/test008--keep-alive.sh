#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -euo pipefail

source ../common--source.sh

HOST_UID="XXXXX"
HOST_GID="XXXXX"

SCRIPT_DIR="$(cd ../.. && pwd)"
LIB_DIR="${SCRIPT_DIR}/libs"

# Cross-shell PWD : Detect MSYS/Git Bash and convert to Windows path
CURRENT_PATH=$(pwd)
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
    # pwd -W returns C:/Users/... instead of /c/Users/...
    CURRENT_PATH="$(pwd -W)"
fi

export TIMEZONE="America/Toronto"

ACTUAL=$(../../coding-booth --dryrun --keep-alive --variant base -- sleep 1)
ACTUAL=$(printf "%s\n" "$ACTUAL")

HERE="$CURRENT_PATH"
VERSION="$(cat ../../version.txt)"

# Notice that there is not `-rm`
EXPECT="\
docker \\
    run \\
    -i \\
    --name dryrun \\
    -e 'HOST_UID=${HOST_UID}' \\
    -e 'HOST_GID=${HOST_GID}' \\
    -v ${HERE}:/home/coder/code \\
    -w /home/coder/code \\
    -p 10000:10000 \\
    -e 'CB_SETUPS=/opt/codingbooth/setups' \\
    -e 'CB_CONTAINER_NAME=dryrun' \\
    -e 'CB_DAEMON=false' \\
    -e 'CB_HOST_PORT=10000' \\
    -e 'CB_IMAGE_NAME=nawaman/codingbooth:base-${VERSION}' \\
    -e 'CB_RUNMODE=COMMAND' \\
    -e 'CB_VARIANT_TAG=base' \\
    -e 'CB_VERBOSE=false' \\
    -e 'CB_VERSION_TAG=${VERSION}' \\
    -e 'CB_CODE_PATH=${HERE}' \\
    -e 'CB_CODE_PORT=10000' \\
    -e 'CB_HAS_NOTEBOOK=false' \\
    -e 'CB_HAS_VSCODE=false' \\
    -e 'CB_HAS_DESKTOP=false' \\
    -e 'CB_VERSION=${VERSION}' \\
    -e 'CB_CONFIG_FILE=' \\
    -e 'CB_SCRIPT_NAME=coding-booth' \\
    -e 'CB_SCRIPT_DIR=${SCRIPT_DIR}' \\
    -e 'CB_LIB_DIR=${LIB_DIR}' \\
    -e 'CB_KEEP_ALIVE=true' \\
    -e 'CB_SILENCE_BUILD=false' \\
    -e 'CB_PULL=false' \\
    -e 'CB_DIND=false' \\
    -e 'CB_DOCKERFILE=' \\
    -e 'CB_PROJECT_NAME=dryrun' \\
    -e 'CB_TIMEZONE=America/Toronto' \\
    -e 'CB_PORT=NEXT' \\
    -e 'CB_ENV_FILE=' \\
    -e 'CB_HOST_UID=${HOST_UID}' \\
    -e 'CB_HOST_GID=${HOST_GID}' \\
    '--pull=never' \\
    -e 'TZ=America/Toronto' \\
    nawaman/codingbooth:base-${VERSION} \\
    bash -lc 'sleep 1'"

if diff -u <(echo "$EXPECT" | normalize_output) <(echo "$ACTUAL" | normalize_output); then
  print_test_result "true" "$0" "1" "Keep-alive output matches expected"
else
  print_test_result "false" "$0" "1" "Keep-alive output matches expected"
  echo "-------------------------------------------------------------------------------"
  echo "Expected: "
  echo "$EXPECT"
  echo "-------------------------------------------------------------------------------"
  echo "Actual: "
  echo "$ACTUAL"
  echo "-------------------------------------------------------------------------------"
  exit 1
fi
