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

# Just check the USAGE section (first 17 lines) - the full help is ~98 lines
ACTUAL=$(run_coding_booth --help | head -18)

HERE="$PWD"
VERSION="$(cat ../../version.txt)"

EXPECT="\
codingbooth $VERSION — launch a Docker-based development booth.

USAGE:
  codingbooth [options]                    Run the current booth.
  codingbooth [options] [-- command ...]   Run the command inside the current booth.

OPTIONS
  --build-arg <KEY=VAL>   Add a Docker build-arg which customize the booth image.
  --variant <name>        Prebuilt variant: base | notebook | codeserver | xfce | kde
  --port <n|RANDOM|NEXT>  Host port → container 10000
  --daemon                Run the booth in the background
  --keep-alive            Do not remove the container when stopped
  --dind                  Enable a Docker-in-Docker sidecar
  --public                Bind to all interfaces with password authentication
  --sandboxed             Enable sandbox defaults (proxy + enforcement)

EXAMPLES:
  codingbooth --variant codeserver"

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
