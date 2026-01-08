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


ACTUAL=$(../../workspace --verbose --dryrun | grep -E '^[A-Z_]+:' | sort)

EXPECT="\
BUILD_ARGS: 
CMDS:       
CONFIG_FILE:    ${HERE}/ws--config.toml
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
IMAGE_NAME:     nawaman/workspace:ide-codeserver-$VERSION
KEEPALIVE:      false
LOCAL_BUILD:    false
PORT_GENERATED: true
PREBUILD_REPO:  nawaman/workspace
RUN_ARGS:   
SCRIPT_DIR:     $(realpath "$HERE/../..")
SCRIPT_NAME:    workspace
VARIANT:        ide-codeserver
VERSION:        $VERSION
WORKSPACE_PATH: $HERE
WORKSPACE_PORT: 10000
WS_VERSION:     $VERSION"

if diff -u <(echo "$EXPECT") <(echo "$ACTUAL"); then
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

cat > test--config.sh <<EOF
CONTAINER_ENV_FILE=test--.env
CONTAINER_NAME=test-container
DAEMON=true
DIND=true
DO_PULL=true
DOCKER_FILE=test--config.sh
DRYRUN=true
HOST_PORT=10005
IMAGE_MODE=EXISTING
IMAGE_NAME=test/workspace:codeserver-$VERSION
KEEPALIVE=true
LOCAL_BUILD=true
PORT_GENERATED=true
PREBUILD_REPO=nawaman/workspace
SCRIPT_DIR=..
SCRIPT_NAME=ws.sh
VARIANT=codeserver
VERSION=$VERSION
WORKSPACE_PATH=$HERE
WORKSPACE_PORT=10005
WS_VERSION=$VERSION
EOF



ACTUAL=$(../../workspace --verbose --dryrun --config test--config.toml | grep -E '^[A-Z_]+:' | sort)

EXPECT="\
BUILD_ARGS: 
CMDS:       
CONFIG_FILE:    ${HERE}/test--config.toml
CONTAINER_ENV_FILE: test--.env
CONTAINER_NAME: test-container
DAEMON:         true
DIND:           true
DOCKER_FILE:    test--config.sh
DO_PULL:        true
DRYRUN:         true
HOST_GID:       $HOST_GID
HOST_PORT:      10005
HOST_UID:       $HOST_UID
IMAGE_MODE:     EXISTING
IMAGE_NAME:     test/workspace:codeserver-${VERSION}
KEEPALIVE:      true
LOCAL_BUILD:    false
PORT_GENERATED: false
PREBUILD_REPO:  nawaman/workspace
RUN_ARGS:   
SCRIPT_DIR:     ..
SCRIPT_NAME:    ws.sh
VARIANT:        ide-codeserver
VERSION:        ${VERSION}
WORKSPACE_PATH: $HERE
WORKSPACE_PORT: 10005
WS_VERSION:     ${VERSION}"

if diff -u <(echo "$EXPECT") <(echo "$ACTUAL"); then
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
