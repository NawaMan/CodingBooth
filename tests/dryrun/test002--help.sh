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

ACTUAL=$(../../workspace --help | head)

HERE="$PWD"
VERSION="$(cat ../../version.txt)"

EXPECT="\
workspace — launch a Docker-based development workspace (version $VERSION)

USAGE:
  workspace version                              (print the workspace version)
  workspace help                                 (show this help and exit)
  workspace run [options] [--] [command ...]     (run the workspace)
  workspace [options] [--] [command ...]         (default action: run)

BOOTSTRAP OPTIONS (CLI or defaults; evaluated before environmental variable and config file):
  --workspace <path>     Host workspace path to mount at /home/coder/workspace"

if diff -u <(echo "$EXPECT") <(echo "$ACTUAL"); then
  print_test_result "true" "$0" "1" "Help output matches expected"
else
  print_test_result "false" "$0" "1" "Help output matches expected"
  echo "-------------------------------------------------------------------------------"
  echo "Expected: "
  echo "$EXPECT"
  echo "-------------------------------------------------------------------------------"
  echo "Actual: "
  echo "$ACTUAL"
  echo "-------------------------------------------------------------------------------"
  exit 1
fi
