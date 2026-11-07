#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# envfolio+store-host and gnupg+keys: what the run would be, with no container
#
# store-host mounts the host's folio store and gpg home live (~ expanded only at
# the start), adds a tmpfs at /run/user/<uid> for the booth gpg-agent's sockets,
# warns on every start, and refuses +store-cache, +seed and gnupg+keys. A dry
# run skips the check that the host folders exist (CI has neither), but still
# refuses a combination. gnupg+keys passes the key names to the run; a dry run
# only says what it would bring, and a name that looks like a gpg option is
# refused before gpg could see it.
# -----------------------------------------------------------------------------

set -euo pipefail

source ../common--source.sh

strip_ansi() { sed -r 's/\x1B\[[0-9;]*[A-Za-z]//g'; }

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PROJECT="$(mktemp -d)"
trap 'rm -rf "$PROJECT"' EXIT

dry() {
  run_coding_booth express --dryrun --code "$PROJECT" --templates-path "$REPO/templates" \
    --select "$1" -- true 2>&1 | strip_ansi || true
}

result() { # result <ok> <n> <desc> [<output to show on failure>]
  print_test_result "$1" "$0" "$2" "$3"
  if [[ "$1" != "true" ]]; then printf '%s\n' "${4:-}" | grep -i -E 'folio|gnupg|run/user|error' | head -20; exit 1; fi
}

OUT=$(dry 'envfolio+store-host')
ok=false
printf '%s\n' "$OUT" | grep -F -- "-v $HOME/.folio:/home/coder/.folio" >/dev/null \
  && printf '%s\n' "$OUT" | grep -F -- "-v $HOME/.gnupg:/home/coder/.gnupg" >/dev/null \
  && ok=true
result "$ok" 1 "store-host mounts the host store and gpg home, ~ expanded at the start" "$OUT"

ok=false
printf '%s\n' "$OUT" | grep -F -- "--tmpfs '/run/user/$(id -u):uid=$(id -u),gid=$(id -g),mode=0700'" >/dev/null && ok=true
result "$ok" 2 "store-host gives gpg-agent its own /run/user/<uid> tmpfs, out of the shared gpg home" "$OUT"

ok=false
printf '%s\n' "$OUT" | grep -F "Warning: envfolio+store-host: the host's EnvFolio store" >/dev/null && ok=true
result "$ok" 3 "store-host warns that the host's store and keys are live in the booth" "$OUT"

ok=true
for combo in 'envfolio+store-host+store-cache:envfolio+store-cache' \
             'envfolio+store-host+seed:"--secrets gh":envfolio+seed'; do
  sel="${combo%:*}" want="${combo##*:}"
  out=$(dry "$sel")
  printf '%s\n' "$out" | grep -F "envfolio+store-host: cannot be used with $want" >/dev/null || { ok=false; OUT="$out"; }
done
out=$(dry 'envfolio+store-host/gnupg+keys:"me@example.com"')
printf '%s\n' "$out" | grep -F "envfolio+store-host: cannot be used with gnupg+keys" >/dev/null || { ok=false; OUT="$out"; }
result "$ok" 4 "store-host refuses +store-cache, +seed and gnupg+keys, naming the other one" "$OUT"

OUT=$(dry 'gnupg+keys:"me@example.com 0xABCDEF12"')
ok=false
printf '%s\n' "$OUT" | grep -F -- "CB_GNUPG_KEYS=me@example.com 0xABCDEF12" >/dev/null \
  && printf '%s\n' "$OUT" | grep -F "would bring the host's GnuPG key(s) me@example.com, 0xABCDEF12" >/dev/null \
  && [[ -z "$(find "$PROJECT" -path '*gnupg-keys*' 2>/dev/null)" ]] \
  && ok=true
result "$ok" 5 "gnupg+keys passes the key names to the run; a dry run says what it would bring and copies nothing" "$OUT"

OUT=$(dry 'gnupg+keys:"--export-secret-keys"')
ok=false
printf '%s\n' "$OUT" | grep -F 'gnupg keys: "--export-secret-keys" is not a key id' >/dev/null && ok=true
result "$ok" 6 "a key name that looks like a gpg option is refused" "$OUT"

OUT=$(dry 'gnupg')
ok=false
! printf '%s\n' "$OUT" | grep -F "CB_GNUPG_KEYS" >/dev/null && ok=true
result "$ok" 7 "gnupg alone brings nothing" "$OUT"
