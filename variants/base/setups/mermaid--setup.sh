#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [VERSION] [PORT]

Arguments:
  VERSION  Mermaid CLI version (default: 11.4.2)
  PORT     Port for the Mermaid live editor (default: 18090)

Examples:
  $0                    # install with defaults
  $0 11.4.2 18090       # specific version and port

Notes:
- Installs Node.js (if not present), Mermaid CLI (mmdc), and Mermaid Live Editor
- CLI available as 'mmdc' command for converting .mmd files to images
- Web UI available at http://localhost:<PORT>
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# This script will always be installed by root.
HOME=/root

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

# ---- defaults / args ----
MERMAID_VERSION="${1:-11.4.2}"
MERMAID_PORT="${2:-18090}"
MERMAID_DIR="/opt/mermaid"

STARTER_FILE="/usr/local/bin/start-mermaid"

# ---- check if nodejs is already installed ----
if command -v node >/dev/null 2>&1; then
  echo "• Node.js already installed: $(node --version)"
else
  SETUPS_DIR="/opt/codingbooth/setups"
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ -x "$SETUPS_DIR/nodejs--setup.sh" ]]; then
    echo "• Installing Node.js ..."
    "$SETUPS_DIR/nodejs--setup.sh" 20
  elif [[ -x "$SCRIPT_DIR/nodejs--setup.sh" ]]; then
    echo "• Installing Node.js ..."
    "$SCRIPT_DIR/nodejs--setup.sh" 20
  else
    echo "❌ nodejs--setup.sh not found"
    exit 1
  fi
fi

# ---- install Mermaid CLI ----
echo "• Installing Mermaid CLI (@mermaid-js/mermaid-cli@${MERMAID_VERSION}) ..."
npm install -g "@mermaid-js/mermaid-cli@${MERMAID_VERSION}"

# ---- build Mermaid Live Editor ----
echo "• Building Mermaid Live Editor ..."
mkdir -p "$MERMAID_DIR"

cat > "${MERMAID_DIR}/index.html" <<'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Mermaid Live Editor</title>
  <script type="module">
    import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@__MERMAID_VERSION__/dist/mermaid.esm.min.mjs';
    mermaid.initialize({ startOnLoad: false, theme: 'default' });

    const defaultDiagram = `graph TD
    A[Start] --> B{Decision}
    B -->|Yes| C[OK]
    B -->|No| D[Cancel]
    C --> E[End]
    D --> E`;

    window.addEventListener('DOMContentLoaded', () => {
      const editor = document.getElementById('editor');
      const preview = document.getElementById('preview');
      const exportBtn = document.getElementById('export-svg');

      editor.value = defaultDiagram;

      async function renderDiagram() {
        const code = editor.value.trim();
        if (!code) { preview.innerHTML = ''; return; }
        try {
          const { svg } = await mermaid.render('mermaid-preview', code);
          preview.innerHTML = svg;
        } catch (e) {
          preview.innerHTML = '<pre style="color:red;">' + e.message + '</pre>';
        }
      }

      editor.addEventListener('input', renderDiagram);

      exportBtn.addEventListener('click', () => {
        const svg = preview.querySelector('svg');
        if (!svg) return;
        const blob = new Blob([svg.outerHTML], { type: 'image/svg+xml' });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url; a.download = 'diagram.svg'; a.click();
        URL.revokeObjectURL(url);
      });

      renderDiagram();
    });
  </script>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { font-family: system-ui, sans-serif; height: 100vh; display: flex; flex-direction: column; }
    .toolbar { padding: 8px 16px; background: #2d3748; color: white; display: flex; align-items: center; gap: 12px; }
    .toolbar h1 { font-size: 16px; font-weight: 600; }
    .toolbar button { padding: 4px 12px; border-radius: 4px; border: 1px solid #4a5568; background: #4a5568; color: white; cursor: pointer; }
    .toolbar button:hover { background: #718096; }
    .main { display: flex; flex: 1; overflow: hidden; }
    #editor { width: 40%; padding: 16px; font-family: 'Fira Code', monospace; font-size: 14px; border: none; border-right: 2px solid #e2e8f0; resize: none; outline: none; }
    #preview { width: 60%; padding: 16px; overflow: auto; display: flex; align-items: flex-start; justify-content: center; }
    #preview svg { max-width: 100%; }
  </style>
</head>
<body>
  <div class="toolbar">
    <h1>Mermaid Live Editor</h1>
    <button id="export-svg">Export SVG</button>
  </div>
  <div class="main">
    <textarea id="editor" spellcheck="false" placeholder="Enter Mermaid diagram code..."></textarea>
    <div id="preview"></div>
  </div>
</body>
</html>
HTML
sed -i "s/__MERMAID_VERSION__/${MERMAID_VERSION}/g" "${MERMAID_DIR}/index.html"

# ---- install serve for hosting ----
if ! command -v serve >/dev/null 2>&1; then
  echo "• Installing serve ..."
  npm install -g serve
fi

# ---- create starter script ----
cat > "${STARTER_FILE}" <<'STARTER'
#!/usr/bin/env bash
set -euo pipefail

PORT=${1:-__MERMAID_PORT__}

echo "Starting Mermaid Live Editor on http://localhost:$PORT ..."
exec serve -s --no-clipboard /opt/mermaid -l "$PORT"
STARTER
sed -i "s/__MERMAID_PORT__/${MERMAID_PORT}/g" "${STARTER_FILE}"
chmod 755 "${STARTER_FILE}"

# ---- summary ----
echo ""
# Register a desktop icon that opens the Mermaid Live Editor in a browser
# (desktop variants only).
cb-web-icon.sh --id mermaid --name "Mermaid" --icon applications-internet \
  --port "${MERMAID_PORT}" --path / --start start-mermaid

echo "✅ Mermaid installed."
echo "   CLI Version: ${MERMAID_VERSION}"
echo "   CLI:         mmdc"
echo "   Web UI:      ${MERMAID_DIR}"
echo "   Port:        ${MERMAID_PORT}"
echo "   Starter:     ${STARTER_FILE}"
echo ""
echo "ℹ️  CLI usage:     mmdc -i diagram.mmd -o output.svg"
echo "   Web UI launch: start-mermaid [PORT]"
echo "   Access:        http://localhost:${MERMAID_PORT}"
