#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>|latest]

Examples:
  $0                       # latest xonsh[full]
  $0 --version 0.24.2      # pin a release

Notes:
- Installs xonsh into its own venv at /opt/xonsh
- Symlinks /usr/local/bin/xonsh and registers it in /etc/shells
- Needs Python >= 3.11. Installs the catalog Python 3.13.15 when the
  interpreter on PATH is missing or older.
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }
HOME=/root

# ---- defaults / args ----
XONSH_FALLBACK_VER="0.24.2"
PY_PIN="3.13.15"
REQ_VER="latest"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VER="${1:-latest}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ "$REQ_VER" != "latest" && ! "$REQ_VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "❌ Not a xonsh version: '${REQ_VER}' (expected X.Y.Z or latest)" >&2
  exit 2
fi

python_ok() {
  command -v python3 >/dev/null 2>&1 || return 1
  python3 -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 11) else 1)' || return 1
}

# A bare `setup xonsh` has to work without the template's requires line.
if ! python_ok; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  PY_SETUP=""
  for candidate in "$SCRIPT_DIR/python--setup.sh" /opt/codingbooth/setups/python--setup.sh; do
    if [[ -x "$candidate" ]]; then
      PY_SETUP="$candidate"
      break
    fi
  done
  if [[ -z "$PY_SETUP" ]]; then
    echo "❌ xonsh needs Python >= 3.11 and python--setup.sh was not found" >&2
    exit 1
  fi
  echo "• Installing Python ${PY_PIN} (xonsh needs >= 3.11) ..."
  "$PY_SETUP" "$PY_PIN"
fi
python_ok || { echo "❌ Python >= 3.11 is still not on PATH" >&2; exit 1; }

UV_BIN=""
for candidate in /usr/local/uv/uv /usr/local/uv/bin/uv; do
  if [[ -x "$candidate" ]]; then
    UV_BIN="$candidate"
    break
  fi
done
if [[ -z "$UV_BIN" ]] && command -v uv >/dev/null 2>&1; then
  UV_BIN="$(command -v uv)"
fi
if [[ -z "$UV_BIN" ]]; then
  echo "❌ uv is not on PATH. Run python--setup.sh first." >&2
  exit 1
fi

PY_EXE="/opt/python/bin/python"
if [[ ! -x "$PY_EXE" ]]; then
  PY_EXE="$(command -v python3)"
fi

VENV_DIR="/opt/xonsh"
echo "🛠  Creating venv at ${VENV_DIR} ..."
rm -rf "$VENV_DIR"
"$UV_BIN" venv --python "$PY_EXE" "$VENV_DIR"

# pip stays in the venv so `xpip` can install xontribs later.
if [[ "$REQ_VER" == "latest" ]]; then
  echo "⬇️  Installing latest xonsh[full] ..."
  "$UV_BIN" pip install --python "$VENV_DIR/bin/python" --no-cache pip 'xonsh[full]'
else
  echo "⬇️  Installing xonsh[full]==${REQ_VER} ..."
  "$UV_BIN" pip install --python "$VENV_DIR/bin/python" --no-cache pip "xonsh[full]==${REQ_VER}"
fi

chmod -R a+rX "$VENV_DIR"
ln -sfn "$VENV_DIR/bin/xonsh" /usr/local/bin/xonsh
grep -qxF /usr/local/bin/xonsh /etc/shells 2>/dev/null || echo /usr/local/bin/xonsh >> /etc/shells

PROFILE_FILE="/etc/profile.d/70-cb-xonsh--profile.sh"
cat > "$PROFILE_FILE" <<'EOF'
# Profile: Xonsh
#   xonsh                         # Python-powered shell
#   xonsh -c 'print(2 + 2)'       # one shot, no TTY
#   xonsh script.xsh              # run a script
#
# Login shell: select xonsh+default (USER_SHELL=/usr/local/bin/xonsh).
# Config: ~/.xonshrc
# Extra xontribs: xpip install <name>   (or sudo /opt/xonsh/bin/pip install <name>)
# Docs: https://xon.sh/
EOF
chmod 644 "$PROFILE_FILE"

echo "✅ Xonsh installed."
echo -n "   xonsh → "; xonsh --version 2>/dev/null || true

cat <<'EON'
ℹ️ Ready to use:
- Start the shell:  xonsh
- One shot:         xonsh -c 'print(2 + 2)'
- Run a script:     xonsh hello.xsh
- As login shell:   select xonsh+default

Notes:
- The shell's own Python is the venv at /opt/xonsh, separate from later pip installs.
- Docs: https://xon.sh/
EON
