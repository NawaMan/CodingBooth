#!/bin/bash
set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 [<RUST_VERSION>] [--rust-version <RUST_VERSION>] [--profile minimal|default] [--no-components]

Examples:
  $0                          # default version (1.90.0), minimal profile, add rustfmt+clippy
  $0 1.89.0                   # pin a specific version
  $0 --rust-version 1.88.1 --profile default
  $0 --no-components          # skip rustfmt/clippy

Notes:
- Installs into /opt/rust/rust-<version> then links /opt/rust-stable
- Adds multi-call wrappers in /usr/local/bin so rust tools work in any shell
USAGE
}

# ---- root check ----
if [ "$EUID" -ne 0 ]; then
  echo "❌ This script must be run as root (use sudo)" >&2
  exit 1
fi

# ---- defaults ----
RUST_DEFAULT_VERSION="1.90.0"
PROFILE="minimal"
ADD_COMPONENTS=1

# ---- parse args ----
RUST_VERSION_INPUT="${1:-}"
if [[ "${RUST_VERSION_INPUT}" =~ ^- ]]; then RUST_VERSION_INPUT=""; fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rust-version) shift; RUST_VERSION_INPUT="${1:-}"; shift ;;
    --profile)      shift; PROFILE="${1:-minimal}"; shift ;;
    --no-components) ADD_COMPONENTS=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      if [[ -z "${RUST_VERSION_INPUT}" ]]; then
        RUST_VERSION_INPUT="$1"; shift
      else
        echo "❌ Unknown argument: $1" >&2; usage; exit 2
      fi
      ;;
  esac
done

RUST_VERSION="${RUST_VERSION_INPUT:-$RUST_DEFAULT_VERSION}"

# ---- arch / host triple ----
dpkgArch="$(dpkg --print-architecture)"
case "$dpkgArch" in
  amd64) HOST_TRIPLE="x86_64-unknown-linux-gnu" ;;
  arm64) HOST_TRIPLE="aarch64-unknown-linux-gnu" ;;
  *) echo "❌ Unsupported architecture: $dpkgArch (supported: amd64, arm64)" >&2; exit 1 ;;
esac

# ---- dirs ----
INSTALL_PARENT=/opt/rust
TARGET_DIR="${INSTALL_PARENT}/rust-${RUST_VERSION}"
LINK_DIR=/opt/rust-stable
export RUSTUP_HOME="${TARGET_DIR}/rustup"
export CARGO_HOME="${TARGET_DIR}/cargo"
TOOLCHAIN_FILE="${LINK_DIR}/toolchain.txt"

