#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# This script installs PHP PECL extensions.
# It requires php--setup.sh to have been run first.
# Usage: pecl--install.sh <extension[-version]> [extension[-version]...]
# Example: pecl--install.sh redis xdebug-3.3.2

set -Eeuo pipefail
trap 'echo "Error on line $LINENO"; exit 1' ERR

if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root (use sudo)" >&2
    exit 1
fi

case "${1:-}" in
    -h|--help)
        echo "Usage: $0 <extension[-version]> [extension[-version]...]"
        exit 0
        ;;
esac

# Expand comma-separated packages into separate arguments
set -- $(echo "$@" | tr ',' ' ')

# No PECL extensions requested is a no-op, not an error: the *-pkg templates emit
# `install pecl ${..._PKGS}` with the package list defaulting to empty, so
# failing here would break the image build of every project that selects the
# extension without naming packages.
if [ $# -eq 0 ]; then
    echo "ℹ️  No PECL extensions requested; nothing to install."
    exit 0
fi

PHP_HOME="${PHP_HOME:-/opt/php-stable}"
export PATH="$PHP_HOME/bin:$PATH"

if ! command -v pecl &> /dev/null; then
    echo "PECL not found. Run php--setup.sh first." >&2
    exit 1
fi

for spec in "$@"; do
    # The version is part of the *request*, never part of the extension name:
    # `pecl install redis-6.0.2` builds redis.so. Checking for redis-6.0.2.so
    # failed every pinned install, which is why the pin was undocumented. Strip
    # only a suffix that looks like a version or a PECL state tag, so a name that
    # happens to contain a hyphen is left alone; a wrong guess still fails loudly
    # on the .so check below rather than installing something unloaded.
    ext="$spec"
    if [[ "$spec" =~ ^(.+)-([0-9].*|alpha|beta|devel|snapshot|stable)$ ]]; then
        ext="${BASH_REMATCH[1]}"
    fi

    echo "Installing PECL extension: $spec"
    # No `|| true`: pecl builds from source, and a failed build (a missing compiler,
    # say) must fail the image rather than produce a booth where the extension is
    # quietly absent.
    pecl install "$spec"

    PHP_EXT_DIR="$(php -i | awk -F' => ' '/^extension_dir/ {print $2; exit}')"
    if [ ! -f "${PHP_EXT_DIR}/${ext}.so" ]; then
        echo "pecl reported success but ${ext}.so is not in ${PHP_EXT_DIR}" >&2
        exit 1
    fi

    # Enable it in the directory this PHP actually scans. The old code wrote into
    # /etc/php/<ver>/mods-available, which nothing reads without a2enmod-style
    # symlinking, so the extension stayed unloaded even when it had built fine.
    SCAN_DIR="$(php -i | awk -F' => ' '/^Scan this dir for additional .ini files/ {print $2; exit}')"
    if [ -z "$SCAN_DIR" ] || [ ! -d "$SCAN_DIR" ]; then
        echo "Could not determine PHP's additional-.ini scan directory" >&2
        exit 1
    fi
    echo "extension=${ext}.so" > "${SCAN_DIR}/${ext}.ini"
    echo "  enabled via ${SCAN_DIR}/${ext}.ini"
done

echo "PECL extensions installed."
