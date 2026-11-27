#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# build/release-publish.sh — the release job's upload, which must survive GitHub's secondary rate
# limit (0.82.0 and both attempts of 0.83.0 died on it). gh is a stub that keeps the release in a
# temp dir and fails the calls it is told to; no network, no Docker.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PUBLISH="$SCRIPT_DIR/../../build/release-publish.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

failures=0
pass() { echo "✅ $1"; }
fail() { echo "❌ $1"; failures=$((failures + 1)); }
check() { # check <name> <expected> <actual>
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1"; echo "   expected: $2"; echo "   actual:   $3"; fi
}

# The stub. $STATE/exists = the release exists; $STATE/assets/<name> = an uploaded asset's sha256;
# $STATE/fail/<key> = how many more times that call fails (key: upload-<name>, or view).
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'EOF'
#!/usr/bin/env bash
echo "gh $*" >> "$STATE/calls.log"
fail_once() { # fail_once <key> <message>
  local f="$STATE/fail/$1" n
  [[ -f "$f" ]] || return 0
  n=$(cat "$f"); (( n > 0 )) || return 0
  echo $((n - 1)) > "$f"; echo "$2" >&2; exit 1
}
[[ "$1" == release ]] || exit 9
case "$2" in
  view)
    if [[ "$*" == *"--json assets"* ]]; then
      for a in "$STATE/assets"/*; do [[ -f "$a" ]] && printf '%s\tsha256:%s\n' "$(basename "$a")" "$(cat "$a")"; done
      exit 0
    fi
    fail_once view "HTTP 502: Bad Gateway"
    [[ -f "$STATE/exists" ]] || { echo "release not found" >&2; exit 1; }
    ;;
  create) touch "$STATE/exists" ;;
  edit)   [[ -f "$STATE/exists" ]] || exit 1 ;;
  upload)
    file="$4"; name="$(basename "$file")"
    fail_once "upload-$name" "HTTP 403: You have exceeded a secondary rate limit. Please wait a few minutes before you try again."
    sha256sum "$file" | cut -d' ' -f1 > "$STATE/assets/$name"
    ;;
  *) exit 9 ;;
esac
EOF
chmod +x "$TMP/bin/gh"

mkdir -p "$TMP/files"
echo "binary"   > "$TMP/files/codingbooth-linux-amd64"
echo "0.83.0"   > "$TMP/files/version.txt"
echo "zip"      > "$TMP/files/kind-example.zip"
echo "notes"    > "$TMP/notes.md"
FILES=("$TMP/files/codingbooth-linux-amd64" "$TMP/files/version.txt" "$TMP/files/kind-example.zip")

new_state() {
  export STATE="$TMP/state-$1"
  mkdir -p "$STATE/assets" "$STATE/fail"
  : > "$STATE/calls.log"
}
run() { # run <args>... — output in $OUT, exit code in $RC
  set +e
  OUT=$(PATH="$TMP/bin:$PATH" GH_REPO=o/r CB_RELEASE_RETRY_WAIT=0 CB_RELEASE_RETRIES=3 \
        "$PUBLISH" --title T --notes-file "$TMP/notes.md" "$@" 2>&1)
  RC=$?
  set -e
}
sha() { sha256sum "$1" | cut -d' ' -f1; }

# --- 1. No release yet: it is created at the target, marked latest, and every file goes up.
new_state create
run --tag 0.83.0 --latest --target abc123 "${FILES[@]}"
check "new release: exit 0" 0 "$RC"
check "new release: created at the target, marked latest" 1 \
  "$(grep -c '^gh release create 0.83.0 --title T --notes-file .* --target abc123 --latest=true$' "$STATE/calls.log")"
check "new release: not edited" 0 "$(grep -c '^gh release edit' "$STATE/calls.log")"
check "new release: one upload per file" 3 "$(grep -c '^gh release upload 0.83.0 .* --clobber$' "$STATE/calls.log")"
check "new release: all files on it" 3 "$(ls "$STATE/assets" | wc -l)"

# --- 2. An existing release (the rolling `latest`): updated, not marked latest; a file already
#        there with the same content is skipped, one with other content (last release's
#        version.txt, same name and size) is replaced.
new_state existing
touch "$STATE/exists"
sha "$TMP/files/codingbooth-linux-amd64" > "$STATE/assets/codingbooth-linux-amd64"
echo "0.82.0-sha" > "$STATE/assets/version.txt"
run --tag latest --not-latest --target abc123 "${FILES[@]}"
check "existing release: exit 0" 0 "$RC"
check "existing release: edited, not marked latest" 1 \
  "$(grep -c '^gh release edit latest --title T --notes-file .* --draft=false --prerelease=false --latest=false$' "$STATE/calls.log")"
check "existing release: not created again" 0 "$(grep -c '^gh release create' "$STATE/calls.log")"
check "existing release: the unchanged file is not uploaded" 0 \
  "$(grep -c 'upload latest .*/codingbooth-linux-amd64 ' "$STATE/calls.log")"
