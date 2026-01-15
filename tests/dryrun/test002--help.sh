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

if diff -u <(echo "$EXPECT" | normalize_output) <(echo "$ACTUAL" | normalize_output); then
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
