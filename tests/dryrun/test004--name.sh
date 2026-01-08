#!/bin/bash
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

export TIMEZONE="America/Toronto"

ACTUAL=$(../../workspace --variant base --dryrun --name test-container -- tree -C)

HERE="$CURRENT_PATH"
VERSION="$(cat ../../version.txt)"

EXPECT="\
docker \\
    run \\
    -i \\
    --rm \\
    --name test-container \\
    -e 'HOST_UID=${HOST_UID}' \\
    -e 'HOST_GID=${HOST_GID}' \\
    -v ${HERE}:/home/coder/workspace \\
    -w /home/coder/workspace \\
    -p 10000:10000 \\
    -e 'WS_SETUPS_DIR=/opt/workspace/setups' \\
    -e 'WS_CONTAINER_NAME=test-container' \\
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
    bash -lc 'tree -C'"

if diff -u <(echo "$EXPECT") <(echo "$ACTUAL"); then
  print_test_result "true" "$0" "1" "Name output matches expected"
else
  print_test_result "false" "$0" "1" "Name output matches expected"
  echo "-------------------------------------------------------------------------------"
  echo "Expected: "
  echo "$EXPECT"
  echo "-------------------------------------------------------------------------------"
  echo "Actual: "
  echo "$ACTUAL"
  echo "-------------------------------------------------------------------------------"
  exit 1
fi
