#!/bin/bash
set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 [<OTP_VERSION>] [--otp-version <ver>] [--with-wx|--no-wx] [--with-rebar3|--no-rebar3]

Examples:
  $0                       # install default (27.0.1), no wx, with rebar3
  $0 26.2.5                # pin a specific OTP
  $0 --otp-version 27.1 --with-wx
  $0 --no-rebar3           # skip rebar3

Notes:
- Erlang/OTP is built with kerl into /opt/erlang/erlang-<ver>, then linked at /opt/erlang-stable
- Binaries exposed via /usr/local/bin (works in non-login shells)
USAGE
}

# --- Root check ---
if [ "$EUID" -ne 0 ]; then
  echo "❌ This script must be run as root (use sudo)" >&2
  exit 1
fi

# --- Defaults (adjust OTP_DEFAULT_VERSION as you like) ---
OTP_DEFAULT_VERSION="27.0.1"
OTP_VERSION_INPUT="${1:-}"
WITH_WX=0              # off by default; enables Observer (needs GUI libs)
WITH_REBAR3=1

# --- Parse args ---
if [[ "${OTP_VERSION_INPUT}" =~ ^- ]]; then OTP_VERSION_INPUT=""; fi
while [[ $# -gt 0 ]]; do
  case "$1" in
    --otp-version) shift; OTP_VERSION_INPUT="${1:-}"; shift ;;
    --with-wx)     WITH_WX=1; shift ;;
    --no-wx)       WITH_WX=0; shift ;;
    --with-rebar3) WITH_REBAR3=1; shift ;;
    --no-rebar3)   WITH_REBAR3=0; shift ;;
    -h|--help)     usage; exit 0 ;;
    *)
      if [[ -z "$OTP_VERSION_INPUT" ]]; then
        OTP_VERSION_INPUT="$1"; shift
      else
        echo "❌ Unknown argument: $1" >&2; usage; exit 2
      fi
      ;;
  esac
done
OTP_VERSION="${OTP_VERSION_INPUT:-$OTP_DEFAULT_VERSION}"

# --- Arch guard (Ubuntu/Debian) ---
dpkgArch="$(dpkg --print-architecture)"
case "$dpkgArch" in
  amd64|arm64) ;;
  *) echo "❌ Unsupported arch: $dpkgArch (supported: amd64, arm64)" >&2; exit 1 ;;
esac

# --- Paths ---
INSTALL_PARENT=/opt/erlang
TARGET_DIR="${INSTALL_PARENT}/erlang-${OTP_VERSION}"
LINK_DIR=/opt/erlang-stable

# kerl build name (safe for re-runs)
BUILD_NAME="otp_${OTP_VERSION}"

# --- Base dependencies ---
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  curl git ca-certificates build-essential autoconf m4 libncurses5-dev \
  libssl-dev unixodbc-dev libxslt1-dev xsltproc \
  libxml2-dev zlib1g-dev # general deps
# wx/Observer (optional, big)
if [ "$WITH_WX" -eq 1 ]; then
  apt-get install -y --no-install-recommends \
    libgl1-mesa-dev libglu1-mesa-dev libgtk-3-dev libwxgtk3.2-dev
