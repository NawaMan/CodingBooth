#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
#
# sales-explorer-icon--setup.sh — give the Sales Explorer dashboard a desktop
# icon, the same way JupyterLab gets one.
#
# The dashboard is *not* auto-started at boot. Clicking the icon builds it if
# needed (npm install), starts it, and opens it in a browser window —
# cb-web-open does the start-if-not-listening dance from the descriptor this
# script registers, exactly as it does for "Jupyter Notebook".
#
# Workspace-local setup: it lives in .booth/setups/, and the matching
# `setup sales-explorer-icon` line is emitted into the Boothfile by the
# project-local template in .booth/templates/project/sales-explorer/ — so
# `booth config` (TUI or CLI) still owns the Boothfile end to end.

set -Eeuo pipefail
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (use sudo)"; exit 1; }

SALES_PORT="${1:-13000}"                    # matches config.toml's +3000:13000
SALES_DIR="${2:-/home/coder/code/sales-explorer}"

# ---- starter: one obvious way to build + run the dashboard ------------------
# Delegates to the workspace's own start-server.sh, which installs node_modules
# on first run and then daemonises the server (PID + log in $HOME). Keeping the
# logic there means the shell and the desktop icon start it the same way.
STARTER_FILE="/usr/local/bin/start-sales-explorer"
cat > "$STARTER_FILE" <<STARTER
#!/usr/bin/env bash
set -euo pipefail

DIR="\${1:-\${HOME:-/home/coder}/code/sales-explorer}"
[ -d "\$DIR" ] || DIR="${SALES_DIR}"

if [ ! -x "\$DIR/start-server.sh" ]; then
  echo "❌ Sales Explorer not found at \$DIR — is the project mounted?" >&2
  exit 1
fi

exec "\$DIR/start-server.sh"
STARTER
chmod 755 "$STARTER_FILE"

# ---- icon artwork ----------------------------------------------------------
# The dashboard ships no artwork of its own, so draw a small bar-chart mark
# rather than settle for a generic globe. cb-web-icon.sh copies any --icon that
# is a file into a stable location and references it by absolute path.
ICON_SRC="/tmp/sales-explorer-icon.svg"
cat > "$ICON_SRC" <<'SVG'
<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="64" height="64">
  <rect x="2" y="2" width="60" height="60" rx="12" fill="#1f4e79"/>
  <rect x="12" y="34" width="8" height="16" rx="2" fill="#7fd1e8"/>
  <rect x="24" y="26" width="8" height="24" rx="2" fill="#7fd1e8"/>
  <rect x="36" y="18" width="8" height="32" rx="2" fill="#ffd166"/>
  <rect x="48" y="28" width="8" height="22" rx="2" fill="#7fd1e8"/>
  <path d="M12 28 L28 20 L40 12 L54 18" fill="none" stroke="#ffffff"
        stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
SVG

# ---- register the launcher -------------------------------------------------
# No --port-env: 13000 is baked into config.toml's `+3000:13000` publish, so a
# runtime override would only desync the icon from the host mapping.
cb-web-icon.sh --id sales-explorer --name "Sales Explorer" --icon "$ICON_SRC" \
  --port "${SALES_PORT}" --path / --start start-sales-explorer

rm -f "$ICON_SRC"

echo "✅ Sales Explorer desktop icon registered."
echo "   Port:    ${SALES_PORT}"
echo "   Project: ${SALES_DIR}"
echo "   Starter: ${STARTER_FILE}"
