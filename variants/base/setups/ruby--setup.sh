#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 1.1.0

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# --------------------------
# Root setup - installs Ruby at BUILD time
# --------------------------
[ "$EUID" -eq 0 ] || { echo "❌ Run as root (use sudo)"; exit 1; }

# This script will always be installed by root.
HOME=/root

# --- Defaults ---
RUBY_VERSION="${1:-3.4}"

LEVEL=59                          # See README.md - Profile Ordering

STARTUP_FILE="/usr/share/startup.d/${LEVEL}-cb-ruby--startup.sh"
PROFILE_FILE="/etc/profile.d/${LEVEL}-cb-ruby--profile.sh"

# Install rbenv and ruby-build
echo "📦 Installing rbenv..."
# github.com intermittently answers 429/503 during a full build sweep and git has
# no --retry of its own, so retry with backoff. Clear the partial clone first —
# git refuses to clone into a non-empty directory.
clone_with_retry() {
  local url="$1" dest="$2" attempt
  for attempt in 1 2 3; do
    if git clone "$url" "$dest"; then return 0; fi
    if [ "$attempt" = 3 ]; then echo "❌ clone of $url failed after 3 attempts"; return 1; fi
    echo "  ⚠️  clone failed — retrying in $((attempt * 5))s ..."
    rm -rf "$dest"
    sleep $((attempt * 5))
  done
}
clone_with_retry https://github.com/rbenv/rbenv.git      /opt/rbenv
clone_with_retry https://github.com/rbenv/ruby-build.git /opt/rbenv/plugins/ruby-build

export RBENV_ROOT="/opt/rbenv"
export PATH="/opt/rbenv/bin:/opt/rbenv/shims:$PATH"

# Initialize rbenv
eval "$(rbenv init -)"

# Determine full version - if already has patch (x.y.z), use as-is; otherwise find latest patch
if [[ "$RUBY_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    # Exact version specified (e.g., 3.3.0)
    FULL_VERSION="$RUBY_VERSION"
    echo "📌 Using exact Ruby version: ${FULL_VERSION}"
else
    # Major.minor specified (e.g., 3.3) - find latest patch
    echo "🔎 Finding latest Ruby ${RUBY_VERSION}.x version..."
    FULL_VERSION=$(rbenv install -l 2>/dev/null | grep -E "^[[:space:]]*${RUBY_VERSION}\.[0-9]+$" | tail -1 | tr -d ' ')
fi

if [ -z "$FULL_VERSION" ]; then
    echo "❌ Could not find Ruby version matching ${RUBY_VERSION}"
    exit 1
fi

# Prebuilt: ruby/ruby-builder publishes a tarball per version, Ubuntu release
# and arch (the ones GitHub's setup-ruby uses), so nothing is compiled. They are
# not relocatable -- RUNPATH and shebangs point at
# /opt/hostedtoolcache/Ruby/<version>/<x64|arm64> -- so they are extracted there
# and linked into rbenv's versions dir. The sha256 comes from the release's
# asset digest; a mismatch stops the setup. No asset for this version, Ubuntu
# or arch (or no digest to check it against) falls back to a source build.
PREBUILT_REPO="ruby/ruby-builder"
TOOLCACHE_DIR="/opt/hostedtoolcache/Ruby"

install_prebuilt() {
  local arch ubuntu name tag api digest want got_sum tmp
  case "$(uname -m)" in
    x86_64|amd64)  arch=x64   ;;
    aarch64|arm64) arch=arm64 ;;
    *) return 1 ;;
  esac
  ubuntu="$(. /etc/os-release && [ "$ID" = ubuntu ] && echo "$VERSION_ID")" || return 1
  [ -n "$ubuntu" ] || return 1
  tag="ruby-${FULL_VERSION}"
  name="${tag}-ubuntu-${ubuntu}-${arch}.tar.gz"
  api="https://api.github.com/repos/${PREBUILT_REPO}/releases/tags/${tag}"

  digest="$(curl --connect-timeout 15 --retry 3 --retry-delay 3 -fsSL "$api" 2>/dev/null \
            | jq -r --arg n "$name" '.assets[] | select(.name == $n) | .digest // empty' 2>/dev/null)" || digest=""
  if [[ "$digest" != sha256:* ]]; then
    echo "ℹ️  No prebuilt Ruby ${FULL_VERSION} for Ubuntu ${ubuntu} ${arch} (${name}); building from source."
    return 1
  fi
  want="${digest#sha256:}"

  tmp="$(mktemp -d)"
  echo "⬇️  Downloading prebuilt Ruby ${FULL_VERSION} (Ubuntu ${ubuntu}, ${arch}) ..."
  curl --connect-timeout 15 --retry 3 --retry-delay 3 --retry-all-errors \
    -fsSL "https://github.com/${PREBUILT_REPO}/releases/download/${tag}/${name}" -o "$tmp/$name"
  got_sum="$(sha256sum "$tmp/$name" | awk '{print $1}')"
  if [ "$want" != "$got_sum" ]; then
    echo "❌ ${name}: sha256 ${got_sum} does not match the release's ${want}" >&2
    rm -rf "$tmp"
    exit 1
  fi

  install_gem_build_deps

  rm -rf "${TOOLCACHE_DIR:?}/${FULL_VERSION}"
  mkdir -p "${TOOLCACHE_DIR}/${FULL_VERSION}"
  tar -xzf "$tmp/$name" -C "${TOOLCACHE_DIR}/${FULL_VERSION}"
  rm -rf "$tmp"
  [ -x "${TOOLCACHE_DIR}/${FULL_VERSION}/${arch}/bin/ruby" ] \
    || { echo "❌ ${name} has no ${arch}/bin/ruby" >&2; exit 1; }
  chmod -R a+rX /opt/hostedtoolcache

  mkdir -p "${RBENV_ROOT}/versions"
  ln -sfn "${TOOLCACHE_DIR}/${FULL_VERSION}/${arch}" "${RBENV_ROOT}/versions/${FULL_VERSION}"
  "${RBENV_ROOT}/versions/${FULL_VERSION}/bin/ruby" -e 'require "openssl"; require "psych"; require "fiddle"' \
    || { echo "❌ prebuilt Ruby ${FULL_VERSION} cannot load openssl/psych/fiddle" >&2; exit 1; }
  rbenv rehash
}

