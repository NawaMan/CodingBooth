#!/usr/bin/env bash
# Project-local extension setup (from widget--extension.toml files.setups)
set -euo pipefail

MARKER="CB_DETECT_EXTENSION_v1"
echo "$MARKER" > /tmp/cb-local-extension-marker.txt
mkdir -p /opt/cb-local-detect
echo "$MARKER" > /opt/cb-local-detect/extension.txt

cat > /usr/local/bin/cb-local-extension <<'EOF'
#!/usr/bin/env bash
echo "CB_DETECT_EXTENSION_v1"
EOF
chmod 755 /usr/local/bin/cb-local-extension

cat > /etc/profile.d/70-cb-local-extension--profile.sh <<'EOF'
export CB_LOCAL_EXTENSION_MARKER=CB_DETECT_EXTENSION_v1
EOF
chmod 644 /etc/profile.d/70-cb-local-extension--profile.sh
