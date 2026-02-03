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

ACTUAL=$(run_coding_booth --help | head -11)

HERE="$PWD"
VERSION="$(cat ../../version.txt)"

EXPECT="\
codingbooth — launch a Docker-based development booth (version $VERSION)

USAGE:
  codingbooth version                              (print the CodingBooth version)
  codingbooth help                                 (show this help and exit)
  codingbooth run [options] [--] [command ...]     (run the booth)
  codingbooth [options] [--] [command ...]         (default action: run)
  codingbooth example <subcommand>                 (manage examples)

BOOTSTRAP OPTIONS (CLI or defaults; evaluated before environmental variable and config file):
  --code <path>          Host code path to mount at /home/coder/code"

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
