#!/bin/bash
set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 [--version <OCAML_VER>] [--packages "pkg1 pkg2 ..."] [--switch-name <name>] [--no-default-packages]

Examples:
  $0                                # default OCaml 5.2.1 + dune utop ocamlformat
  $0 --version 4.14.2               # specific compiler version
  $0 --packages "dune merlin"       # customize global packages
  $0 --switch-name my-ocaml         # custom switch name

Notes:
- Shared opam root: OPAMROOT=/opt/opam (world-writable), switch-based install
- Switch prefix is linked to /opt/ocaml/ocaml-<ver> and /opt/ocaml-stable
- /usr/local/bin shim makes ocaml/dune/utop work in non-login shells
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# ---- defaults / args ----
OCAML_DEFAULT_VER="5.2.1"
REQ_VER="$OCAML_DEFAULT_VER"
SWITCH_NAME=""            # if empty we'll use "ocaml-<ver>"
NO_DEFAULT_PACKS=0
EXTRA_PACKS=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VER="${1:-$OCAML_DEFAULT_VER}"; shift ;;
    --switch-name) shift; SWITCH_NAME="${1:-}"; shift ;;
    --packages) shift; EXTRA_PACKS="${1:-}"; shift ;;
    --no-default-packages) NO_DEFAULT_PACKS=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

# ---- base deps ----
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  git build-essential m4 pkg-config bubblewrap \
  opam  # distro opam (Ubuntu 22.04+/Debian 12+)
rm -rf /var/lib/apt/lists/*

# ---- locations ----
export OPAMROOT=/opt/opam
INSTALL_PARENT=/opt/ocaml
LINK_DIR=/opt/ocaml-stable
BIN_DIR=/usr/local/bin

# fresh root & dirs
mkdir -p "$OPAMROOT" "$INSTALL_PARENT"
chmod -R 0777 "$OPAMROOT" "$INSTALL_PARENT" || true

# ---- initialize opam (container-friendly) ----
# No user interaction; disable sandboxing for Docker
if [[ ! -f "$OPAMROOT/config" ]]; then
  echo "🔧 Initializing opam root at $OPAMROOT ..."
  opam init -y --bare --disable-sandboxing --reinit >/dev/null
fi

# pick switch name
if [[ -z "$SWITCH_NAME" ]]; then
  SWITCH_NAME="ocaml-$REQ_VER"
fi

# create or reuse switch
if ! opam switch list --short | grep -qx "$SWITCH_NAME"; then
  echo "📦 Creating switch '$SWITCH_NAME' with OCaml $REQ_VER ..."
  opam switch create "$SWITCH_NAME" "ocaml-base-compiler.$REQ_VER" -y >/dev/null
else
  echo "ℹ️ Using existing switch '$SWITCH_NAME'"
fi

# capture switch prefix (physical install location)
SW_PREFIX="$(OPAMROOT=$OPAMROOT opam var --switch="$SWITCH_NAME" prefix)"
[[ -n "$SW_PREFIX" && -d "$SW_PREFIX" ]] || { echo "❌ Could not resolve switch prefix"; exit 1; }

# link stable & versioned dirs
TARGET_DIR="${INSTALL_PARENT}/ocaml-${REQ_VER}"
rm -rf "$TARGET_DIR"
ln -sfn "$SW_PREFIX" "$TARGET_DIR"
ln -sfn "$TARGET_DIR" "$LINK_DIR"
chmod -R 0777 "$TARGET_DIR" "$LINK_DIR" || true

# default global packages (useful/safe)
DEFAULT_PACKS="dune utop ocamlformat"
PACKS=""
if [[ $NO_DEFAULT_PACKS -eq 0 ]]; then PACKS="$DEFAULT_PACKS"; fi
if [[ -n "$EXTRA_PACKS" ]]; then PACKS="$PACKS ${EXTRA_PACKS}"; fi

if [[ -n "$PACKS" ]]; then
  echo "📦 Installing packages into switch '$SWITCH_NAME': $PACKS"
  # Make sure env is set for the switch during install
  eval "$(OPAMROOT=$OPAMROOT opam env --switch="$SWITCH_NAME" --set-switch --shell=sh)"
  opam install -y $PACKS
fi

# ---- profile env (login shells) ----
cat >/etc/profile.d/99-ocaml--profile.sh <<EOF
# OCaml via opam (system-wide)
export OPAMROOT=$OPAMROOT
# Activate the chosen switch in login shells
eval "\$(opam env --switch $SWITCH_NAME --root $OPAMROOT --set-switch --shell=sh)" 2>/dev/null || true
# Convenience: stable path to current switch prefix
export OCAML_HOME=$LINK_DIR
export PATH="\$OCAML_HOME/bin:\$PATH"
EOF
chmod 0644 /etc/profile.d/99-ocaml--profile.sh

# ---- wrapper for non-login shells ----
install -d "$BIN_DIR"
cat >"$BIN_DIR/ocamlwrap" <<'EOF'
#!/bin/sh
: "${OPAMROOT:=/opt/opam}"
: "${OCAML_HOME:=/opt/ocaml-stable}"
# Prime opam env for the switch pointed by /opt/ocaml-stable
# We can read the switch from opam var if needed; assume a single active global switch for simplicity.
if command -v opam >/dev/null 2>&1; then
  # Try to infer a switch from the prefix path (best effort)
  # If that fails, rely on opam's global default.
  eval "$(opam env --root "$OPAMROOT" --shell=sh 2>/dev/null)" || true
fi
export OPAMROOT OCAML_HOME PATH="$OCAML_HOME/bin:$PATH"
tool="$(basename "$0")"
# Prefer binaries in the switch prefix (stable link), else fall back to PATH
if [ -x "$OCAML_HOME/bin/$tool" ]; then
  exec "$OCAML_HOME/bin/$tool" "$@"
fi
exec "$(command -v "$tool")" "$@"
EOF
chmod +x "$BIN_DIR/ocamlwrap"

# expose common tools via wrapper
for t in opam ocaml ocamlc ocamlopt ocamllsp dune utop ocamlformat ocamlmerlin; do
  ln -sfn "$BIN_DIR/ocamlwrap" "$BIN_DIR/$t"
done

# ---- summary ----
echo "✅ OCaml $REQ_VER installed in opam switch '$SWITCH_NAME'."
echo "   OPAMROOT      = $OPAMROOT"
echo "   Switch prefix = $SW_PREFIX"
echo "   OCAML_HOME    = $LINK_DIR -> $SW_PREFIX"
# Show versions
eval "$(OPAMROOT=$OPAMROOT opam env --switch="$SWITCH_NAME" --set-switch --shell=sh)"
echo -n "   ocamlc -version → "; ocamlc -version 2>/dev/null || true
echo -n "   dune --version  → "; command -v dune >/dev/null && dune
