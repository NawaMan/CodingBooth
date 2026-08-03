#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
#
# viewmd-desktop-icon--setup.sh — give viewmd a desktop launcher.
#
# This is a separate setup rather than a few lines at the end of
# viewmd--setup.sh because of *when* each runs. viewmd is installed into the
# **base** image, where no desktop environment exists yet, so cb-web-icon.sh
# would correctly no-op there and the icon would never appear on any variant.
# The desktop variants build on top of base and run this afterwards, by which
# point cb-has-desktop.sh passes.
#
# Clicking the icon starts viewmd if it is not already serving — cb-web-open
# handles that via START_CMD — so nothing has to be auto-started at boot.

set -Eeuo pipefail

VIEWMD_PORT="${1:-8765}"          # viewmd's own default
VIEWMD_FOLDER="${2:-/home/coder/code}"   # the project mount, as booth -w sets it

command -v viewmd >/dev/null 2>&1 || {
  echo "⚠️  viewmd is not installed; skipping its desktop icon." >&2
  exit 0
}

# A starter with the folder and port baked in, so the launcher (and anyone at a
# shell) has one obvious way to serve the project's Markdown. Foreground, not
# --daemon: cb-web-open backgrounds it itself and then waits for the port.
STARTER_FILE="/usr/local/bin/start-viewmd"
cat > "$STARTER_FILE" <<STARTER
#!/usr/bin/env bash
set -euo pipefail

PORT=\${1:-${VIEWMD_PORT}}
FOLDER=\${2:-${VIEWMD_FOLDER}}

# Fall back to \$HOME when the project mount is absent (e.g. a booth started
# without a code directory) so the launcher still opens something.
[ -d "\$FOLDER" ] || FOLDER="\$HOME"

echo "Starting viewmd on http://localhost:\$PORT (folder: \$FOLDER) ..."
exec viewmd --folder "\$FOLDER" --port "\$PORT"
STARTER
chmod 755 "$STARTER_FILE"

# viewmd ships no icon of its own (a single Go binary), so a themed document
# icon it is — honest about what the launcher opens.
cb-web-icon.sh --id viewmd --name "Markdown Viewer" --icon x-office-document \
  --port "${VIEWMD_PORT}" --path / --start start-viewmd

echo "✅ viewmd desktop icon registered."
echo "   Port:    ${VIEWMD_PORT}"
echo "   Folder:  ${VIEWMD_FOLDER}"
echo "   Starter: ${STARTER_FILE}"
