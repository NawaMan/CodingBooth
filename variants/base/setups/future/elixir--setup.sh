#!/bin/bash
set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 [--version <x.y.z>|latest] [--with-phoenix] [--mix-home <dir>] [--hex-home <dir>]

Examples:
  $0                       # install default (1.16.2) and set up hex/rebar
  $0 --version latest      # fetch latest Elixir release from GitHub
  $0 --with-phoenix        # also install the phx.new mix archive
  $0 --mix-home /opt/mix-cache --hex-home /opt/hex-cache

Notes:
- Requires Erlang/OTP in PATH (erl/erlc). Use your erlang--setup.sh first.
- Installs to /opt/elixir/elixir-<ver> and links /opt/elixir-stable.
- Mix & Hex caches live under /opt by default and are world-writable (CI/dev friendly).
USAGE
}

# --- root check ---
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# --- defaults / args ---
ELIXIR_DEFAULT="1.16.2"     # bump when you want a newer pinned default
REQ_VER=""
WITH_PHOENIX=0
MIX_HOME_DEFAULT="/opt/mix"
HEX_HOME_DEFAULT="/opt/hex"
MIX_HOME="$MIX_HOME_DEFAULT"
HEX_HOME="$HEX_HOME_DEFAULT"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)      shift; REQ_VER="${1:-}"; shift ;;
    --with-phoenix) WITH_PHOENIX=1; shift ;;
    --mix-home)     shift; MIX_HOME="${1:-$MIX_HOME_DEFAULT}"; shift ;;
    --hex-home)     shift; HEX_HOME="${1:-$HEX_HOME_DEFAULT}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

# Resolve version (supports 'latest' via GitHub API)
if [[ -z "$REQ_VER" ]]; then
  ELIX_VER="$ELIXIR_DEFAULT"
elif [[ "$REQ_VER" == "latest" ]]; then
  ELIX_VER="$(curl -fsSL https://api.github.com/repos/elixir-lang/elixir/releases/latest \
    | grep -oP '"tag_name"\s*:\s*"\K[^"]+' | sed 's/^v//')"
  [[ -n "$ELIX_VER" ]] || { echo "❌ Failed to resolve latest Elixir version"; exit 1; }
else
  ELIX_VER="$REQ_VER"
fi

# --- sanity: Erlang present ---
if ! command -v erl >/dev/null 2>&1; then
  echo "❌ Erlang/OTP not found (erl). Install it first."; exit 1
fi

# --- base deps ---
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends curl unzip ca-certificates coreutils
rm -rf /var/lib/apt/lists/*

# --- locations ---
INSTALL_PARENT=/opt/elixir
TARGET_DIR="${INSTALL_PARENT}/elixir-${ELIX_VER}"
LINK_DIR=/opt/elixir-stable
BIN_DIR=/usr/local/bin

# Clean old shims (idempotent)
for b in elixir iex mix elixirc; do rm -f "${BIN_DIR}/$b" || true; done

# --- download precompiled Elixir ---
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
ZIP_URL="https://github.com/elixir-lang/elixir/releases/download/v${ELIX_VER}/Precompiled.zip"

echo "⬇️  Downloading Elixir ${ELIX_VER} ..."
curl -fsSL "$ZIP_URL" -o "$TMP/elixir.zip"

echo "📦 Installing Elixir ${ELIX_VER} ..."
rm -rf "$TARGET_DIR"
mkdir -p "$TARGET_DIR"
unzip -q "$TMP/elixir.zip" -d "$TARGET_DIR"

# Stable link
ln -sfn "$TARGET_DIR" "$LINK_DIR"

# --- shared caches (world-writable) ---
mkdir -p "$MIX_HOME" "$HEX_HOME"
chmod -R 0777 "$MIX_HOME" "$HEX_HOME" || true

# --- profile env (login shells) ---
cat >/etc/profile.d/99-elixir--profile.sh <<EOF
# Elixir under /opt
export ELIXIR_HOME=$LINK_DIR
export PATH="\$ELIXIR_HOME/bin:\$PATH"
# Shared caches for mix/hex
export MIX_HOME=${MIX_HOME}
export HEX_HOME=${HEX_HOME}
EOF
chmod 0644 /etc/profile.d/99-elixir--profile.sh

# --- non-login wrappers (so it works in Docker RUN etc.) ---
install -d "$BIN_DIR"
cat >"${BIN_DIR}/exwrap" <<'EOF'
#!/bin/sh
: "${ELIXIR_HOME:=/opt/elixir-stable}"
: "${MIX_HOME:=/opt/mix}"
: "${HEX_HOME:=/opt/hex}"
export ELIXIR_HOME MIX_HOME HEX_HOME PATH="$ELIXIR_HOME/bin:$PATH"
tool="$(basename "$0")"
exec "$ELIXIR_HOME/bin/$tool" "$@"
EOF
chmod +x "${BIN_DIR}/exwrap"

for t in elixir iex mix elixirc; do
  ln -sfn "${BIN_DIR}/exwrap" "${BIN_DIR}/$t"
done

# --- install Hex & Rebar globally (into MIX_HOME/HEX_HOME) ---
echo "🔧 Installing Hex & Rebar for all users ..."
# Mix requires HOME to write configs; use MIX_HOME as a neutral HOME to avoid touching /root
HOME="$MIX_HOME" MIX_HOME="$MIX_HOME" HEX_HOME="$HEX_HOME" \
  "${BIN_DIR}/mix" local.hex --force
HOME="$MIX_HOME" MIX_HOME="$MIX_HOME" HEX_HOME="$HEX_HOME" \
  "${BIN_DIR}/mix" local.rebar --force

# --- optional: Phoenix generator (phx.new) ---
if [[ $WITH_PHOENIX -eq 1 ]]; then
  echo "🌶  Installing Phoenix project generator (phx.new) ..."
  HOME="$MIX_HOME" MIX_HOME="$MIX_HOME" HEX_HOME="$HEX_HOME" \
    "${BIN_DIR}/mix" archive.install hex phx_new --force
fi

# --- summary ---
echo "✅ Elixir ${ELIX_VER} installed at ${TARGET_DIR} (linked at ${LINK_DIR})."
echo -n "   elixir -v → "; "${BIN_DIR}/elixir" -v 2>/dev/null || true
echo -n "   mix -v    → "; "${BIN_DIR}/mix" -v 2>/dev/null || true
if [[ $WITH_PHOENIX -eq 1 ]]; then
  echo "   phx.new archive installed (try: mix phx.new demo_app)"
fi

cat <<'EON'
ℹ️ Ready to use:
- Try: elixir -v && mix -v
- Works in login & non-login shells (wrapper primes PATH/MIX_HOME/HEX_HOME).
- Create a project: mix new my_app
- Phoenix (if installed): mix phx.new demo_app

Notes:
- Elixir uses your Erlang/OTP (erl) already on PATH.
- Caches live under /opt (MIX_HOME=/opt/mix, HEX_HOME=/opt/hex); persist them in CI for speed.
EON
