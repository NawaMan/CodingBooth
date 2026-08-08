#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Lombok support for the JetBrains IDEs — the counterpart to lombok-eclipse--setup.sh,
# which does the same job for Eclipse.
#
# Usage: lombok-idea--setup.sh
#
# IntelliJ IDEA Community does not bundle the Lombok plugin (checked on 2025.2.3: it is
# absent from /opt/idea/plugins), so without this the IDE flags every getter that
# @Value or @Data generates as an unresolved symbol, in a project that compiles fine.
#
# ---- Why this exists rather than just naming the id ----
# It is a thin wrapper over `install jetbrains-plugin`, and the point of it is the name.
# Lombok's marketplace xmlId is "Lombook Plugin" — two words, JetBrains' own typo — and a
# Boothfile expands `install jetbrains-plugin ${JETBRAINS_PLUGIN_PKGS}` unquoted, so the
# only form that survives the trip through a template param is the numeric id, 6317. A
# Boothfile line reading `arg JETBRAINS_PLUGIN_PKGS=6317` tells its reader nothing.
# `setup lombok-idea`, sitting next to `setup lombok-eclipse`, tells them everything.
#
# The escape hatch is still there for anything without a curated script of its own:
# `install jetbrains-plugin <id>` takes whatever you name.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

if [ "$EUID" -ne 0 ]; then
    echo "❌ This script must be run as root (use sudo)" >&2
    exit 1
fi

case "${1:-}" in
    -h|--help)
        echo "Usage: $0"
        echo "Installs the Lombok plugin into every JetBrains IDE in the image."
        exit 0
        ;;
esac

# This script always runs as root during the build.
HOME=/root

SCRIPT_DIR="$(dirname "$0")"

# Passed as a single argument, so the installer receives the xmlId intact — it splits
# comma lists but leaves an argument that already arrived whole alone. No IDE in the
# image is a skip, handled there.
"${SCRIPT_DIR}/jetbrains-plugin--install.sh" "Lombook Plugin"
