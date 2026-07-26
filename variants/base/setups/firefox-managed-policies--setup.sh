#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# firefox-managed-policies--setup.sh — sample enterprise policies for Firefox
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO" >&2; exit 1' ERR

if [[ $EUID -ne 0 ]]; then
  echo "❌ This script must be run as root (use sudo)" >&2
  exit 1
fi

install -d -m 0755 /etc/firefox/policies
cat > /etc/firefox/policies/policies.json <<'EOF'
{
  "policies": {
    "DisplayBookmarksToolbar": "always",
    "PasswordManagerEnabled": false,
    "DisableTelemetry": true,
    "Homepage": {
      "URL": "about:home",
      "StartPage": "homepage"
    }
  }
}
EOF
chmod 0644 /etc/firefox/policies/policies.json
echo "✅ Firefox managed policies → /etc/firefox/policies/policies.json"
