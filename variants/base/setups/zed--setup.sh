#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.1.0

# zed--setup.sh — Install the Zed editor from its official release tarball, then wrap it for containers
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO" >&2; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>|latest]

Examples:
  $0                         # latest stable Zed
  $0 --version 1.25.3        # pin a specific release

Notes:
- Installs to /opt/zed-<version>, linked as /opt/zed-current; launcher at /usr/local/bin/zed.
- Zed renders with Vulkan. A booth has no GPU, so Mesa's software driver
  (lavapipe) is installed and ZED_ALLOW_EMULATED_GPU=1 silences Zed's warning
  about it. Expect it to be slower than on real hardware.
- Requires a desktop environment; skipped on non-desktop variants.
- Supports amd64 and arm64.
USAGE
}

# --- root check ---
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (use sudo)" >&2; exit 1; }

# This script will always be installed by root.
HOME=/root

ZED_DEFAULT_VER="1.25.3"   # fallback when 'latest' cannot be resolved
REQ_VER="latest"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VER="${1:-latest}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done
REQ_VER="${REQ_VER#v}"

SCRIPT_NAME="$(basename "$0")"
# Resolve helpers from the image, not beside this script: a project copy under
# .booth/setups/ has no libs/ next to it.
SETUP_LIBS_DIR=${SETUP_LIBS_DIR:-/opt/codingbooth/setups/libs}
source "$SETUP_LIBS_DIR/skip-setup.sh"
if ! cb-has-desktop.sh; then
    skip_setup "$SCRIPT_NAME" "desktop environment not available"
fi

ZED_LINK=/opt/zed-current
ZED_BIN=/usr/local/bin/zed
DESKTOP_FILE=/usr/share/applications/dev.zed.Zed.desktop
STARTUP_FILE="/usr/share/startup.d/70-cb-zed--startup.sh"

# ---- arch mapping ----
dpkgArch="$(dpkg --print-architecture)"
case "$dpkgArch" in
  amd64) ZED_ARCH="x86_64" ;;
  arm64) ZED_ARCH="aarch64" ;;
  *) echo "❌ Unsupported arch: $dpkgArch (need amd64 or arm64)" >&2; exit 1 ;;
esac

# ---- deps: software Vulkan (no GPU in a booth) ----
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends curl ca-certificates tar libvulkan1 mesa-vulkan-drivers
rm -rf /var/lib/apt/lists/*

# ---- resolve version ----
if [[ "$REQ_VER" == "latest" ]]; then
  VERSION=$(curl --retry 3 --retry-delay 2 -fsSL https://api.github.com/repos/zed-industries/zed/releases/latest \
            | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"v[^"]+"' | head -1 \
            | sed -E 's/.*"v([^"]+)".*/\1/' || true)
  if [[ -z "$VERSION" ]]; then
    # The GitHub API is rate-limited, so degrade to the pinned default instead of failing the build.
    echo "⚠️  Could not resolve the latest Zed release; using ${ZED_DEFAULT_VER}."
    VERSION="$ZED_DEFAULT_VER"
  fi
else
  VERSION="$REQ_VER"
fi

# ---- download and install ----
ZED_HOME="/opt/zed-${VERSION}"
URL="https://github.com/zed-industries/zed/releases/download/v${VERSION}/zed-linux-${ZED_ARCH}.tar.gz"
echo "⬇️  Installing Zed v${VERSION} (${ZED_ARCH}) ..."
TMP_DIR=$(mktemp -d)
curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL "$URL" -o "${TMP_DIR}/zed.tar.gz"
tar -xzf "${TMP_DIR}/zed.tar.gz" -C "${TMP_DIR}"
rm -rf "$ZED_HOME"
mv "${TMP_DIR}/zed.app" "$ZED_HOME"
rm -rf "${TMP_DIR}"
ln -sfn "$ZED_HOME" "$ZED_LINK"

# --- Container-compatible launcher ---
# Lavapipe is the only Vulkan device a booth has; without the opt-in Zed warns
# on every start that it is running on an emulated GPU.
# With no arguments, open the project rather than an empty window.
cat > "$ZED_BIN" <<EOF
#!/usr/bin/env bash
export ZED_ALLOW_EMULATED_GPU="\${ZED_ALLOW_EMULATED_GPU:-1}"
exec "$ZED_LINK/bin/zed" "\${@:-/home/coder/code}"
EOF
chmod 0755 "$ZED_BIN"

# --- Desktop entry, pointed at the launcher ---
# The tarball's entry says Exec=zed and Icon=zed; make both absolute so they
# resolve without an icon-theme cache refresh.
sed -e "s|^Exec=zed|Exec=${ZED_BIN}|" \
    -e "s|^TryExec=.*|TryExec=${ZED_BIN}|" \
    -e "s|^Icon=.*|Icon=${ZED_LINK}/share/icons/hicolor/512x512/apps/zed.png|" \
    "$ZED_HOME/share/applications/dev.zed.Zed.desktop" > "$DESKTOP_FILE"
chmod 644 "$DESKTOP_FILE"

# Register a Zed desktop icon (no-ops on non-desktop variants).
cb-desktop-icon.sh "$DESKTOP_FILE"

# ---- Create startup file: runs once per container start as normal user ----
# No build-time values to stamp in, so write it verbatim.
cat > "${STARTUP_FILE}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Zed startup script
# Seeds settings from cb-home-seed when the user has none yet.
# Zed keeps settings/keymaps under ~/.config/zed.

CB_SEED_DIR="/etc/cb-home-seed/.config/zed"
DEST_DIR="$HOME/.config/zed"
if [[ -d "$CB_SEED_DIR" && ! -d "$DEST_DIR" ]]; then
    mkdir -p "$DEST_DIR"
    cp -r "$CB_SEED_DIR/." "$DEST_DIR/"
fi

# Zed's self-updater cannot write the root-owned /opt install and shows
# "Failed to Update"; the version comes from the Boothfile instead. Only when
# the user has no settings of their own — seeded or hand-made ones win.
if [[ ! -f "$DEST_DIR/settings.json" ]]; then
    mkdir -p "$DEST_DIR"
    cat > "$DEST_DIR/settings.json" <<'JSON'
{
  // Written by CodingBooth: the booth pins Zed's version (ZED_VERSION), so
  // the self-updater stays off. Edit freely; this file is never rewritten.
  "auto_update": false
}
JSON
fi
EOF
chmod 755 "${STARTUP_FILE}"

echo ""
echo "✅ Zed installed."
echo -n "   Version: "; "$ZED_LINK/bin/zed" --version 2>/dev/null || echo "${VERSION}"
echo "   Binary:  ${ZED_BIN} (wraps ${ZED_LINK}/bin/zed)"
echo "   Startup: ${STARTUP_FILE}"

cat <<'EON'
ℹ️ Ready to use:
- Click the Zed icon on the desktop, or run: zed          (opens ~/code)
- Open a file or folder: zed path/to/file

Settings seeding — to reuse your host settings, add to .booth/config.toml:
  run-args = ["-v", "~/.config/zed:/etc/cb-home-seed/.config/zed:ro"]

Notes:
- Rendering uses Mesa's software Vulkan driver; there is no GPU in a booth.
- See: https://zed.dev/docs/linux
EON
