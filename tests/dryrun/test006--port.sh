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

PORT=7654

export TIMEZONE="America/Toronto"

ACTUAL=$(../../workspace --dryrun --port $PORT --variant base -- sleep 1)
ACTUAL=$(printf "%s\n" "$ACTUAL")

HERE="$CURRENT_PATH"
VERSION="$(cat ../../version.txt)"

# Notice that there is not `-rm`
EXPECT="\
docker \\
    run \\
    -i \\
    --rm \\
    --name dryrun \\
    -e 'HOST_UID=${HOST_UID}' \\
    -e 'HOST_GID=${HOST_GID}' \\
    -v ${HERE}:/home/coder/workspace \\
    -w /home/coder/workspace \\
    -p ${PORT}:10000 \\
    -e 'WS_SETUPS_DIR=/opt/workspace/setups' \\
    -e 'WS_CONTAINER_NAME=dryrun' \\
    -e 'WS_DAEMON=false' \\
    -e 'WS_HOST_PORT=${PORT}' \\
    -e 'WS_IMAGE_NAME=nawaman/workspace:base-${VERSION}' \\
    -e 'WS_RUNMODE=COMMAND' \\
    -e 'WS_VARIANT_TAG=base' \\
    -e 'WS_VERBOSE=false' \\
    -e 'WS_VERSION_TAG=${VERSION}' \\
    -e 'WS_WORKSPACE_PATH=${HERE}' \\
    -e 'WS_WORKSPACE_PORT=10000' \\
    -e 'WS_HAS_NOTEBOOK=false' \\
    -e 'WS_HAS_VSCODE=false' \\
    -e 'WS_HAS_DESKTOP=false' \\
    -e 'WS_WS_VERSION=${VERSION}' \\
    -e 'WS_CONFIG_FILE=${HERE}/ws--config.toml' \\
    -e 'WS_SCRIPT_NAME=workspace' \\
    -e 'WS_SCRIPT_DIR=${SCRIPT_DIR}' \\
    -e 'WS_LIB_DIR=${LIB_DIR}' \\
    -e 'WS_KEEP_ALIVE=false' \\
    -e 'WS_SILENCE_BUILD=false' \\
    -e 'WS_PULL=false' \\
    -e 'WS_DIND=false' \\
    -e 'WS_DOCKERFILE=' \\
    -e 'WS_PROJECT_NAME=dryrun' \\
    -e 'WS_TIMEZONE=America/Toronto' \\
    -e 'WS_PORT=${PORT}' \\
    -e 'WS_ENV_FILE=' \\
    -e 'WS_HOST_UID=${HOST_UID}' \\
    -e 'WS_HOST_GID=${HOST_GID}' \\
    '--pull=never' \\
    -e 'TZ=America/Toronto' \\
    nawaman/workspace:base-${VERSION} \\
    bash -lc 'sleep 1'"

if diff -u <(echo "$EXPECT" | normalize_output) <(echo "$ACTUAL" | normalize_output); then
  print_test_result "true" "$0" "1" "Port output matches expected"
else
  print_test_result "false" "$0" "1" "Port output matches expected"
  echo "-------------------------------------------------------------------------------"
  echo "Expected: "
  echo "$EXPECT"
  echo "-------------------------------------------------------------------------------"
  echo "Actual: "
  echo "$ACTUAL"
  echo "-------------------------------------------------------------------------------"
  exit 1
fi
