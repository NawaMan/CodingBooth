#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Creates start-codeserver-wrapped: nginx wrapper around code-server.

set -euo pipefail

cat > /usr/local/bin/start-codeserver-wrapped <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
export INNER_PORT=19999
export INNER_CMD="start-codeserver $INNER_PORT"
export IFRAME_SRC="/?_booth_inner=1"

# code-server's own settings.json sets terminal.integrated.fontFamily, but
# that only *names* the font — code-server's terminal (and its whole
# workbench) renders client-side in the visitor's browser, same as ttyd, so
# the font bytes still have to reach that browser. start-booth-wrapped's
# nginx serves them at /booth-assets/fonts/ unconditionally; this is what
# actually asks for them to be woven into the page.
export WRAPPER_HEAD_INJECT='<style>@font-face{font-family:FiraCode Nerd Font Mono;font-weight:400;font-style:normal;font-display:swap;src:url(/booth-assets/fonts/FiraCodeNerdFontMono-Regular.ttf);}@font-face{font-family:FiraCode Nerd Font Mono;font-weight:700;font-style:normal;font-display:swap;src:url(/booth-assets/fonts/FiraCodeNerdFontMono-Bold.ttf);}</style>'

exec start-booth-wrapped
EOF
chmod +x /usr/local/bin/start-codeserver-wrapped

echo "✅ start-codeserver-wrapped installed."
