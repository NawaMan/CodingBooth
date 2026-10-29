#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# run.sh  (EXPERIMENT -- see docs/REUSE_BOOTH.md)
#
# The whole flow, run as the real (non-root, sudo-capable) user:
#   1. base-provision.sh      the base Dockerfile, as a script
#   2. provision-example.sh   the example's Boothfile, as a script
#   3. booth-entry            the CB_TARGET-guarded copy, as root, which ends by
#                             running check-go-example.sh as this user
#
# Usage: run.sh gha|host [example-dir]   (default: examples/workspaces/go-example)
# Report: $REPORT (default /tmp/host-provision-report.txt)
# -----------------------------------------------------------------------------

set -euo pipefail

TARGET="${1:?usage: run.sh gha|host [example-dir]}"
case "$TARGET" in gha|host) ;; *) echo "❌ target must be gha or host" >&2; exit 1 ;; esac
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
EXAMPLE="$(cd "${2:-$REPO/examples/workspaces/go-example}" && pwd)"
# Not /tmp: with fs.protected_regular, root cannot write a user-owned file in a sticky dir.
REPORT="${REPORT:-$HOME/host-provision-report.txt}"
[ "$(id -u)" -ne 0 ] || { echo "❌ Run as the real user, not root" >&2; exit 1; }

ME="$(id -un)"
: > "$REPORT"
echo "host-provision experiment: target=$TARGET user=$ME $(. /etc/os-release; echo "$PRETTY_NAME")" | tee -a "$REPORT"

time sudo env CB_TARGET="$TARGET" "$HERE/base-provision.sh" "$REPO"

time sudo env CB_TARGET="$TARGET" CB_USER_NAME="$ME" CB_USER_HOME="$HOME" REPORT="$REPORT" \
  "$HERE/provision-example.sh" "$EXAMPLE"

time sudo env \
  CB_TARGET="$TARGET" CB_USER_NAME="$ME" CB_USER_HOME="$HOME" CB_CODE_DIR="$EXAMPLE" \
  HOST_UID="$(id -u)" HOST_GID="$(id -g)" BOOTH_VERBOSE=true REPORT="$REPORT" \
  /usr/local/bin/booth-entry "$HERE/check-go-example.sh"

echo
echo "================ REPORT ================"
cat "$REPORT"
