#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -euo pipefail

source ../common--source.sh

# A profile overlay's run-args are added to the base's, never substituted for them.
# Two layers claiming the same thing — one -e variable, one container mount target,
# one published port — used to be settled by whichever layer handled the flag
# (Docker kept the last -e, booth silently kept the first bind mount, a repeated -p
# published both). Booth now refuses, and names both entries.
#
# Only a later layer against an earlier one is a collision: repeats inside a single
# config, and everything when no profile is selected, behave exactly as before.
#
# All checks use --dryrun: the refusal happens before any container is started.
# See docs/BOOTH_PROFILES.md.

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

git init -q "$TMP"
mkdir -p "$TMP/.booth"

run() { run_coding_booth --variant base --dryrun --code "$TMP" "$@" 2>&1 || true; }
fail() { print_test_result "false" "$0" "$1" "$2"; echo "Actual:"; echo "$3"; exit 1; }

base() { printf 'variant = "base"\nrun-args = %s\n' "$1" > "$TMP/.booth/config.toml"; }
overlay() { printf 'run-args = %s\n' "$2" > "$TMP/.booth/$1--config.toml"; }

# ---- 1. Same -e variable, different value ----
base   '["-e", "LOG=info"]'
overlay dev '["-e", "LOG=debug"]'
OUT="$(run --profile dev)"
grep -q 'collides with an earlier layer' <<<"$OUT" || fail 1 "a repeated -e KEY is refused" "$OUT"
grep -q 'environment variable LOG'        <<<"$OUT" || fail 1 "the error names the variable" "$OUT"
grep -q 'earlier: -e LOG=info'            <<<"$OUT" || fail 1 "the error shows the earlier entry" "$OUT"
grep -q 'dev: -e LOG=debug'               <<<"$OUT" || fail 1 "the error shows the profile's entry, labelled with its name" "$OUT"
grep -q 'docs/BOOTH_PROFILES.md'          <<<"$OUT" || fail 1 "the error points at the docs" "$OUT"
grep -q 'BOOTH_HOST_PORT' <<<"$OUT" && fail 1 "a refused run must not print a docker command" "$OUT"
print_test_result "true" "$0" "1" "-e LOG=info in the base and -e LOG=debug in a profile is refused, naming both"

# ---- 2. Same container mount target ----
base   '["-v", "/etc:/cfg"]'
overlay dev '["-v", "/usr:/cfg"]'
OUT="$(run --profile dev)"
grep -q 'mount target /cfg' <<<"$OUT" || fail 2 "a second mount on one target is refused, not silently dropped" "$OUT"
print_test_result "true" "$0" "2" "a base mount and a profile mount on one target is refused"

# ---- 3. A profile 'moving' a port would really publish both ----
base   '["-p", "39200:80"]'
overlay dev '["-p", "39300:80"]'
OUT="$(run --profile dev)"
grep -q 'container port 80/tcp' <<<"$OUT" || fail 3 "the same container port on another host port is refused" "$OUT"
print_test_result "true" "$0" "3" "-p 39200:80 then -p 39300:80 is refused"

# ---- 4. Same host port, different container port ----
overlay dev '["-p", "39200:81"]'
OUT="$(run --profile dev)"
grep -q 'host port 39200/tcp' <<<"$OUT" || fail 4 "a host port claimed twice is refused" "$OUT"
print_test_result "true" "$0" "4" "-p 39200:80 then -p 39200:81 is refused"

# ---- 5. Distinct claims and exact repeats pass, and are combined ----
base   '["-e", "TZ=UTC", "-v", "/etc:/cfg", "-p", "39200:80"]'
overlay dev '["-e", "LOG=debug", "-v", "/usr:/data", "-p", "39300:81", "-e", "TZ=UTC"]'
OUT="$(run --profile dev)"
grep -q 'collides' <<<"$OUT" && fail 5 "distinct claims and an exact repeat must be accepted" "$OUT"
grep -q "LOG=debug" <<<"$OUT" || fail 5 "the overlay's entries reach docker" "$OUT"
grep -q ':/cfg'     <<<"$OUT" || fail 5 "the base's entries are kept" "$OUT"
print_test_result "true" "$0" "5" "non-colliding entries are accepted and combined; an exact repeat is fine"

# ---- 6. Two profiles collide with each other, not just with the base ----
base   '["-e", "TZ=UTC"]'
overlay a '["-e", "LOG=debug"]'
overlay b '["-e", "LOG=trace"]'
OUT="$(run --profile a,b)"
grep -q 'profile "b"'          <<<"$OUT" || fail 6 "the later profile is the one blamed" "$OUT"
grep -q 'earlier: -e LOG=debug' <<<"$OUT" || fail 6 "the earlier profile's entry is shown" "$OUT"
print_test_result "true" "$0" "6" "--profile a,b: b colliding with a is refused"
OUT="$(run --profile a)"
grep -q 'collides' <<<"$OUT" && fail 6 "a alone does not collide with anything" "$OUT"
print_test_result "true" "$0" "6" "each of those profiles is fine on its own"

# ---- 7. Only the selected profiles are checked ----
base   '["-e", "LOG=info"]'
overlay dev '["-e", "LOG=debug"]'
overlay other '["-e", "SOMETHING=else"]'
OUT="$(run --profile other)"
grep -q 'collides' <<<"$OUT" && fail 7 "an unselected profile must not be checked" "$OUT"
print_test_result "true" "$0" "7" "a colliding profile that is not selected is not checked"

# ---- 8. No profile selected: nothing changes, even for a repeat within the base ----
base   '["-e", "LOG=info", "-e", "LOG=debug", "-v", "/etc:/cfg", "-v", "/usr:/cfg"]'
rm -f "$TMP/.booth/"*--config.toml
OUT="$(run)"
grep -q 'collides' <<<"$OUT" && fail 8 "without a profile there is no layer to collide with" "$OUT"
grep -q 'LOG=' <<<"$OUT" || fail 8 "the run still produces a docker command" "$OUT"
print_test_result "true" "$0" "8" "without --profile a repeat inside the base is left alone, as before"

# ---- 9. Scalars override; that is the point of an overlay, not a collision ----
printf 'variant = "base"\nport = "9000"\n' > "$TMP/.booth/config.toml"
printf 'port = "9100"\n' > "$TMP/.booth/dev--config.toml"
OUT="$(run --profile dev)"
grep -q 'collides' <<<"$OUT" && fail 9 "overriding a scalar is not a collision" "$OUT"
grep -q 'BOOTH_HOST_PORT=9100' <<<"$OUT" || fail 9 "the overlay's scalar wins" "$OUT"
print_test_result "true" "$0" "9" "a profile overriding a scalar is not a collision"
