#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -euo pipefail

source ../common--source.sh

# A profile env file (.booth/.<name>--env) holds per-environment secrets, so it
# gets the same guard as the base .booth/.env: booth refuses to run when git
# would commit it. The guard used to cover only the base file, so a profile env
# file slipped through whenever the base .env was ignored — or absent.
#
# All checks use --dryrun: the refusal happens before any container is started.
# See docs/BOOTH_PROFILES.md.

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

git init -q "$TMP"
mkdir -p "$TMP/.booth"
printf 'variant = "base"\n' > "$TMP/.booth/config.toml"
printf 'TOKEN=secret\n'     > "$TMP/.booth/.prod--env"

run() { run_coding_booth --variant base --dryrun --code "$TMP" "$@" 2>&1 || true; }
fail() { print_test_result "false" "$0" "$1" "$2"; echo "Actual:"; echo "$3"; exit 1; }

# ---- 1. No .gitignore at all: refused, and the hint names the right pattern ----
OUT="$(run --profile prod)"
grep -q 'NOT gitignored' <<<"$OUT" || fail 1 "an un-ignored profile env file is refused" "$OUT"
grep -q "Add '.\*--env'" <<<"$OUT"  || fail 1 "the refusal suggests the .*--env pattern" "$OUT"
grep -q -- '--env-file'  <<<"$OUT" && fail 1 "a refused profile env file is not handed to docker" "$OUT"
print_test_result "true" "$0" "1" "an un-ignored .prod--env is refused, with the .*--env hint"

# ---- 2. The old hole: base .env ignored, profile env file is not ----
printf '.env\n' > "$TMP/.booth/.gitignore"
OUT="$(run --profile prod)"
grep -q 'NOT gitignored' <<<"$OUT" || fail 2 "ignoring only the base .env must not cover a profile file" "$OUT"
print_test_result "true" "$0" "2" "ignoring the base .env does not excuse .prod--env"

# ---- 3. Ignored via .*--env: accepted and passed to docker ----
printf '.env\n.*--env\n' > "$TMP/.booth/.gitignore"
OUT="$(run --profile prod)"
grep -q 'NOT gitignored' <<<"$OUT" && fail 3 "an ignored profile env file must be accepted" "$OUT"
grep -q -- '--env-file.*\.prod--env' <<<"$OUT" || fail 3 "the profile env file reaches docker as --env-file" "$OUT"
print_test_result "true" "$0" "3" "a .prod--env covered by .*--env is accepted and passed on"

# ---- 4. Only the selected profile's file matters ----
printf 'TOKEN=other\n' > "$TMP/.booth/.staging--env"     # not ignored by...
printf '.env\n.prod--env\n' > "$TMP/.booth/.gitignore"   # ...this narrower list
OUT="$(run --profile prod)"
grep -q 'NOT gitignored' <<<"$OUT" && fail 4 "an unselected profile's env file must not be checked" "$OUT"
print_test_result "true" "$0" "4" "an unselected profile's env file is not checked"
OUT="$(run --profile staging)"
grep -q 'NOT gitignored' <<<"$OUT" || fail 4 "the selected profile's own file is checked" "$OUT"
print_test_result "true" "$0" "4" "selecting the un-ignored profile is refused"

# ---- 5. The old .env--<name> shape is no longer a profile ----
printf '.env\n.*--env\n' > "$TMP/.booth/.gitignore"
printf 'A=1\n' > "$TMP/.booth/.env--legacy"
OUT="$(run --profile legacy)"
grep -q 'not found under .booth/' <<<"$OUT" || fail 5 ".env--<name> is not discovered any more" "$OUT"
grep -q '\.legacy--env' <<<"$OUT"           || fail 5 "the not-found error names the .<name>--env shape" "$OUT"
print_test_result "true" "$0" "5" ".env--legacy is not a profile; the error names .legacy--env"