# A compiler and headers for gems with native extensions (pg, ffi, nokogiri from
# source, ...). The prebuilt Ruby itself only needs libffi8 and libyaml-0-2, which
# these pull in; the base image has no compiler of its own.
install_gem_build_deps() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends "$@" \
      build-essential \
      libssl-dev \
      libyaml-dev \
      libreadline-dev \
      zlib1g-dev \
      libncurses-dev \
      libffi-dev \
      libgdbm-dev
  rm -rf /var/lib/apt/lists/*
}

build_from_source() {
  install_gem_build_deps autoconf bison
  echo "📦 Building Ruby ${FULL_VERSION} from source..."
  RUBY_CONFIGURE_OPTS="--disable-install-doc" rbenv install "$FULL_VERSION"
}

echo "📦 Installing Ruby ${FULL_VERSION}..."
install_prebuilt || build_from_source
rbenv global "$FULL_VERSION"

# Make rbenv accessible
chmod -R a+rX /opt/rbenv

# Verify installation
echo "• Verifying installation..."
ruby --version
gem --version

# ---- Create startup file: to be executed as normal user on first login ----
cat > "${STARTUP_FILE}" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

SENTINEL="$HOME/.ruby-startup-done"
[[ -f "$SENTINEL" ]] || {
  mkdir -p "$HOME/.gem/bin"
  touch "$SENTINEL"
}
EOF
chmod 755 "${STARTUP_FILE}"

# ---- Create profile file: to be sourced at the beginning of a user shell session ----
cat > "${PROFILE_FILE}" << 'EOF'
# Profile: Ruby (rbenv)

export RBENV_ROOT="/opt/rbenv"

# Add rbenv to PATH
case ":$PATH:" in
  *":/opt/rbenv/bin:"*) ;;
  *) export PATH="/opt/rbenv/bin:$PATH";;
esac

# Add rbenv shims to PATH
case ":$PATH:" in
  *":/opt/rbenv/shims:"*) ;;
  *) export PATH="/opt/rbenv/shims:$PATH";;
esac

# Initialize rbenv
eval "$(rbenv init - bash)"

# Configure gem to install to user directory
export GEM_HOME="$HOME/.gem"
case ":$PATH:" in
  *":$HOME/.gem/bin:"*) ;;
  *) export PATH="$HOME/.gem/bin:$PATH";;
esac
EOF
chmod 644 "${PROFILE_FILE}"

echo "✅ .... Ruby is installed ...."
echo "• Version: ${FULL_VERSION}"
echo "• RBENV_ROOT: /opt/rbenv"
echo "• Startup file: ${STARTUP_FILE}"
echo "• Profile file: ${PROFILE_FILE}"
echo ""
echo "You may source the profile above to start using Ruby in this session."
