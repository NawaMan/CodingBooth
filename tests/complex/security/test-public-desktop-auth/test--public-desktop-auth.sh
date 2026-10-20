#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Real LXQt/Wayland sessions behind the current wrapper and TLS proxy. Uses
# installed desktop dependencies, with this checkout's generated launchers.
# No downloads, host ports, or writable project mounts. Checks login, desktop
# WebSockets, loopback backend binds, session rotation, and private mode.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
source ../../../common--source.sh
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
VERSION="$(tr -d ' \t\n\r' < "$REPO_ROOT/version.txt")"
NAME="public-desktop-auth-$$"
CREATED=false
cleanup() {
  if [[ "$CREATED" == true ]]; then docker rm -f "$NAME" >/dev/null 2>&1 || true; fi
}
trap cleanup EXIT

docker info >/dev/null
case_num=0
for desktop in lxqt wayland; do
  case_num=$((case_num + 1))
  if [[ "$desktop" == lxqt ]]; then
    image="${CB_LXQT_IMAGE:-nawaman/codingbooth:desktop-lxqt-${VERSION}}"
  else
    image="${CB_WAYLAND_IMAGE:-nawaman/codingbooth:desktop-wayland-${VERSION}}"
  fi
  docker image inspect "$image" >/dev/null 2>&1 || docker pull -q "$image" >/dev/null
  docker create --name "$NAME" --network none --hostname cb-auth.test \
    --add-host cb-auth.test:127.0.0.1 --shm-size 1g \
    --mount "type=bind,src=$REPO_ROOT,dst=/review,readonly" \
    --entrypoint bash "$image" \
    /review/tests/complex/security/test-public-desktop-auth/in-container.sh "$desktop" >/dev/null
  CREATED=true
  # docker start -a does not consistently forward the container's exit code.
  docker start -a "$NAME"
  status=$(docker inspect --format '{{.State.ExitCode}}' "$NAME")
  if [[ "$status" != 0 ]]; then
    print_test_result false "$0" "$case_num" "$desktop public authentication lifecycle"
    exit 1
  fi
  print_test_result true "$0" "$case_num" "$desktop public authentication lifecycle"
  docker rm "$NAME" >/dev/null
  CREATED=false
done