fi
rm -rf /var/lib/apt/lists/*

# --- Clean old PATH shims if present (idempotent) ---
for b in erl erlc escript dialyzer typer rebar3; do
  rm -f "/usr/local/bin/$b" || true
done

# --- Prepare target dir fresh ---
rm -rf "$TARGET_DIR"
mkdir -p "$TARGET_DIR"

# --- Install kerl system-wide (simple bash script) ---
install -d /usr/local/bin
if ! command -v kerl >/dev/null 2>&1; then
  curl -fsSL https://raw.githubusercontent.com/kerl/kerl/master/kerl -o /usr/local/bin/kerl
  chmod +x /usr/local/bin/kerl
fi

# --- Configure kerl build options ---
# Keep builds small: skip docs, manpages. Add wx if requested.
KERL_CONFIGURE_OPTIONS="--without-javac --disable-dynamic-ssl-lib --without-docs --without-odbc"  # odbc disabled to reduce deps; remove flag to enable
# Enable ODBC if you actually want it (requires unixodbc-dev above)
# KERL_CONFIGURE_OPTIONS="--without-javac --disable-dynamic-ssl-lib --without-docs"

if [ "$WITH_WX" -eq 1 ]; then
  KERL_CONFIGURE_OPTIONS="${KERL_CONFIGURE_OPTIONS} --with-wx"
else
  KERL_CONFIGURE_OPTIONS="${KERL_CONFIGURE_OPTIONS} --without-wx"
fi
export KERL_CONFIGURE_OPTIONS
export KERL_BUILD_BACKEND=git   # Build from the official git tags

echo "🔧 Building Erlang/OTP ${OTP_VERSION} with kerl (wx=$([ $WITH_WX -eq 1 ] && echo on || echo off)) ..."
# kerl caches builds under ~/.kerl by default; override to inside TARGET_DIR for isolation
export KERL_BASE_DIR="${TARGET_DIR}/.kerl"
mkdir -p "${KERL_BASE_DIR}"

# Build (skip if already built in cache)
kerl build "${OTP_VERSION}" "${BUILD_NAME}" || true

# Install into TARGET_DIR
kerl install "${BUILD_NAME}" "${TARGET_DIR}" 

# --- Sanity: ensure bin exists ---
if [ ! -x "${TARGET_DIR}/bin/erl" ]; then
  echo "❌ Failed to install Erlang/OTP ${OTP_VERSION} to ${TARGET_DIR}" >&2
  exit 1
fi

# --- rebar3 (optional) ---
if [ "$WITH_REBAR3" -eq 1 ]; then
  echo "📦 Installing rebar3 ..."
  curl -fsSL https://github.com/erlang/rebar3/releases/latest/download/rebar3 -o "${TARGET_DIR}/bin/rebar3"
  chmod +x "${TARGET_DIR}/bin/rebar3" || true
fi

# --- Stable link (/opt/erlang-stable) ---
ln -sfn "${TARGET_DIR}" "${LINK_DIR}"

# --- Login-shell env (POSIX) ---
cat >/etc/profile.d/99-erlang--profile.sh <<'EOF'
# Erlang/OTP under /opt
export ERLANG_HOME=/opt/erlang-stable
export PATH="$ERLANG_HOME/bin:$PATH"
EOF
chmod 0644 /etc/profile.d/99-erlang--profile.sh

# --- fish & nushell autoloads ---
install -d /etc/fish/conf.d
cat >/etc/fish/conf.d/erlang.fish <<'EOF'
set -gx ERLANG_HOME /opt/erlang-stable
if test -d $ERLANG_HOME/bin
  fish_add_path -g $ERLANG_HOME/bin
end
EOF
chmod 0644 /etc/fish/conf.d/erlang.fish

install -d /etc/nu
cat >/etc/nu/erlang.nu <<'EOF'
$env.ERLANG_HOME = "/opt/erlang-stable"
let b = ($env.ERLANG_HOME | path join "bin")
if ($b | path exists) { $env.PATH = ($b | path add $env.PATH) }
EOF
chmod 0644 /etc/nu/erlang.nu

# --- Multi-call wrapper for non-login shells ---
cat >/usr/local/bin/erlwrap <<'EOF'
#!/bin/sh
: "${ERLANG_HOME:=/opt/erlang-stable}"
export PATH="$ERLANG_HOME/bin:$PATH"
tool="$(basename "$0")"
exec "$ERLANG_HOME/bin/$tool" "$@"
EOF
chmod +x /usr/local/bin/erlwrap

# Symlink common tools through the wrapper
for t in erl erlc escript dialyzer typer; do
  ln -sfn /usr/local/bin/erlwrap "/usr/local/bin/$t"
done
# rebar3 wrapper if installed
if [ -x "${TARGET_DIR}/bin/rebar3" ]; then
  ln -sfn /usr/local/bin/erlwrap "/usr/local/bin/rebar3"
fi

# --- Summary ---
echo "✅ Erlang/OTP '${OTP_VERSION}' installed at ${TARGET_DIR} (linked at ${LINK_DIR})."
echo -n "   erl:      "; /usr/local/bin/erl -eval 'erlang:display(erlang:system_info(otp_release)), halt().' -noshell 2>/dev/null || true
echo -n "   erlc:     "; /usr/local/bin/erlc -v 2>/dev/null || true
if [ -x "${TARGET_DIR}/bin/rebar3" ]; then
  echo -n "   rebar3:   "; /usr/local/bin/rebar3 version 2>/dev/null || true
fi

cat <<'EON'
ℹ️ Ready to use:
- Try: erl -noshell -eval 'io:format("~p~n",[erlang:system_info(otp_release)]), halt().'
- For builds: rebar3 compile    # if installed
- Works in login & non-login shells (wrapper primes PATH)
- Re-run script with a different --otp-version to install side-by-side at /opt/erlang/erlang-<ver>
EON
