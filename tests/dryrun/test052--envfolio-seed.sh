#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# envfolio+seed: the selection reaches the run, and a dry run makes no seed
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

# The store key comes with every seed now: there is no +key to ask for it, and no flag for it.
OUT=$(dry 'envfolio+seed:"--secrets gh"')
if ! printf '%s\n' "$OUT" | grep -F -- "CB_FOLIO_SEED_KEY" >/dev/null \
  && dry 'envfolio+seed:"--secrets gh"+key' | grep -F 'unknown extension "key"' >/dev/null; then
  print_test_result "true"  "$0" "4" "the store key needs no +key: no CB_FOLIO_SEED_KEY, and envfolio+key is gone"
else
  print_test_result "false" "$0" "4" "the store key needs no +key: no CB_FOLIO_SEED_KEY, and envfolio+key is gone"
  printf '%s\n' "$OUT" | grep -i folio; exit 1
fi
