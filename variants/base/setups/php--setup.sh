#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 [--version <MAJOR.MINOR>] [--with-composer] [--with-fpm] [--extensions "ext1,ext2,..."] [--no-default-exts]

Examples:
  $0                            # PHP 8.3 CLI + common extensions
  $0 --version 8.2              # PHP 8.2 instead
  $0 --with-composer            # also install Composer globally
  $0 --with-fpm                 # install php-fpm (service not enabled in containers)
  $0 --extensions "curl,gd,intl"  # choose your own extension set
  $0 --no-default-exts            # install only core + dev tools (no extra exts)

Notes:
- Installs under /opt/php/php-<ver> and links /opt/php-stable
- Exposes php/pecl/phpize/php-config via /usr/local/bin (non-login shells OK)
- Uses apt packages (php<ver>-*) for speed & security
- Composer is optional and installed to /usr/local/bin/composer
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# ---- defaults / args ----
PHP_DEFAULT_VER="8.3"
PHP_VER="$PHP_DEFAULT_VER"
WITH_COMPOSER=0
WITH_FPM=0
NO_DEFAULT_EXTS=0
CUSTOM_EXTS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; PHP_VER="${1:-$PHP_DEFAULT_VER}"; shift ;;
    --with-composer) WITH_COMPOSER=1; shift ;;
    --with-fpm)      WITH_FPM=1; shift ;;
    --extensions)    shift; CUSTOM_EXTS="${1:-}"; shift ;;
    --no-default-exts) NO_DEFAULT_EXTS=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

# sanitize version like 8.3 / 8.2
if ! [[ "$PHP_VER" =~ ^[0-9]+\.[0-9]+$ ]]; then
  echo "❌ --version must be like '8.3' or '8.2'"; exit 2
fi

