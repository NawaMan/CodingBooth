#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Creates start-notebook-wrapped: nginx wrapper around JupyterLab.
# All /booth-messages/api/* requests are proxied by the wrapper to the
# shared bash API server (booth-message-api-server); Jupyter itself is
# not involved in the message API, so no Jupyter server extension is
# installed here.

set -euo pipefail

# ── Create start-notebook-wrapped ──
cat > /usr/local/bin/start-notebook-wrapped <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
export INNER_PORT=18888
export INNER_CMD="BOOTH_CODE_PORT=18888 start-notebook 18888"
export IFRAME_SRC="/lab"

# JupyterLab's terminal (xterm.js, rendered client-side in the browser same
# as ttyd and code-server) and its notebook/file editors (CodeMirror) both
# take their monospace font from the --jp-code-font-family CSS variable,
# which the active theme sets — there's no per-feature "terminal font"
# setting to seed via user-settings the way VS Code has. Overriding the
# variable here covers both surfaces in one shot. start-booth-wrapped's
# nginx serves the actual font bytes at /booth-assets/fonts/.
export WRAPPER_HEAD_INJECT='<style>@font-face{font-family:FiraCode Nerd Font Mono;font-weight:400;font-style:normal;font-display:swap;src:url(/booth-assets/fonts/FiraCodeNerdFontMono-Regular.ttf);}@font-face{font-family:FiraCode Nerd Font Mono;font-weight:700;font-style:normal;font-display:swap;src:url(/booth-assets/fonts/FiraCodeNerdFontMono-Bold.ttf);}:root{--jp-code-font-family:FiraCode Nerd Font Mono, menlo, consolas, "DejaVu Sans Mono", monospace !important;}</style>'

exec start-booth-wrapped
EOF
chmod +x /usr/local/bin/start-notebook-wrapped

echo "✅ start-notebook-wrapped installed."
