#!/usr/bin/env bash
# Project-local template setup (from localgadget/setups/)
set -euo pipefail

MARKER="CB_DETECT_TEMPLATE_v1"
echo "$MARKER" > /tmp/cb-local-template-marker.txt
mkdir -p /opt/cb-local-detect
echo "$MARKER" > /opt/cb-local-detect/template.txt

cat > /usr/local/bin/cb-local-template <<'EOF'
#!/usr/bin/env bash
echo "CB_DETECT_TEMPLATE_v1"
EOF
chmod 755 /usr/local/bin/cb-local-template

cat > /etc/profile.d/70-cb-local-template--profile.sh <<'EOF'
export CB_LOCAL_TEMPLATE_MARKER=CB_DETECT_TEMPLATE_v1
EOF
chmod 644 /etc/profile.d/70-cb-local-template--profile.sh
