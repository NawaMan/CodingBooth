#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: XFCE window edges widened by xfce+modern-theme:8
#
# xfwm4 resizes only from the border its theme draws, so the edge width is the
# grab width. xfce-theme--setup.sh --border 8 should build Greybird-dark-wide
# with 8 px left/right/bottom edges and corners, keep every XPM's declared size
# equal to its pixel rows (xfwm4 rejects a theme piece that disagrees), and make
# it the system default window theme.
#
# A drag on the running desktop needs the desktop up, which a command-mode
# booth does not start; that was checked by hand (every pixel of a 6 px edge
# resizes, 7 px out does not).
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../../common--source.sh

echo "=== Test: XFCE window edges at 8 px ==="

FAILED=0

check() {   # <n> <message> <command> <expected>
    local actual
    actual=$(run_coding_booth --silence-build -- "$3" 2>/dev/null) || actual=""
    actual=$(printf '%s\n' "$actual" | tail -1)
    if [[ "$actual" == "$4" ]]; then
        print_test_result "true" "$0" "$1" "$2"
    else
        print_test_result "false" "$0" "$1" "$2"
        echo "  Expected: $4"
        echo "  Actual:   ${actual:-<empty>}"
        FAILED=$((FAILED + 1))
    fi
}

XFWM4=/usr/share/themes/Greybird-dark-wide/xfwm4

check 1 "Greybird-dark-wide is the default window theme" \
    "grep -o 'name=\"theme\" type=\"string\" value=\"[^\"]*\"' /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml" \
    'name="theme" type="string" value="Greybird-dark-wide"'

# Width x height of each edge piece: the left/right edges and the bottom
# corners grow to 8 px, the bottom to 8 rows, the top corners by 5 columns.
check 2 "edges and corners are 8 px" \
    "cd $XFWM4 && for f in left right bottom bottom-left bottom-right top-left top-right; do grep -m1 '^\"' \$f-active.xpm | cut -d' ' -f1,2 | tr -d '\"'; done | paste -sd' '" \
    "8 1 8 1 1 8 8 8 8 8 13 34 13 34"

# Every piece, active and inactive, has as many rows as it declares, each as
# wide as it declares.
check 3 "every XPM matches its declared size" \
    "cd $XFWM4 && for f in *.xpm; do awk '/^\"/ && !h { h = 1; split(substr(\$0, 2), d, \" \"); n = d[3]; next }
         /^\"/ && n > 0 { n--; next }
         /^\"/ { r++; match(\$0, /^\"[^\"]*\"/); if (RLENGTH - 2 != d[1]) bad = 1 }
         END { if (bad || r != d[2]) print FILENAME }' \$f; done | wc -l" \
    "0"

exit $FAILED
