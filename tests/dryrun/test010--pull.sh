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

ACTUAL=$(../../coding-booth --dryrun --pull --variant base -- tree -C)
ACTUAL=$(printf "%s\n" "$ACTUAL" | head -n 3)

HERE="$CURRENT_PATH"
VERSION="$(cat ../../version.txt)"

EXPECT="\
docker \\
    pull \\
    nawaman/coding-booth:base-${VERSION}"

if diff -u <(echo "$EXPECT") <(echo "$ACTUAL"); then
  print_test_result "true" "$0" "1" "Pull output matches expected"
else
  print_test_result "false" "$0" "1" "Pull output matches expected"
  echo "-------------------------------------------------------------------------------"
  echo "Expected: "
  echo "$EXPECT"
  echo "-------------------------------------------------------------------------------"
  echo "Actual: "
  echo "$ACTUAL"
  echo "-------------------------------------------------------------------------------"
  exit 1
fi