# ---- base tools ----
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends curl ca-certificates tar xz-utils
rm -rf /var/lib/apt/lists/*

# ---- install rustup for host triple ----
RUSTUP_INIT_URL="https://static.rust-lang.org/rustup/dist/${HOST_TRIPLE}/rustup-init"
echo "Downloading rustup-init (${HOST_TRIPLE})..."
curl -fsSL "$RUSTUP_INIT_URL" -o /tmp/rustup-init
chmod +x /tmp/rustup-init

# Clean target dir for idempotent builds
rm -rf "$TARGET_DIR"
mkdir -p "$TARGET_DIR" "$RUSTUP_HOME" "$CARGO_HOME"

# ---- pre-clean conflicting binaries and skip rustup path check ----
# rustup-init bails if rustc/cargo already exist early in PATH (e.g., /usr/local/bin)
# We remove any old shims/binaries here and tell rustup to skip the path check.
for b in rustc cargo rustup rustfmt clippy-driver cargo-clippy; do
  rm -f "/usr/local/bin/$b" || true
done
export RUSTUP_INIT_SKIP_PATH_CHECK=yes

echo "Installing Rust toolchain '${RUST_VERSION}' with profile '${PROFILE}'..."
/tmp/rustup-init -y --default-toolchain "${RUST_VERSION}" --profile "${PROFILE}"
rm -f /tmp/rustup-init

# Load env NOW for this shell
if [ -f "${CARGO_HOME}/env" ]; then
  # shellcheck source=/dev/null
  . "${CARGO_HOME}/env"
fi

# Set/confirm default toolchain so rustc/cargo “just work”
"${CARGO_HOME}/bin/rustup" default "${RUST_VERSION}" || true

# Optional components
if [ "$ADD_COMPONENTS" -eq 1 ]; then
  "${CARGO_HOME}/bin/rustup" component add rustfmt clippy --toolchain "${RUST_VERSION}" || true
fi

# ---- stable symlink ----
ln -sfn "$TARGET_DIR" "$LINK_DIR"

# Make the installation writable for any user (dev/CI friendly)
chmod -R 0777 "$TARGET_DIR" "$LINK_DIR" || true

# Determine the active toolchain name (e.g., 1.90.0-x86_64-unknown-linux-gnu)
ACTIVE_TC="$("${CARGO_HOME}/bin/rustup" show active-toolchain 2>/dev/null | awk '{print $1}')"
if [ -z "$ACTIVE_TC" ]; then
  ACTIVE_TC="${RUST_VERSION}"
fi
echo "$ACTIVE_TC" > "$TOOLCHAIN_FILE"
chmod 0666 "$TOOLCHAIN_FILE" || true

# ---- login-shell env (POSIX) ----
cat >/etc/profile.d/99-rust--profile.sh <<'EOF'
# ---- Rust/Cargo defaults (safe to source multiple times) ----
export RUSTUP_HOME=/opt/rust-stable/rustup
export CARGO_HOME=/opt/rust-stable/cargo
export PATH="$CARGO_HOME/bin:$PATH"
# Optional: default toolchain hint
if [ -z "${RUSTUP_TOOLCHAIN:-}" ] && [ -r /opt/rust-stable/toolchain.txt ]; then
  export RUSTUP_TOOLCHAIN="$(cat /opt/rust-stable/toolchain.txt)"
fi
# ---- end defaults ----
EOF
chmod 0644 /etc/profile.d/99-rust--profile.sh

# ---- fish shell autoload ----
install -d /etc/fish/conf.d
cat >/etc/fish/conf.d/rust.fish <<'EOF'
# Load Rust env for fish
if test -f /opt/rust-stable/cargo/env.fish
  source /opt/rust-stable/cargo/env.fish
end
if test -z "$RUSTUP_TOOLCHAIN"; and test -r /opt/rust-stable/toolchain.txt
  set -gx RUSTUP_TOOLCHAIN (cat /opt/rust-stable/toolchain.txt)
end
EOF
chmod 0644 /etc/fish/conf.d/rust.fish

# ---- nushell autoload ----
install -d /etc/nu
cat >/etc/nu/rust.nu <<'EOF'
# Load Rust env for Nushell
source /opt/rust-stable/cargo/env.nu
if not ($env | get RUSTUP_TOOLCHAIN | default "" | is-empty) {
  # already set
} else if ("/opt/rust-stable/toolchain.txt" | path exists) {
  $env.RUSTUP_TOOLCHAIN = (open /opt/rust-stable/toolchain.txt | str trim)
}
EOF
chmod 0644 /etc/nu/rust.nu

# ---- bulletproof multi-call wrapper for non-login shells (/usr/local/bin) ----
install -d /usr/local/bin

# Single env-setting wrapper that dispatches based on invoked name
cat >/usr/local/bin/rustwrap <<'EOF'
#!/bin/sh
# Ensure Rust env from /opt is used even in non-login shells
: "${RUSTUP_HOME:=/opt/rust-stable/rustup}"
: "${CARGO_HOME:=/opt/rust-stable/cargo}"
export RUSTUP_HOME CARGO_HOME PATH="$CARGO_HOME/bin:$PATH"

# If rustup default isn't configured, fall back to the stored toolchain
if [ -z "${RUSTUP_TOOLCHAIN:-}" ] && [ -r /opt/rust-stable/toolchain.txt ]; then
  export RUSTUP_TOOLCHAIN="$(cat /opt/rust-stable/toolchain.txt)"
fi

tool="$(basename "$0")"
exec "$CARGO_HOME/bin/$tool" "$@"
EOF
chmod +x /usr/local/bin/rustwrap

# Symlink common tools to rustwrap
for t in rustup rustc cargo rustfmt clippy-driver cargo-clippy; do
  ln -sfn /usr/local/bin/rustwrap "/usr/local/bin/$t"
done

# ---- friendly summary ----
echo "✅ Rust '${RUST_VERSION}' installed at ${TARGET_DIR} (linked at ${LINK_DIR})."
echo -n "   rustc:  "; /usr/local/bin/rustc  --version || true
echo -n "   cargo:  "; /usr/local/bin/cargo  --version || true

cat <<'EON'
Ready to use:
- Try: rustc --version && cargo --version

EON
