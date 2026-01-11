#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -euo pipefail

source ../common--source.sh

HOST_UID="$(id -u)"
HOST_GID="$(id -g)"

# Cross-shell PWD : Detect MSYS/Git Bash and convert to Windows path
CURRENT_PATH=$(pwd)
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
    # pwd -W returns C:/Users/... instead of /c/Users/...
    CURRENT_PATH="$(pwd -W)"
fi

HERE="$CURRENT_PATH"
VERSION="1.2.3"

export TIMEZONE="America/Toronto"

ACTUAL=$(../../workspace --dryrun --version $VERSION --variant base -- sleep 1)
ACTUAL=$(printf "%s\n" "$ACTUAL")

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
    -p 10000:10000 \\
    -e 'WS_SETUPS_DIR=/opt/workspace/setups' \\
    -e 'WS_CONTAINER_NAME=dryrun' \\
    -e 'WS_DAEMON=false' \\
    -e 'WS_HOST_PORT=10000' \\
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
    '--pull=never' \\
    -e 'TZ=America/Toronto' \\
    nawaman/workspace:base-${VERSION} \\
    bash -lc 'sleep 1'"

if diff -u <(echo "$EXPECT") <(echo "$ACTUAL"); then
  print_test_result "true" "$0" "1" "Version output matches expected"
else
  print_test_result "false" "$0" "1" "Version output matches expected"
  echo "-------------------------------------------------------------------------------"
  echo "Expected: "
  echo "$EXPECT"
  echo "-------------------------------------------------------------------------------"
  echo "Actual: "
  echo "$ACTUAL"
  echo "-------------------------------------------------------------------------------"
  exit 1
fi
