#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# playground-firebase override of `setup firebase`.
#
# 1. Run the product firebase installer from the base image.
# 2. Re-install the credential startup that replaces empty / "{}" placeholders
#    with the host-seeded firebase-tools.json (see variants/base/setups/firebase--setup.sh).
#
# Once a published base image includes that startup, this project override can be
# deleted and Boothfile can keep `setup firebase` only.

set -Eeuo pipefail

PRODUCT="${PRODUCT_FIREBASE_SETUP:-/opt/codingbooth/setups/firebase--setup.sh}"
if [[ ! -x "$PRODUCT" ]]; then
  echo "❌ Product firebase setup not found: $PRODUCT" >&2
  exit 1
fi

echo "• playground-firebase: running product firebase setup..."
"$PRODUCT" "$@"

# ---- credential startup (placeholder-aware; matches product fix) ----
STARTUP_FILE="/usr/share/startup.d/60-cb-firebase--startup.sh"
cat > "${STARTUP_FILE}" <<'STARTUP'
#!/usr/bin/env bash
set -euo pipefail

# Firebase CLI credentials from host home-seed.
# Overwrite dest only when missing / empty / placeholder "{}" so a real
# in-container login is not clobbered, but host creds still win over stubs.

SEED_FILE="${CB_FIREBASE_SEED_FILE:-/etc/cb-home-seed/.config/configstore/firebase-tools.json}"
DEST_DIR="${HOME}/.config/configstore"
DEST_FILE="${DEST_DIR}/firebase-tools.json"

if [[ ! -f "$SEED_FILE" ]]; then
  exit 0
fi

need_copy=false
if [[ ! -f "$DEST_FILE" ]]; then
  need_copy=true
elif [[ ! -s "$DEST_FILE" ]]; then
  need_copy=true
else
  content="$(tr -d '[:space:]' <"$DEST_FILE" 2>/dev/null || true)"
  if [[ "$content" == "{}" ]]; then
    need_copy=true
  fi
fi

if [[ "$need_copy" == true ]]; then
  mkdir -p "$DEST_DIR"
  cp "$SEED_FILE" "$DEST_FILE"
fi
STARTUP
chmod 755 "${STARTUP_FILE}"

echo "✅ playground-firebase: installed placeholder-aware Firebase credential startup → ${STARTUP_FILE}"
