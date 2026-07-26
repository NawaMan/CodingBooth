#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# chrome-managed-policies--setup.sh — sample enterprise policies for Chrome/Chromium
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO" >&2; exit 1' ERR

if [[ $EUID -ne 0 ]]; then
  echo "❌ This script must be run as root (use sudo)" >&2
  exit 1
fi

POLICY_JSON='{
  "BookmarkBarEnabled": true,
  "RestoreOnStartup": 5,
  "HomepageIsNewTabPage": true,
  "PasswordManagerEnabled": false,
  "BrowserSignin": 0,
  "SyncDisabled": true
}'

install_policy() {
  local dir="$1"
  install -d -m 0755 "${dir}"
  printf '%s\n' "${POLICY_JSON}" > "${dir}/codingbooth-team.json"
  chmod 0644 "${dir}/codingbooth-team.json"
  echo "✅ Chrome managed policy → ${dir}/codingbooth-team.json"
}

installed=0
if [[ -d /opt/google/chrome ]] || command -v google-chrome-stable >/dev/null 2>&1 || [[ -x /usr/local/bin/google-chrome ]]; then
  install_policy /etc/opt/chrome/policies/managed
  installed=1
fi
if command -v chromium >/dev/null 2>&1 || command -v chromium-browser >/dev/null 2>&1; then
  install_policy /etc/chromium/policies/managed
  installed=1
fi

if [[ "${installed}" -eq 0 ]]; then
  # Still install under Chrome path so a later browser install can pick it up
  install_policy /etc/opt/chrome/policies/managed
  echo "ℹ️  No Chrome/Chromium binary yet; policies written for later use."
fi
