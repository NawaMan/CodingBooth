#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 [<OTP_VERSION>] [--otp-version <ver>] [--with-rebar3|--no-rebar3]

Examples:
  $0                       # install default (OTP 28)
  $0 26                    # pin OTP 26 (latest 26.x)
  $0 --otp-version 27      # pin OTP 27 (latest 27.x)
  $0 --otp-version 27.3.4  # pin an exact OTP release
  $0 --no-rebar3           # skip rebar3

Supported OTP versions: 26, 27, 28

Notes:
- Installs a prebuilt Erlang/OTP from builds.hex.pm (the builds Hex, Elixir
  and setup-beam use), built for this Ubuntu release, SHA256-checked against
  the checksum Hex publishes next to it
- Installs to /opt/erlang/OTP-<ver>, linked at /opt/erlang/current
- Binaries available system-wide (erl, erlc, escript, etc.)
- rebar3 installed by default from GitHub releases
USAGE
}

# --- Root check ---
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (use sudo)"; exit 1; }

# --- Defaults ---
OTP_DEFAULT_VERSION="28"
OTP_VERSION_INPUT=""
WITH_REBAR3=1

# --- Parse args ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --otp-version) shift; OTP_VERSION_INPUT="${1:-}"; shift ;;
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

OTP_REQUESTED="${OTP_VERSION_INPUT:-$OTP_DEFAULT_VERSION}"
OTP_REQUESTED="${OTP_REQUESTED#OTP-}"
# Major version (e.g., 27.0.1 -> 27, 26.2.5 -> 26)
OTP_VERSION="${OTP_REQUESTED%%.*}"

# Validate
case "$OTP_VERSION" in
  26|27|28) ;;
  *) echo "❌ Unsupported OTP version: ${OTP_REQUESTED} (supported: 26, 27, 28)" >&2; usage; exit 2 ;;
esac

# --- Platform ---
. /etc/os-release
ARCH="$(dpkg --print-architecture)"
case "$ARCH" in
  amd64|arm64) ;;
  *) echo "❌ Unsupported architecture: ${ARCH} (supported: amd64, arm64)" >&2; exit 1 ;;
esac
BUILDS_URL="https://builds.hex.pm/builds/otp/${ARCH}/ubuntu-${VERSION_ID}"

export DEBIAN_FRONTEND=noninteractive
# Runtime libraries the prebuilt OTP links against (crypto/ssl need libssl,
# the shell needs ncurses' libtinfo).
apt--install.sh ca-certificates curl libssl-dev libncurses6 zlib1g

# --- Resolve the release ---
# builds.txt: one line per build, "OTP-<ver> <git-sha> <date> <sha256>".
BUILDS_TXT="$(curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL "${BUILDS_URL}/builds.txt")" || {
  echo "❌ Could not fetch ${BUILDS_URL}/builds.txt — no Hex OTP builds for Ubuntu ${VERSION_ID} ${ARCH}?" >&2
  exit 1
}
if [[ "$OTP_REQUESTED" == "$OTP_VERSION" ]]; then
  # Major only: the newest release of that major.
  OTP_RELEASE="$(awk '{print $1}' <<<"$BUILDS_TXT" | grep -E "^OTP-${OTP_VERSION}(\.[0-9]+)*$" | sed 's/^OTP-//' | sort -V | tail -1)"
else
  OTP_RELEASE="$(awk '{print $1}' <<<"$BUILDS_TXT" | grep -xF "OTP-${OTP_REQUESTED}" | sed 's/^OTP-//' | head -1)"
fi
if [[ -z "$OTP_RELEASE" ]]; then
  echo "❌ OTP ${OTP_REQUESTED} is not published for Ubuntu ${VERSION_ID} ${ARCH} at ${BUILDS_URL}" >&2
  exit 1
fi
OTP_SHA256="$(awk -v r="OTP-${OTP_RELEASE}" '$1 == r {print $4; exit}' <<<"$BUILDS_TXT")"