check "existing release: a changed file with the same name is replaced" "$(sha "$TMP/files/version.txt")" \
  "$(cat "$STATE/assets/version.txt")"
check "existing release: summary counts" 1 \
  "$(grep -c '^Release latest: 2 uploaded, 1 already there, 0 failed$' <<<"$OUT")"

# --- 3. A secondary rate limit on one upload: waited out, retried, and the release completes.
new_state ratelimit
echo 2 > "$STATE/fail/upload-kind-example.zip"
run --tag 0.83.0 "${FILES[@]}"
check "rate limit: exit 0" 0 "$RC"
check "rate limit: the file was tried three times" 3 "$(grep -c 'upload 0.83.0 .*/kind-example.zip' "$STATE/calls.log")"
check "rate limit: it got there" "$(sha "$TMP/files/kind-example.zip")" "$(cat "$STATE/assets/kind-example.zip" 2>/dev/null)"
check "rate limit: the log says it was a rate limit" 2 "$(grep -c 'uploading kind-example.zip: rate limited' <<<"$OUT")"
check "rate limit: no --latest flag unless asked" 0 "$(grep -c -- '--latest' "$STATE/calls.log")"

# --- 4. A file that never uploads: the others still go up, and the run fails naming it.
new_state giveup
echo 99 > "$STATE/fail/upload-version.txt"
run --tag 0.83.0 "${FILES[@]}"
check "give up: exit 1" 1 "$RC"
check "give up: stops after CB_RELEASE_RETRIES attempts" 3 "$(grep -c 'upload 0.83.0 .*/version.txt' "$STATE/calls.log")"
check "give up: the files after it still uploaded" 1 "$(ls "$STATE/assets" | grep -c kind-example.zip)"
check "give up: the error names the missing file" 1 "$(grep -c '::error::release 0.83.0 is missing: version.txt' <<<"$OUT")"

# --- 5. The re-run after 4: only the missing file is uploaded.
: > "$STATE/calls.log"; rm "$STATE/fail/upload-version.txt"
run --tag 0.83.0 "${FILES[@]}"
check "re-run: exit 0" 0 "$RC"
check "re-run: uploads only what is missing" "gh release upload 0.83.0 $TMP/files/version.txt --clobber" \
  "$(grep '^gh release upload' "$STATE/calls.log")"

# --- 6. A failed lookup is retried, not read as "no release" (which would create a second one).
new_state lookup
touch "$STATE/exists"; echo 1 > "$STATE/fail/view"
run --tag 0.83.0 "${FILES[@]}"
check "lookup: exit 0" 0 "$RC"
check "lookup: the existing release is edited, not created" "0 1" \
  "$(grep -c '^gh release create' "$STATE/calls.log") $(grep -c '^gh release edit' "$STATE/calls.log")"

# --- 7. Bad input stops before touching GitHub.
new_state badinput
run --tag 0.83.0 "$TMP/files/nope.zip"
check "bad input: exit 2" 2 "$RC"
check "bad input: no gh call" 0 "$(wc -l < "$STATE/calls.log")"

echo
if (( failures > 0 )); then echo "❌ $failures check(s) failed"; exit 1; fi
echo "✅ all checks passed"
