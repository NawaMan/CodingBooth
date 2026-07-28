#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# This script installs PHP PECL extensions.
# It requires php--setup.sh to have been run first.
# Usage: pecl--install.sh <extension> [extension...]
# Example: pecl--install.sh redis xdebug

set -Eeuo pipefail
trap 'echo "Error on line $LINENO"; exit 1' ERR

if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root (use sudo)" >&2
    exit 1
fi

if [ $# -eq 0 ]; then
    echo "Usage: $0 <extension> [extension...]" >&2
    exit 1
fi

# Expand comma-separated packages into separate arguments
set -- $(echo "$@" | tr ',' ' ')

PHP_HOME="${PHP_HOME:-/opt/php-stable}"
export PATH="$PHP_HOME/bin:$PATH"

if ! command -v pecl &> /dev/null; then
    echo "PECL not found. Run php--setup.sh first." >&2
    exit 1
fi

for ext in "$@"; do
    echo "Installing PECL extension: $ext"
    # No `|| true`: pecl builds from source, and a failed build (a missing compiler,
    # say) must fail the image rather than produce a booth where the extension is
    # quietly absent.
    pecl install "$ext"

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