# --- Download, verify, install ---
echo "📦 Installing Erlang/OTP ${OTP_RELEASE} (${ARCH}, Ubuntu ${VERSION_ID}) from builds.hex.pm ..."
INSTALL_PARENT=/opt/erlang
TARGET_DIR="${INSTALL_PARENT}/OTP-${OTP_RELEASE}"
TMP_TGZ="$(mktemp --suffix=.tar.gz)"
trap 'rm -f "$TMP_TGZ"' EXIT
curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL "${BUILDS_URL}/OTP-${OTP_RELEASE}.tar.gz" -o "$TMP_TGZ"
if [[ -n "$OTP_SHA256" ]]; then
  echo "${OTP_SHA256}  ${TMP_TGZ}" | sha256sum -c - >/dev/null || {
    echo "❌ SHA256 mismatch for OTP-${OTP_RELEASE}.tar.gz" >&2
    exit 1
  }
else
  echo "⚠️  builds.txt lists no checksum for OTP-${OTP_RELEASE}; installing unverified." >&2
fi

rm -rf "$TARGET_DIR"
mkdir -p "$INSTALL_PARENT"
tar -xzf "$TMP_TGZ" -C "$INSTALL_PARENT"
[[ -x "${TARGET_DIR}/Install" ]] || { echo "❌ Unexpected archive layout (no ${TARGET_DIR}/Install)" >&2; exit 1; }
# The tarball is relocatable: Install rewrites its launch scripts for this path.
"${TARGET_DIR}/Install" -minimal "$TARGET_DIR" >/dev/null
ln -sfn "$TARGET_DIR" "${INSTALL_PARENT}/current"

for b in erl erlc escript ct_run dialyzer typer epmd run_erl to_erl; do
  if [[ -e "${INSTALL_PARENT}/current/bin/${b}" ]]; then
    ln -sfn "${INSTALL_PARENT}/current/bin/${b}" "/usr/local/bin/${b}"
  fi
done

# --- verify the requested version actually got installed ---
INSTALLED_OTP_MAJOR=$(erl -noshell -eval 'io:format("~s~n",[erlang:system_info(otp_release)]), halt().' 2>/dev/null || echo "")
if [[ "$INSTALLED_OTP_MAJOR" != "$OTP_VERSION" ]]; then
  echo "❌ Erlang/OTP did not install correctly (expected OTP ${OTP_VERSION}, erl reports '${INSTALLED_OTP_MAJOR}')." >&2
  exit 1
fi
if ! erl -noshell -eval 'ok = crypto:start(), halt().' >/dev/null 2>&1; then
  echo "❌ Erlang/OTP ${OTP_RELEASE} installed, but its crypto application cannot load (libssl mismatch?)." >&2
  exit 1
fi

# --- rebar3 (optional) ---
if [[ "$WITH_REBAR3" -eq 1 ]]; then
  echo "📦 Installing rebar3 ..."
  curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL https://github.com/erlang/rebar3/releases/latest/download/rebar3 -o /usr/local/bin/rebar3
  chmod +x /usr/local/bin/rebar3
fi

# --- env for login shells ---
cat >/etc/profile.d/99-erlang--profile.sh <<'EOF'
# Erlang/OTP from builds.hex.pm
export PATH="/opt/erlang/current/bin:$PATH"
EOF
chmod 0644 /etc/profile.d/99-erlang--profile.sh

echo "✅ Erlang/OTP ${OTP_RELEASE} installed"
echo -n "   erl → "; erl -noshell -eval 'io:format("OTP ~s (erts ~s)~n",[erlang:system_info(otp_release), erlang:system_info(version)]), halt().'
if [[ "$WITH_REBAR3" -eq 1 ]]; then
  echo -n "   rebar3 → "; rebar3 version 2>/dev/null || echo "not found"
fi

cat <<'EON'
ℹ️ Ready to use:
- Try: erl -noshell -eval 'io:format("~p~n",[erlang:system_info(otp_release)]), halt().'
- For builds: rebar3 compile    # if installed
- To switch versions, re-run with a different --otp-version.
EON
