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
  $0 26                    # pin OTP 26
  $0 --otp-version 27      # pin OTP 27
  $0 --no-rebar3           # skip rebar3

Supported OTP versions: 25, 26, 27, 28
  - 25: default Ubuntu repo
  - 26: ppa:rabbitmq/rabbitmq-erlang-26
  - 27: ppa:rabbitmq/rabbitmq-erlang-27
  - 28: ppa:rabbitmq/rabbitmq-erlang-28

Notes:
- Installs Erlang/OTP via apt (RabbitMQ team PPAs for OTP 26+)
- Binaries available system-wide (erl, erlc, escript, etc.)
- rebar3 installed by default from GitHub releases
USAGE
}

# --- Root check ---
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (use sudo)"; exit 1; }

# --- Defaults ---
OTP_DEFAULT_VERSION="28"
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
  25|26|27|28) ;;
  *) echo "❌ Unsupported OTP version: ${OTP_VERSION} (supported: 25, 26, 27, 28)" >&2; usage; exit 2 ;;
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

# --- verify the requested version actually got installed ---
# On arm64, ppa:rabbitmq/rabbitmq-erlang-26/27/28 publishes only a handful of
# arch-independent metapackages (erlang, erlang-nox, ...) — none of the
# granular erlang-base/erlang-dev/... packages installed above by name. apt
# then silently satisfies those names from Ubuntu's own default archive,
# which only carries OTP 25 on that architecture, so a request for 26/27/28
# quietly becomes 25 with no error from apt at all — until something
# downstream (e.g. elixir--setup.sh picking a release asset for "the
# installed OTP") fails confusingly, far away from the actual cause. Check
# at the source instead of letting that happen.
INSTALLED_OTP_MAJOR=$(erl -noshell -eval 'io:format("~s~n",[erlang:system_info(otp_release)]), halt().' 2>/dev/null || echo "")
if [[ -z "$INSTALLED_OTP_MAJOR" ]]; then
  echo "❌ Erlang/OTP did not install correctly (erl not runnable)." >&2
  exit 1
fi
if [[ "$INSTALLED_OTP_MAJOR" != "$OTP_VERSION" ]]; then
  ARCH="$(dpkg --print-architecture 2>/dev/null || uname -m)"
  echo "❌ Requested OTP ${OTP_VERSION} but apt installed OTP ${INSTALLED_OTP_MAJOR} instead." >&2
  echo "   On ${ARCH}, ppa:rabbitmq/rabbitmq-erlang-${OTP_VERSION} does not publish the" >&2
  echo "   individual erlang-base/erlang-dev/... packages this script installs by name" >&2
  echo "   — only a few arch-independent metapackages. apt silently fell back to" >&2
  echo "   Ubuntu's default archive, which only has OTP 25 on this architecture." >&2
  echo "   Use --otp-version 25, or build/run this on an amd64 host." >&2
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
