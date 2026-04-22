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
exec start-booth-wrapped
EOF
chmod +x /usr/local/bin/start-notebook-wrapped

echo "✅ start-notebook-wrapped installed."
