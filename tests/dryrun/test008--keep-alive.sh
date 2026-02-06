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

ACTUAL=$(run_coding_booth --dryrun --keep-alive --variant base -- sleep 1)
ACTUAL=$(printf "%s\n" "$ACTUAL")

HERE="$CURRENT_PATH"
VERSION="$(cat ../../version.txt)"

# Notice that there is not `-rm`
EXPECT="\
docker \\
    ps \\
    -a \\
    --filter 'name=^dryrun\$' \\
    --format '{{.Names}}'
docker \\
    run \\
    -i \\
    --name dryrun \\
    -e 'HOST_UID=${HOST_UID}' \\
    -e 'HOST_GID=${HOST_GID}' \\
    -v ${HERE}:/home/coder/code \\
    -w /home/coder/code \\
    --label 'cb.managed=true' \\
    --label 'cb.project=dryrun' \\
    --label 'cb.variant=base' \\
    --label 'cb.code-path=${HERE}' \\
    --label 'cb.created-at=XXXXX' \\
    --label 'cb.version=${VERSION}' \\
    --label 'cb.keep-alive=true' \\
    -p 10000:10000 \\
    -e 'BOOTH_SETUPS=/opt/codingbooth/setups' \\
    -e 'BOOTH_CONTAINER_NAME=dryrun' \\
    -e 'BOOTH_DAEMON=false' \\
    -e 'BOOTH_HOST_PORT=10000' \\
    -e 'BOOTH_IMAGE_NAME=nawaman/codingbooth:base-${VERSION}' \\
    -e 'BOOTH_RUNMODE=COMMAND' \\
    -e 'BOOTH_VARIANT_TAG=base' \\
    -e 'BOOTH_VERBOSE=false' \\
    -e 'BOOTH_VERSION_TAG=${VERSION}' \\
    -e 'BOOTH_CODE_PATH=${HERE}' \\
    -e 'BOOTH_CODE_PORT=10000' \\
    -e 'BOOTH_VERSION=${VERSION}' \\
    -e 'BOOTH_CONFIG_FILE=' \\
    -e 'BOOTH_SCRIPT_NAME=codingbooth' \\
    -e 'BOOTH_SCRIPT_DIR=${SCRIPT_DIR}' \\
    -e 'BOOTH_LIB_DIR=${LIB_DIR}' \\
    -e 'BOOTH_KEEP_ALIVE=true' \\
    -e 'BOOTH_SILENCE_BUILD=false' \\
    -e 'BOOTH_PULL=false' \\
    -e 'BOOTH_DIND=false' \\
    -e 'BOOTH_SANDBOX=false' \\
    -e 'BOOTH_DOCKERFILE=' \\
    -e 'BOOTH_PROJECT_NAME=dryrun' \\
    -e 'BOOTH_TIMEZONE=America/Toronto' \\
    -e 'BOOTH_PORT=NEXT' \\
    -e 'BOOTH_ENV_FILE=' \\
    -e 'BOOTH_HOST_UID=${HOST_UID}' \\
    -e 'BOOTH_HOST_GID=${HOST_GID}' \\
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
