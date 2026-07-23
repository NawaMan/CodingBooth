#!/bin/bash
# Drive the same Playwright task from five languages: each opens its language's own
# official page on the shared pinned browser, saves a screenshot to shots/, and prints
# "TITLE|SUM" (TITLE = the live page's title, SUM = 1+2+...+10 run inside the browser).
# A language passes when it prints a "...|55" line AND leaves a non-empty screenshot.
#
# The four official bindings (JS, Python, Java, .NET) are pinned to Playwright 1.58 and
# reuse the Chromium pre-baked into the image. The Go binding pins its own driver, so it
# fetches its own browser on first run.
set -uo pipefail
cd "$(dirname "$0")"

SHOT_DIR="$(pwd)/shots"
mkdir -p "$SHOT_DIR"
rm -f "$SHOT_DIR"/*.png

declare -A RESULT

check() {
    local lang="$1"; local slug="$2"; local url="$3"; local cmd="$4"
    echo ""
    echo "=================================================="
    echo ">>> $lang  ($url)"
    echo "=================================================="
    export PAGE_URL="$url"
    export SHOT_PATH="$SHOT_DIR/$slug.png"

    local out rc line
    out=$(bash -c "$cmd" 2>&1); rc=$?
    line=$(printf '%s\n' "$out" | grep -E '\|[0-9]+$' | tail -1)

    if [ "$rc" -eq 0 ] && [[ "$line" == *"|55" ]] && [ -s "$SHOT_PATH" ]; then
        RESULT[$lang]="PASS   \"${line%|55}\"   [shots/$slug.png, $(stat -c%s "$SHOT_PATH") bytes]"
        echo "  -> $line"
        echo "  -> screenshot: shots/$slug.png"
    else
        local why="${line:-<no TITLE|SUM output>}"
        [ -s "$SHOT_PATH" ] || why="$why [no screenshot]"
        RESULT[$lang]="FAIL   (rc=$rc) $why"
        printf '%s\n' "$out" | tail -12
    fi
}

check "JavaScript" "javascript" "https://developer.mozilla.org/en-US/docs/Web/JavaScript" '
    cd js
    [ -d node_modules ] || npm install --silent
    node check.js
'

check "Python" "python" "https://www.python.org/" '
    cd python
    python check.py
'

check "Java" "java" "https://www.java.com/en/" '
    cd java
    mvn -q compile
    mvn -q exec:java
'

check "C#" "csharp" "https://dotnet.microsoft.com/en-us/languages/csharp" '
    cd csharp
    dotnet run --verbosity quiet
'

check "Go" "go" "https://go.dev/" '
    cd go
    # The official bindings share the pre-baked browser in the read-only
    # /opt/ms-playwright. Go pins its own driver version and installs its own
    # browser, so give it a writable path of its own.
    export PLAYWRIGHT_BROWSERS_PATH="$HOME/.cache/ms-playwright-go"
    go mod tidy
    go run check.go
'

echo ""
echo "==================== SUMMARY ===================="
fail=0
for l in JavaScript Python Java "C#" Go; do
    r="${RESULT[$l]:-? not run}"
    printf '  %-12s %s\n' "$l" "$r"
    [[ "$r" == PASS* ]] || fail=1
done
echo "================================================="
echo "Screenshots (one real page per language):"
ls -1 "$SHOT_DIR"/*.png 2>/dev/null | sed 's#.*/#  shots/#' || echo "  (none)"
exit "$fail"