# ---- base deps ----
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends lsb-release software-properties-common
rm -rf /var/lib/apt/lists/*

# ---- enable ondrej/php PPA when the requested version isn't in main repos ----
# (Safe on Ubuntu; on Debian you usually stick to distro PHP or use sury.org Debian repo)
. /etc/os-release
is_ubuntu=0; [[ "${ID:-}" == "ubuntu" || "${ID_LIKE:-}" == *ubuntu* ]] && is_ubuntu=1
if [[ $is_ubuntu -eq 1 ]]; then
  # Add PPA only if needed (or if it isn't already present)
  if ! apt-cache policy | grep -q "ppa.launchpadcontent.net/ondrej/php"; then
    add-apt-repository -y ppa:ondrej/php
  fi
  apt-get update
fi

# ---- build the package list for the requested version ----
# Core CLI + dev tools
PKGS=( "php${PHP_VER}-cli" "php${PHP_VER}-dev" "php${PHP_VER}-opcache" "php${PHP_VER}-readline" )

# FPM (optional)
[[ $WITH_FPM -eq 1 ]] && PKGS+=( "php${PHP_VER}-fpm" )

# Extensions
if [[ $NO_DEFAULT_EXTS -eq 0 ]]; then
  # Safe, common default set (tweak as you like)
  DEFAULT_EXTS=( bcmath curl gd intl mbstring xml zip sqlite3 )
  for e in "${DEFAULT_EXTS[@]}"; do PKGS+=( "php${PHP_VER}-$e" ); done
fi

# Custom ext list overrides/augments
if [[ -n "$CUSTOM_EXTS" ]]; then
  IFS=',' read -r -a CEXTS <<<"$CUSTOM_EXTS"
  for e in "${CEXTS[@]}"; do
    e_trim="$(echo "$e" | xargs)"
    [[ -n "$e_trim" ]] && PKGS+=( "php${PHP_VER}-${e_trim}" )
  done
fi

# ---- install packages ----
apt-get install -y --no-install-recommends "${PKGS[@]}"
rm -rf /var/lib/apt/lists/*

# ---- normalize into /opt layout ----
INSTALL_PARENT=/opt/php
TARGET_DIR="${INSTALL_PARENT}/php-${PHP_VER}"
LINK_DIR=/opt/php-stable
BIN_DIR=/usr/local/bin

rm -rf "$TARGET_DIR"
mkdir -p "$TARGET_DIR/bin" "$TARGET_DIR/etc" "$TARGET_DIR/lib"

# Find actual binaries (apt puts them at /usr/bin/php${PHP_VER}, /usr/bin/pecl${PHP_VER} on PPA;
# fallback to generic paths if distro uses alternatives)
PHP_BIN="$(command -v php${PHP_VER} || true)"
PECL_BIN="$(command -v pecl${PHP_VER} || command -v pecl || true)"
PHPIZE_BIN="$(command -v phpize${PHP_VER} || command -v phpize || true)"
PHPCONFIG_BIN="$(command -v php-config${PHP_VER} || command -v php-config || true)"

# Require PHP binary to exist
[[ -x "$PHP_BIN" ]] || { echo "❌ Could not find php${PHP_VER} binary after install"; exit 1; }

# Symlink into /opt/php/php-<ver>/bin
ln -sfn "$PHP_BIN"        "$TARGET_DIR/bin/php"
[[ -n "$PECL_BIN" ]]      && ln -sfn "$PECL_BIN"      "$TARGET_DIR/bin/pecl"
[[ -n "$PHPIZE_BIN" ]]    && ln -sfn "$PHPIZE_BIN"    "$TARGET_DIR/bin/phpize"
[[ -n "$PHPCONFIG_BIN" ]] && ln -sfn "$PHPCONFIG_BIN" "$TARGET_DIR/bin/php-config"

# php.ini locations (don’t overwrite; just provide convenience links if present)
if [[ -d "/etc/php/${PHP_VER}" ]]; then
  ln -sfn "/etc/php/${PHP_VER}" "$TARGET_DIR/etc/php"
fi

# Stable link
ln -sfn "$TARGET_DIR" "$LINK_DIR"

# ---- login-shell env (PATH only) ----
cat >/etc/profile.d/99-php--profile.sh <<'EOF'
# PHP under /opt
export PHP_HOME=/opt/php-stable
export PATH="$PHP_HOME/bin:$PATH"
EOF
chmod 0644 /etc/profile.d/99-php--profile.sh

# ---- non-login wrapper (so php works in Docker RUN etc.) ----
install -d "$BIN_DIR"
cat >"${BIN_DIR}/phpwrap" <<'EOF'
#!/bin/sh
: "${PHP_HOME:=/opt/php-stable}"
export PHP_HOME PATH="$PHP_HOME/bin:$PATH"
tool="$(basename "$0")"
exec "$PHP_HOME/bin/$tool" "$@"
EOF
chmod +x "${BIN_DIR}/phpwrap"

# expose php & friends
ln -sfn "${BIN_DIR}/phpwrap" "${BIN_DIR}/php"
[[ -x "$TARGET_DIR/bin/pecl" ]]       && ln -sfn "${BIN_DIR}/phpwrap" "${BIN_DIR}/pecl"
[[ -x "$TARGET_DIR/bin/phpize" ]]     && ln -sfn "${BIN_DIR}/phpwrap" "${BIN_DIR}/phpize"
[[ -x "$TARGET_DIR/bin/php-config" ]] && ln -sfn "${BIN_DIR}/phpwrap" "${BIN_DIR}/php-config"

# ---- Composer (optional) ----
if [[ $WITH_COMPOSER -eq 1 ]]; then
  echo "⬇️  Installing Composer ..."
  curl -fsSL https://getcomposer.org/installer -o /tmp/composer-setup.php
  # You can add signature verification here if you like (sha384)
  php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer
  rm -f /tmp/composer-setup.php
fi

# ---- FPM footnote (optional) ----
if [[ $WITH_FPM -eq 1 ]]; then
  # Don’t enable services in containers; but leave a note
  echo "ℹ️ php-fpm installed (php${PHP_VER}-fpm). Service not enabled in containers."
fi

# ---- friendly summary ----
echo "✅ PHP ${PHP_VER} installed at ${TARGET_DIR} (linked at ${LINK_DIR})."
echo -n "   php -v → "; "${BIN_DIR}/php" -v 2>/dev/null | head -n2 || true
[[ $WITH_COMPOSER -eq 1 ]] && { echo -n "   composer -V → "; command -v composer >/dev/null && composer -V || echo "composer not found"; }

cat <<'EON'
ℹ️ Ready to use:
- Try: php -v
- PECL: pecl version        (build extensions from source if desired)
- phpize/php-config available for compiling extensions
- Composer (if installed): composer --version

Tips:
- Switch PHP versions later by re-running this script with --version (updates /opt/php-stable).
- PHP-FPM is optional and off by default to keep images slim.
- INI: use /etc/php/<ver>/cli/php.ini (this script just links it under /opt/php-<ver>/etc).
EON
