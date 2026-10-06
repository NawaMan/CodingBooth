#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 1.0.0

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--version <YY.MM.P>|latest]

Examples:
  $0                          # latest stable Helix
  $0 --version 25.07.1        # pin a release

Notes:
- Installs the hx binary and its runtime tree under /opt/helix
- Symlinks a wrapper at /usr/local/bin/hx that sets HELIX_RUNTIME
- Supports amd64 and arm64
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# ---- defaults / args ----
HELIX_FALLBACK_VER="25.07.1"
REQ_VER="latest"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VER="${1:-latest}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

# ---- arch mapping (release assets use uname-style names) ----
dpkgArch="$(dpkg --print-architecture)"
case "$dpkgArch" in
  amd64) ARCH="x86_64" ;;
  arm64) ARCH="aarch64" ;;
  *) echo "❌ Unsupported arch: $dpkgArch (need amd64 or arm64)"; exit 1 ;;
esac

if ! command -v curl >/dev/null 2>&1 || ! command -v tar >/dev/null 2>&1 || ! command -v xz >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends curl ca-certificates tar xz-utils
  rm -rf /var/lib/apt/lists/*
fi

# ---- resolve version ----
# Tags are YY.MM.P with no leading "v" (25.07.1). releases/latest is the
# newest stable tag; a rate-limited API falls back to the pinned release.
if [[ "$REQ_VER" == "latest" ]]; then
  VERSION=$(curl --retry 3 --retry-delay 2 -fsSL https://api.github.com/repos/helix-editor/helix/releases/latest \
            | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 \
            | sed -E 's/.*"([^"]+)".*/\1/' || true)
  if [[ -z "$VERSION" || ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "⚠️  Could not resolve the latest Helix release; using ${HELIX_FALLBACK_VER}."
    VERSION="$HELIX_FALLBACK_VER"
  fi
else
  VERSION="${REQ_VER#v}"
fi

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "❌ Not a Helix version: '${VERSION}' (expected YY.MM.P, for example 25.07.1)" >&2
  exit 2
fi

ASSET="helix-${VERSION}-${ARCH}-linux.tar.xz"
URL="https://github.com/helix-editor/helix/releases/download/${VERSION}/${ASSET}"

echo "⬇️  Installing Helix ${VERSION} (${ARCH}) ..."
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL "$URL" -o "${TMP_DIR}/helix.tar.xz"
tar -xJf "${TMP_DIR}/helix.tar.xz" -C "$TMP_DIR"

SRC="${TMP_DIR}/helix-${VERSION}-${ARCH}-linux"
if [[ ! -x "$SRC/hx" || ! -d "$SRC/runtime" ]]; then
  echo "❌ Helix archive did not contain hx and runtime/" >&2
  exit 1
fi

rm -rf /opt/helix
mkdir -p /opt/helix
# The runtime tree (grammars, queries, themes) must sit next to the binary.
cp -a "$SRC/hx" "$SRC/runtime" /opt/helix/
chmod 755 /opt/helix/hx
chmod -R a+rX /opt/helix

cat > /usr/local/bin/hx <<'EOF'
#!/bin/sh
# Wrapper so a non-login `hx` still finds the runtime tree.
export HELIX_RUNTIME="${HELIX_RUNTIME:-/opt/helix/runtime}"
exec /opt/helix/hx "$@"
EOF
chmod 755 /usr/local/bin/hx

PROFILE_FILE="/etc/profile.d/70-cb-helix--profile.sh"
cat > "$PROFILE_FILE" <<'EOF'
# Profile: Helix
export HELIX_RUNTIME="${HELIX_RUNTIME:-/opt/helix/runtime}"
EOF
chmod 644 "$PROFILE_FILE"

echo "✅ Helix installed."
echo -n "   hx → "; hx --version 2>/dev/null || true

cat <<'EON'
ℹ️ Ready to use:
- Open a file:   hx README.md
- Check runtime: hx --health
- Tutor:         hx --tutor
- Make it $EDITOR for this shell: export EDITOR=hx VISUAL=hx

Notes:
- Config lives in ~/.config/helix/config.toml
- Select helix+config-shared to keep that directory in git (.booth/shared)
- Docs: https://docs.helix-editor.com/
EON
