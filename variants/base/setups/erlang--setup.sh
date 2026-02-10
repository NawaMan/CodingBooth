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
  $0                       # install default (OTP 27)
  $0 26                    # pin OTP 26
  $0 --otp-version 27      # pin OTP 27
  $0 --no-rebar3           # skip rebar3

Supported OTP versions: 25, 26, 27
  - 25: default Ubuntu repo
  - 26: ppa:rabbitmq/rabbitmq-erlang-26
  - 27: ppa:rabbitmq/rabbitmq-erlang-27

Notes:
- Installs Erlang/OTP via apt (RabbitMQ team PPAs for OTP 26+)
- Binaries available system-wide (erl, erlc, escript, etc.)
- rebar3 installed by default from GitHub releases
USAGE
}

# --- Root check ---
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (use sudo)"; exit 1; }

# --- Defaults ---
OTP_DEFAULT_VERSION="27"
OTP_VERSION_INPUT="${1:-}"
WITH_REBAR3=1

# --- Parse args ---
if [[ "${OTP_VERSION_INPUT}" =~ ^- ]]; then OTP_VERSION_INPUT=""; fi
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
OTP_VERSION="${OTP_VERSION_INPUT:-$OTP_DEFAULT_VERSION}"

# Strip to major version (e.g., 27.0.1 -> 27, 26.2.5 -> 26)
OTP_VERSION="${OTP_VERSION%%.*}"

# Validate
case "$OTP_VERSION" in
  25|26|27) ;;
  *) echo "❌ Unsupported OTP version: ${OTP_VERSION} (supported: 25, 26, 27)" >&2; usage; exit 2 ;;
esac

export DEBIAN_FRONTEND=noninteractive

# --- Add PPA if needed (OTP 26+) ---
echo "📦 Installing Erlang/OTP ${OTP_VERSION} via apt ..."

if [[ "$OTP_VERSION" -ge 26 ]]; then
  apt-get update
  apt-get install -y --no-install-recommends software-properties-common
  add-apt-repository -y "ppa:rabbitmq/rabbitmq-erlang-${OTP_VERSION}"
fi

# --- Install erlang ---
apt-get update
apt-get install -y --no-install-recommends \
  erlang-base erlang-dev erlang-crypto erlang-ssl \
  erlang-public-key erlang-asn1 erlang-inets \
  erlang-mnesia erlang-runtime-tools erlang-syntax-tools \
  erlang-tools erlang-parsetools erlang-eunit \
  erlang-xmerl erlang-os-mon erlang-snmp \
  erlang-eldap erlang-ftp erlang-tftp

rm -rf /var/lib/apt/lists/*

# --- rebar3 (optional) ---
if [[ "$WITH_REBAR3" -eq 1 ]]; then
  echo "📦 Installing rebar3 ..."
  curl -fsSL https://github.com/erlang/rebar3/releases/latest/download/rebar3 -o /usr/local/bin/rebar3
  chmod +x /usr/local/bin/rebar3
fi

# --- env for login shells ---
cat >/etc/profile.d/99-erlang--profile.sh <<'EOF'
# Erlang/OTP via apt
export PATH="/usr/lib/erlang/bin:$PATH"
EOF
chmod 0644 /etc/profile.d/99-erlang--profile.sh

# --- Summary ---
INSTALLED_OTP=$(erl -noshell -eval 'io:format("~s~n",[erlang:system_info(otp_release)]), halt().' 2>/dev/null || echo "unknown")
echo ""
echo "✅ Erlang/OTP ${INSTALLED_OTP} installed."
echo -n "   erl:      "; erl -eval 'erlang:display(erlang:system_info(otp_release)), halt().' -noshell 2>/dev/null || true
echo -n "   erlc:     "; erlc -v 2>/dev/null || true
if [[ "$WITH_REBAR3" -eq 1 ]]; then
  echo -n "   rebar3:   "; rebar3 version 2>/dev/null || true
fi

cat <<'EON'
ℹ️ Ready to use:
- Try: erl -noshell -eval 'io:format("~p~n",[erlang:system_info(otp_release)]), halt().'
- For builds: rebar3 compile    # if installed
- To switch versions, re-run with a different --otp-version.
EON
