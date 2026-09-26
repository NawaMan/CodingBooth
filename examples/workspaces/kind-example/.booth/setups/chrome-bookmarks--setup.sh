#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Workspace-local setup: pre-seeds Chrome's "Managed bookmarks" folder with the
# two services this example's Quick start deploys, via Chrome's ManagedBookmarks
# enterprise policy (https://chromeenterprise.google/policies/#ManagedBookmarks)
# — a build-time JSON policy file, not a live browser-profile edit, so it needs
# no running Chrome and survives every fresh booth the same way. Shows up as a
# folder on the bookmarks bar the first time Chrome opens.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO while running: $BASH_COMMAND" >&2' ERR

[[ $EUID -eq 0 ]] || { echo "❌ Run as root (use sudo)" >&2; exit 1; }

POLICY_JSON='{
  "ManagedBookmarks": [
    {"toplevel_name": "KinD Example"},
    {"name": "nginx (NodePort 30080)", "url": "http://localhost:30080"},
    {"name": "hello-service (NodePort 30081)", "url": "http://localhost:30081"}
  ]
}'

install_policy() {
  local dir="$1"
  install -d -m 0755 "${dir}"
  printf '%s\n' "${POLICY_JSON}" > "${dir}/kind-example-bookmarks.json"
  chmod 0644 "${dir}/kind-example-bookmarks.json"
  echo "✅ Chrome bookmarks policy → ${dir}/kind-example-bookmarks.json"
}

if [[ -d /opt/google/chrome ]] || command -v google-chrome-stable >/dev/null 2>&1 || [[ -x /usr/local/bin/google-chrome ]]; then
  install_policy /etc/opt/chrome/policies/managed
else
  # Still install under Chrome's path so a later Chrome install can pick it up.
  install_policy /etc/opt/chrome/policies/managed
  echo "ℹ️  No Chrome binary yet; policy written for later use."
fi
