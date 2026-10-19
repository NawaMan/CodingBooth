#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# The exact versions of this example's apt packages, and whether they really came
# from the APT_SNAPSHOT freeze. Ubuntu's snapshot service mirrors only amd64/i386;
# on any other architecture (arm64 on Apple Silicon) `install apt` drops the pin
# and installs from the live archive, so the versions below are not frozen there.
set -euo pipefail

ARCH="$(dpkg --print-architecture)"

echo "Architecture: ${ARCH}"
if [[ -z "${APT_SNAPSHOT:-}" ]]; then
  echo "Resolved from: the live archive (no APT_SNAPSHOT)"
else
  case "$ARCH" in
    amd64|i386) echo "Resolved from: snapshot ${APT_SNAPSHOT} (frozen)" ;;
    *)
      echo "Resolved from: the live archive, NOT frozen — APT_SNAPSHOT=${APT_SNAPSHOT} is set"
      echo "               but Ubuntu has no ${ARCH} snapshots, so the build ignored it."
      echo "               Build with --platform linux/amd64 when the freeze has to hold."
      ;;
  esac
fi
echo
dpkg-query -W -f='${Package}\t${Version}\n' jq tree ripgrep
