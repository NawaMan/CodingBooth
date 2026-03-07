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

# ---- Test 1: Scalar string fields expand $VAR and ${VAR} ----

cat > test--.env <<EOF
EOF

export TEST_VARIANT="base"
export TEST_NAME="expanded-container"
export TEST_PORT="10007"
export TEST_DOCKERFILE="test--config.toml"
export TEST_ENV_FILE="test--.env"

cat > test--env-expand-config.toml <<EOF
daemon = true
dind = true
dockerfile = "\$TEST_DOCKERFILE"
dryrun = true
env-file = "\${TEST_ENV_FILE}"
keep-alive = true
name = "\$TEST_NAME"
port = "\${TEST_PORT}"
pull = true
variant = "\$TEST_VARIANT"
verbose = true
version = "$VERSION"
run-args = "-p;10005"
EOF


# Only check the fields we care about for env expansion
ACTUAL=$(run_coding_booth --config test--env-expand-config.toml \
  | grep -E '^(CONTAINER_NAME|HOST_PORT|DOCKER_FILE|CONTAINER_ENV_FILE|VARIANT):' \
  | sort)

EXPECT="\
CONTAINER_ENV_FILE: test--.env
CONTAINER_NAME: expanded-container
DOCKER_FILE:    test--config.toml
HOST_PORT:      10007
VARIANT:        base"

if diff -u <(echo "$EXPECT" | normalize_output) <(echo "$ACTUAL" | normalize_output); then
  print_test_result "true" "$0" "1" "Scalar fields expand env vars (\$VAR and \${VAR})"
else
  print_test_result "false" "$0" "1" "Scalar fields expand env vars (\$VAR and \${VAR})"
  echo "-------------------------------------------------------------------------------"
  echo "Expected: "
  echo "$EXPECT"
  echo "-------------------------------------------------------------------------------"
  echo "Actual: "
  echo "$ACTUAL"
  echo "-------------------------------------------------------------------------------"
  exit 1
fi

# ---- Test 2: Unset env vars expand to empty string ----

unset TEST_VARIANT TEST_NAME TEST_PORT TEST_DOCKERFILE TEST_ENV_FILE

cat > test--env-expand-unset-config.toml <<EOF
dryrun = true
verbose = true
name = "\${UNSET_VAR_FOR_TEST}"
EOF


ACTUAL=$(run_coding_booth --config test--env-expand-unset-config.toml | grep -E '^CONTAINER_NAME:')

EXPECT="CONTAINER_NAME: dryrun"

if diff -u <(echo "$EXPECT" | normalize_output) <(echo "$ACTUAL" | normalize_output); then
  print_test_result "true" "$0" "2" "Unset env var expands to empty (falls back to default)"
else
  print_test_result "false" "$0" "2" "Unset env var expands to empty (falls back to default)"
  echo "-------------------------------------------------------------------------------"
  echo "Expected: "
  echo "$EXPECT"
  echo "-------------------------------------------------------------------------------"
  echo "Actual: "
  echo "$ACTUAL"
  echo "-------------------------------------------------------------------------------"
  exit 1
fi
