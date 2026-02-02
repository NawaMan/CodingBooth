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

PHP_HOME="${PHP_HOME:-/opt/php-stable}"
export PATH="$PHP_HOME/bin:$PATH"

if ! command -v pecl &> /dev/null; then
    echo "PECL not found. Run php--setup.sh first." >&2
    exit 1
fi

for ext in "$@"; do
    echo "Installing PECL extension: $ext"
    pecl install "$ext" || true
    # Enable the extension
    PHP_EXT_DIR="$(php -i | grep '^extension_dir' | cut -d' ' -f3)"
    if [ -f "${PHP_EXT_DIR}/${ext}.so" ]; then
        echo "extension=${ext}.so" > "/etc/php/$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')/mods-available/${ext}.ini" 2>/dev/null || true
    fi
done

echo "PECL extensions installed. You may need to enable them in php.ini."
