#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: lsp+haskell and lsp+zig serve a real editor.
#
# A binary on PATH proves little: HLS has to find the GHC it was built for and
# zls the Zig X.Y it was released for. Neovim, through neovim+lsp, attaches each
# server to a sample file and asks it to hover over `greet`; the answer has to be
# the function's type, which only a server that compiled the file can give.
# hover.lua is the client; the samples are Main.hs and main.zig.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../../common--source.sh

echo "=== Test: Boothfile lsp+haskell / lsp+zig ==="

FAILED=0

ACTUAL=$(capture_codingbooth "tail -1" --silence-build -- 'command -v haskell-language-server-wrapper && command -v zls')
if [[ "$ACTUAL" == */zls ]]; then
    print_test_result "true" "$0" "1" "haskell-language-server-wrapper and zls are on a non-login PATH"
else
    print_test_result "false" "$0" "1" "haskell-language-server-wrapper and zls should be on PATH"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

hover() {
    capture_codingbooth "tail -1" --silence-build -- \
        "nvim --headless $1 -c 'lua HOVER_AT={$2,$3}' -c 'luafile hover.lua' 2>&1"
}

ACTUAL=$(hover main.zig 7 4)
if [[ "$ACTUAL" == "zls: fn greet(name: []const u8) void"* ]]; then
    print_test_result "true" "$0" "2" "zls answers hover with greet's type"
else
    print_test_result "false" "$0" "2" "zls should answer hover with greet's type"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

ACTUAL=$(hover Main.hs 6 18)
if [[ "$ACTUAL" == "hls: greet :: String -> Int -> String"* ]]; then
    print_test_result "true" "$0" "3" "HLS answers hover with greet's type"
else
    print_test_result "false" "$0" "3" "HLS should answer hover with greet's type"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
