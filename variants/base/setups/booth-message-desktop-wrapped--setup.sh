#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 1.0.0

# Creates start-xfce-wrapped, start-kde-wrapped and start-lxqt-wrapped: nginx wrapper around desktop.
# The desktop's noVNC+websockify listens on an internal port, nginx on the booth port.

set -euo pipefail

# Each desktop runs behind the wrapper on its own default port — the same port
# `start-<desktop>` uses when started by hand on another variant.
XFCE_INNER_PORT=14444
KDE_INNER_PORT=15555
LXQT_INNER_PORT=16666
WAYLAND_INNER_PORT=17777

cat > /usr/local/bin/start-xfce-wrapped <<EOF
#!/usr/bin/env bash
set -euo pipefail
export INNER_PORT=$XFCE_INNER_PORT
export INNER_CMD="start-xfce $XFCE_INNER_PORT"
export IFRAME_SRC="/vnc.html?autoconnect=true&resize=remote"
exec start-booth-wrapped
EOF
chmod +x /usr/local/bin/start-xfce-wrapped

cat > /usr/local/bin/start-kde-wrapped <<EOF
#!/usr/bin/env bash
set -euo pipefail
export INNER_PORT=$KDE_INNER_PORT
export INNER_CMD="start-kde $KDE_INNER_PORT"
export IFRAME_SRC="/vnc.html?autoconnect=true&resize=remote"
exec start-booth-wrapped
EOF
chmod +x /usr/local/bin/start-kde-wrapped

cat > /usr/local/bin/start-lxqt-wrapped <<EOF
#!/usr/bin/env bash
set -euo pipefail
export INNER_PORT=$LXQT_INNER_PORT
export INNER_CMD="start-lxqt $LXQT_INNER_PORT"
export IFRAME_SRC="/vnc.html?autoconnect=true&resize=remote"
exec start-booth-wrapped
EOF
chmod +x /usr/local/bin/start-lxqt-wrapped

cat > /usr/local/bin/start-wayland-wrapped <<EOF
#!/usr/bin/env bash
set -euo pipefail
export INNER_PORT=$WAYLAND_INNER_PORT
export INNER_CMD="start-wayland $WAYLAND_INNER_PORT"
export IFRAME_SRC="/vnc.html?autoconnect=true&resize=remote"
exec start-booth-wrapped
EOF
chmod +x /usr/local/bin/start-wayland-wrapped

echo "✅ start-xfce-wrapped, start-kde-wrapped, start-lxqt-wrapped and start-wayland-wrapped installed."
