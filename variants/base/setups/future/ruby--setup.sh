#!/bin/bash
set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 [<RUBY_VERSION>] [--ruby-version <RUBY_VERSION>]

Examples:
  $0                   # install default (3.3.5)
  $0 3.2.4             # pin specific MRI version
  $0 jruby-9.4.8.0     # install JRuby
  $0 truffleruby-24.1.1

Notes:
- Installs into /opt/ruby/ruby-<version> then links /opt/ruby-stable
- Binaries exposed via /usr/local/bin (works in non-login shells)
USAGE
}

# ---- root check ----
if [ "$EUID" -ne 0 ]; then
  echo "❌ This script must be run as root (use sudo)" >&2
  exit 1
fi

# ---- defaults ----
RUBY_DEFAULT_VERSION="3.3.5"
RUBY_VERSION_INPUT="${1:-$RUBY_DEFAULT_VERSION}"

# ---- dirs ----
INSTALL_PARENT=/opt/ruby
TARGET_DIR="${INSTALL_PARENT}/ruby-${RUBY_VERSION_INPUT}"
LINK_DIR=/opt/ruby-stable

# ---- base tools ----
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  curl git build-essential libssl-dev libreadline-dev zlib1g-dev \
  libyaml-dev libxml2-dev libxslt-dev libffi-dev autoconf bison \
  libgdbm-dev
rm -rf /var/lib/apt/lists/*

# ---- install rbenv + ruby-build (system-wide) ----
if [ ! -d /opt/rbenv ]; then
  git clone https://github.com/rbenv/rbenv.git /opt/rbenv
  git clone https://github.com/rbenv/ruby-build.git /opt/rbenv/plugins/ruby-build
fi

export RBENV_ROOT=/opt/rbenv
export PATH="$RBENV_ROOT/bin:$PATH"

# ---- install Ruby ----
echo "Installing Ruby ${RUBY_VERSION_INPUT}..."
RBENV_VERSION_DIR="${RBENV_ROOT}/versions/${RUBY_VERSION_INPUT}"

if [ ! -d "$RBENV_VERSION_DIR" ]; then
  rbenv install -s "${RUBY_VERSION_INPUT}"
fi

# Copy to /opt/ruby
rm -rf "$TARGET_DIR"
cp -a "$RBENV_VERSION_DIR" "$TARGET_DIR"

# ---- stable symlink ----
ln -sfn "$TARGET_DIR" "$LINK_DIR"

# ---- wrappers for non-login shells ----
cat >/usr/local/bin/rubywrap <<'EOF'
#!/bin/sh
: "${RUBY_HOME:=/opt/ruby-stable}"
export PATH="$RUBY_HOME/bin:$PATH"

tool="$(basename "$0")"
exec "$RUBY_HOME/bin/$tool" "$@"
EOF
chmod +x /usr/local/bin/rubywrap

for t in ruby irb gem bundle bundler rake rdoc erb; do
  ln -sfn /usr/local/bin/rubywrap "/usr/local/bin/$t"
done

# ---- login-shell env ----
cat >/etc/profile.d/99-ruby--profile.sh <<'EOF'
export RUBY_HOME=/opt/ruby-stable
export PATH="$RUBY_HOME/bin:$PATH"
EOF
chmod 0644 /etc/profile.d/99-ruby--profile.sh

# ---- summary ----
echo "✅ Ruby '${RUBY_VERSION_INPUT}' installed at ${TARGET_DIR} (linked at ${LINK_DIR})."
echo -n "   ruby: "; /usr/local/bin/ruby --version || true
echo -n "   gem:  "; /usr/local/bin/gem --version || true
