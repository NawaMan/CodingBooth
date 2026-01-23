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

HERE="$CURRENT_PATH"
VERSION="$(cat ../../version.txt)"

export TIMEZONE="America/Toronto"

# Each entry is WANT_VARIANT:GOT_VARIANT
VARIANTS=(
  "base:base"
  "ide-notebook:ide-notebook"
  "ide-codeserver:ide-codeserver"
  "desktop-xfce:desktop-xfce"
  "desktop-kde:desktop-kde"

  # aliases
  "default:base"
  "ide:ide-codeserver"
  "desktop:desktop-xfce"
  "notebook:ide-notebook"
  "codeserver:ide-codeserver"
  "xfce:desktop-xfce"
  "kde:desktop-kde"
)

test_num=0
for entry in "${VARIANTS[@]}"; do
  test_num=$((test_num + 1))
  WANT_VARIANT="${entry%%:*}"
  GOT_VARIANT="${entry#*:}"

  ACTUAL=$(../../coding-booth --dryrun --variant "${WANT_VARIANT}" -- sleep 1)
  ACTUAL=$(printf "%s\n" "$ACTUAL")

  case "${GOT_VARIANT}" in
    base)           HAS_NOTEBOOK=false ; HAS_VSCODE=false ; HAS_DESKTOP=false ;;
    ide-notebook)   HAS_NOTEBOOK=true  ; HAS_VSCODE=false ; HAS_DESKTOP=false ;;
    ide-codeserver) HAS_NOTEBOOK=true  ; HAS_VSCODE=true  ; HAS_DESKTOP=false ;;
    desktop-*)      HAS_NOTEBOOK=true  ; HAS_VSCODE=true  ; HAS_DESKTOP=true  ;;
    *)              echo "Error: unknown variant '$VARIANT'." >&2 ; exit 1    ;;
  esac

  # Notice that there is not `-rm`
  EXPECT="\
docker \\
    run \\
    -i \\
    --rm \\
    --name dryrun \\
    -e 'HOST_UID=${HOST_UID}' \\
    -e 'HOST_GID=${HOST_GID}' \\
    -v ${HERE}:/home/coder/code \\
    -w /home/coder/code \\
    -p 10000:10000 \\
    -e 'CB_SETUPS=/opt/codingbooth/setups' \\
    -e 'CB_CONTAINER_NAME=dryrun' \\
    -e 'CB_DAEMON=false' \\
    -e 'CB_HOST_PORT=10000' \\
    -e 'CB_IMAGE_NAME=nawaman/codingbooth:${GOT_VARIANT}-${VERSION}' \\
    -e 'CB_RUNMODE=COMMAND' \\
    -e 'CB_VARIANT_TAG=${GOT_VARIANT}' \\
    -e 'CB_VERBOSE=false' \\
    -e 'CB_VERSION_TAG=${VERSION}' \\
    -e 'CB_CODE_PATH=${HERE}' \\
    -e 'CB_CODE_PORT=10000' \\
    -e 'CB_HAS_NOTEBOOK=${HAS_NOTEBOOK}' \\
    -e 'CB_HAS_VSCODE=${HAS_VSCODE}' \\
    -e 'CB_HAS_DESKTOP=${HAS_DESKTOP}' \\
    -e 'CB_VERSION=${VERSION}' \\
    -e 'CB_CONFIG_FILE=' \\
    -e 'CB_SCRIPT_NAME=coding-booth' \\
    -e 'CB_SCRIPT_DIR=${SCRIPT_DIR}' \\
    -e 'CB_LIB_DIR=${LIB_DIR}' \\
    -e 'CB_KEEP_ALIVE=false' \\
    -e 'CB_SILENCE_BUILD=false' \\
    -e 'CB_PULL=false' \\
    -e 'CB_DIND=false' \\
    -e 'CB_DOCKERFILE=' \\
    -e 'CB_PROJECT_NAME=dryrun' \\
    -e 'CB_TIMEZONE=America/Toronto' \\
    -e 'CB_PORT=NEXT' \\
    -e 'CB_ENV_FILE=' \\
    -e 'CB_HOST_UID=${HOST_UID}' \\
    -e 'CB_HOST_GID=${HOST_GID}' \\
    '--pull=never' \\
    -e 'TZ=America/Toronto' \\
    nawaman/codingbooth:${GOT_VARIANT}-${VERSION} \\
    bash -lc 'sleep 1'"

  if diff -u <(echo "$EXPECT" | normalize_output) <(echo "$ACTUAL" | normalize_output); then
    print_test_result "true" "$0" "$test_num" "variant '${WANT_VARIANT}' -> '${GOT_VARIANT}'"
  else
    print_test_result "false" "$0" "$test_num" "variant '${WANT_VARIANT}' -> '${GOT_VARIANT}'"
    echo "-------------------------------------------------------------------------------"
    echo "Expected (${WANT_VARIANT} -> ${GOT_VARIANT}):"
    echo "$EXPECT"
    echo "-------------------------------------------------------------------------------"
    echo "Actual:"
    echo "$ACTUAL"
    echo "-------------------------------------------------------------------------------"
    exit 1
  fi
done

print_test_result "true" "$0" "$((test_num + 1))" "All variants and aliases produced the expected docker command."
