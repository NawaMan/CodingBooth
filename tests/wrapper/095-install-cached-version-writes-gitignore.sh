#!/usr/bin/env bash
# 095 — installing a pinned version that is already in the shared cache still
#       writes .booth/.gitignore. DownloadBooth's already-cached early return
#       used to sit above the heredoc, so a fresh project got the lock but no
#       .gitignore — leaving .booth/cache/ (live credentials) unignored until
#       the first `booth config`.
source "$(dirname "$0")/_lib.sh"

LAST_OUTPUT=$(run_in_container <<'BASH'
mkdir first && cd first
cp /booth/booth ./booth
./booth install >/dev/null
version=$(grep '^version=' .booth/tools/codingbooth.lock | cut -d= -f2)
cd ..

mkdir second && cd second
cp /booth/booth ./booth
echo "=== PINNED INSTALL ==="
./booth install "$version" 2>&1
echo "exit=$?"
echo "=== FILES ==="
[[ -f .booth/tools/codingbooth.lock ]] && echo "lock=present" || echo "lock=missing"
[[ -f .booth/.gitignore ]] && echo "gitignore=present" || echo "gitignore=missing"
cmp -s .booth/.gitignore ../first/.booth/.gitignore && echo "gitignore=same" || echo "gitignore=differs"
BASH
)

install="${LAST_OUTPUT#*=== PINNED INSTALL ===}"; install="${install%%=== FILES*}"
# The early return is the path under test — without it this proves nothing.
assert_contains "$install" "is already up-to-date"
assert_contains "$install" "exit=0"

files="${LAST_OUTPUT##*=== FILES ===}"
assert_contains "$files" "lock=present"
assert_contains "$files" "gitignore=present"
assert_contains "$files" "gitignore=same"
pass
