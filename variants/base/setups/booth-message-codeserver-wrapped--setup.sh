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
exec start-booth-wrapped
EOF
chmod +x /usr/local/bin/start-codeserver-wrapped

echo "✅ start-codeserver-wrapped installed."
