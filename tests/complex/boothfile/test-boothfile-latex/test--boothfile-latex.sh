#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile LaTeX Installation
#
# Verifies that `booth config --select latex+texstudio` (scheme `recommended`)
# produces a booth that turns a .tex file into a PDF with latexmk -- not merely
# that pdflatex is on PATH -- and that the desktop-only pieces skip cleanly on the
# base variant instead of failing the build.
#
# .booth/ is `booth config` output; only .booth/setups/ is hand-placed. It holds
# copies of latex--setup.sh, latex-code-extension--setup.sh and texstudio--setup.sh,
# byte-identical to variants/base/setups/, until the base image ships them -- plus
# the helpers those scripts reach via $SCRIPT_DIR (cb-has-vscode.sh,
# cb-has-desktop.sh, libs/skip-setup.sh), which the released image has only in
# /opt/codingbooth/setups/ and so are not siblings of the override copies. The base
# variant has neither an editor nor a desktop, so a successful build also proves
# both guarded setups skip rather than fail.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../../common--source.sh

echo "=== Test: Boothfile LaTeX Installation ==="

FAILED=0

# Test 1: latexmk builds a PDF from a document that uses packages from the
# recommended scheme (geometry, hyperref, booktabs), which `basic` lacks.
# Heredoc avoids quote-mangling when the command round-trips through
# codingbooth's COMMAND mode (argv -> joined string -> re-parsed by bash -c).
BUILD_PDF_SCRIPT='
mkdir -p /tmp/doc && cd /tmp/doc
cat > main.tex <<EEE
\documentclass{article}
\usepackage[margin=1in]{geometry}
\usepackage{booktabs}
\usepackage{hyperref}
\begin{document}
Hello from CodingBooth.
\begin{tabular}{ll}\toprule a & b \\\\ \bottomrule\end{tabular}
\end{document}
EEE
latexmk -pdf -interaction=nonstopmode -halt-on-error main.tex >/dev/null 2>&1 || { tail -20 main.log; exit 1; }
head -c 5 main.pdf; echo
'
ACTUAL=$(run_coding_booth --silence-build -- bash -c "$BUILD_PDF_SCRIPT" 2>/dev/null | tail -1) || ACTUAL=""
if [[ "$ACTUAL" == "%PDF-" ]]; then
    print_test_result "true" "$0" "1" "latexmk builds a PDF (geometry, booktabs, hyperref)"
else
    print_test_result "false" "$0" "1" "latexmk should build a PDF (geometry, booktabs, hyperref)"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 2: TeXstudio is desktop-only -- on the base variant it is skipped, not installed.
# Multi-line script, like Test 1: a one-line `bash -c '...'` is split apart by
# COMMAND mode's re-parse, and `bash -c command` then prints nothing at all.
TEXSTUDIO_ABSENT_SCRIPT='
command -v texstudio || echo absent
'
ACTUAL=$(run_coding_booth --silence-build -- bash -c "$TEXSTUDIO_ABSENT_SCRIPT" 2>/dev/null | tail -1) || ACTUAL=""
if [[ "$ACTUAL" == "absent" ]]; then
    print_test_result "true" "$0" "2" "texstudio skips itself on the base variant"
else
    print_test_result "false" "$0" "2" "texstudio should skip itself on the base variant"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
