#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# envfolio+seed and +agent: the selection reaches the run, a dry run makes no
# seed, and +agent mounts the host gpg-agent socket read-only
#
# The extension's params become -e CB_FOLIO_SEED / CB_FOLIO_SEED_MODE in
# run-args: the host side reads the selection from there before the container
# starts, and the startup hook reads both inside. A dry run only says what it
# would seed: it runs no folio and writes nothing into .booth/.tmp/.
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

OUT=$(dry 'envfolio+seed:"gh --use @app2/@prod --vars .booth/deploy.vars --secrets",fill')
if printf '%s\n' "$OUT" | grep -F -- "CB_FOLIO_SEED=gh --use @app2/@prod --vars .booth/deploy.vars --secrets" >/dev/null \
  && printf '%s\n' "$OUT" | grep -F -- "CB_FOLIO_SEED_MODE=fill" >/dev/null; then
  print_test_result "true"  "$0" "1" "the selection and the mode reach the run as CB_FOLIO_SEED / CB_FOLIO_SEED_MODE"
else
  print_test_result "false" "$0" "1" "the selection and the mode reach the run as CB_FOLIO_SEED / CB_FOLIO_SEED_MODE"
  printf '%s\n' "$OUT" | grep -i folio; exit 1
fi

if printf '%s\n' "$OUT" | grep -F "would seed the booth's EnvFolio store with: folio exec gh --use @app2/@prod" >/dev/null \
  && [[ -z "$(find "$PROJECT" -path '*folio-seed*' 2>/dev/null)" ]]; then
  print_test_result "true"  "$0" "2" "a dry run says what it would seed and writes no seed"
else
  print_test_result "false" "$0" "2" "a dry run says what it would seed and writes no seed"
  printf '%s\n' "$OUT" | grep -i folio; find "$PROJECT"; exit 1
fi

OUT=$(dry 'envfolio+seed')
if printf '%s\n' "$OUT" | grep -F -- "CB_FOLIO_SEED_MODE=seed" >/dev/null \
  && ! printf '%s\n' "$OUT" | grep -F "would seed" >/dev/null; then
  print_test_result "true"  "$0" "3" "no FOLIO_SEED: mode defaults to seed, and nothing is seeded"
else
  print_test_result "false" "$0" "3" "no FOLIO_SEED: mode defaults to seed, and nothing is seeded"
  printf '%s\n' "$OUT" | grep -i folio; exit 1
fi

# ---- envfolio+agent: the host agent's extra socket, read-only ----
RUNTIME="$PROJECT/runtime"
mkdir -p "$RUNTIME/gnupg"
: > "$RUNTIME/gnupg/S.gpg-agent.extra"   # the missing-mount filter only checks it exists

OUT=$(export XDG_RUNTIME_DIR="$RUNTIME"; dry 'envfolio+agent')
if printf '%s\n' "$OUT" | grep -F -- "$RUNTIME/gnupg/S.gpg-agent.extra:/run/cb-gpg-agent.sock:ro" >/dev/null \
  && printf '%s\n' "$OUT" | grep -F -- "CB_GPG_AGENT_SOCK=/run/cb-gpg-agent.sock" >/dev/null; then
  print_test_result "true"  "$0" "4" "+agent: the host agent's extra socket is mounted read-only, CB_GPG_AGENT_SOCK points at it"
else
  print_test_result "false" "$0" "4" "+agent: the host agent's extra socket is mounted read-only, CB_GPG_AGENT_SOCK points at it"
  printf '%s\n' "$OUT" | grep -i -E 'gpg|skipping'; exit 1
fi

OUT=$(unset XDG_RUNTIME_DIR; dry 'envfolio+agent')
if ! printf '%s\n' "$OUT" | grep -F -- ":/run/cb-gpg-agent.sock" >/dev/null \
  && printf '%s\n' "$OUT" | grep -F "Skipping volume mount: host path does not exist: /nonexistent/gnupg/S.gpg-agent.extra" >/dev/null; then
  print_test_result "true"  "$0" "5" "+agent with no XDG_RUNTIME_DIR: the mount is skipped with a notice"
else
  print_test_result "false" "$0" "5" "+agent with no XDG_RUNTIME_DIR: the mount is skipped with a notice"
  printf '%s\n' "$OUT" | grep -i -E 'gpg|skipping'; exit 1
fi
