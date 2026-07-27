#!/usr/bin/env bash
# Pure project-local setup: hand-placed under .booth/setups/, not shipped by a
# template file entry. The localgadget template's Boothfile still calls
# `setup local-hand` so this script is selected through the picker path.
set -euo pipefail

MARKER="CB_DETECT_SETUP_v1"
echo "$MARKER" > /tmp/cb-local-setup-marker.txt
mkdir -p /opt/cb-local-detect
echo "$MARKER" > /opt/cb-local-detect/setup.txt

cat > /usr/local/bin/cb-local-setup <<'EOF'
#!/usr/bin/env bash
echo "CB_DETECT_SETUP_v1"
EOF
chmod 755 /usr/local/bin/cb-local-setup

cat > /etc/profile.d/70-cb-local-setup--profile.sh <<'EOF'
export CB_LOCAL_SETUP_MARKER=CB_DETECT_SETUP_v1
EOF
chmod 644 /etc/profile.d/70-cb-local-setup--profile.sh
