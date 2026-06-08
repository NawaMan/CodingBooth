#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Creates start-xfce-wrapped, start-kde-wrapped and start-lxqt-wrapped: nginx wrapper around desktop.
# The desktop's noVNC+websockify listens on an internal port, nginx on the booth port.

set -euo pipefail

DESKTOP_INNER_PORT=10099

cat > /usr/local/bin/start-xfce-wrapped <<EOF
#!/usr/bin/env bash
set -euo pipefail
export INNER_PORT=$DESKTOP_INNER_PORT
export INNER_CMD="NOVNC_PORT=$DESKTOP_INNER_PORT start-xfce"
export IFRAME_SRC="/vnc.html?autoconnect=true&resize=remote"
exec start-booth-wrapped
EOF
chmod +x /usr/local/bin/start-xfce-wrapped

cat > /usr/local/bin/start-kde-wrapped <<EOF
#!/usr/bin/env bash
set -euo pipefail
export INNER_PORT=$DESKTOP_INNER_PORT
export INNER_CMD="NOVNC_PORT=$DESKTOP_INNER_PORT start-kde"
export IFRAME_SRC="/vnc.html?autoconnect=true&resize=remote"
exec start-booth-wrapped
EOF
chmod +x /usr/local/bin/start-kde-wrapped

cat > /usr/local/bin/start-lxqt-wrapped <<EOF
#!/usr/bin/env bash
set -euo pipefail
export INNER_PORT=$DESKTOP_INNER_PORT
export INNER_CMD="NOVNC_PORT=$DESKTOP_INNER_PORT start-lxqt"
export IFRAME_SRC="/vnc.html?autoconnect=true&resize=remote"
exec start-booth-wrapped
EOF
chmod +x /usr/local/bin/start-lxqt-wrapped

echo "✅ start-xfce-wrapped, start-kde-wrapped and start-lxqt-wrapped installed."
