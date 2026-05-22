#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# End-to-end test for BOOTH_PROFILES — see docs/BOOTH_PROFILES.md.
#
# Verifies:
#   1) No --profile / no env / no default-profile file → base config only
#   2) Implicit "default" profile applies when default--config.toml exists
#   3) --profile dev overrides base; default is NOT applied
#   4) --profile dev,deploy → later profile wins (cmds), env files stack
#   5) BOOTH_PROFILES=dev works the same as --profile dev
#   6) --profile beats BOOTH_PROFILES (env ignored, no merge across sources)
#   7) Reserved name --profile common → error
#   8) Unknown profile name → error
#   9) --profile combined with --config → error (mutual exclusion)
#  10) --profile combined with --env-file → error (mutual exclusion)
#  11) BOOTH_PROFILES combined with --config → error
#  12) Per-profile .env--<name> values reach the container
#
# Error-path checks (7-11) use --dryrun so docker is never invoked.

set -euo pipefail

source ../../common--source.sh

# ---- Config -------------------------------------------------------------------
CB_SCRIPT="${CB_SCRIPT:-../../../codingbooth}"
if command -v readlink >/dev/null 2>&1; then
  CB_SCRIPT="$(readlink -f "$CB_SCRIPT")"
else
  CB_SCRIPT="$(cd "$(dirname "$CB_SCRIPT")" && pwd -P)/$(basename "$CB_SCRIPT")"
fi

# ---- Preconditions ------------------------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker not found in PATH" >&2
  exit 1
fi

if [[ ! -x "$CB_SCRIPT" ]]; then
  echo "ERROR: CB_SCRIPT not executable or not found: $CB_SCRIPT" >&2
  exit 1
fi

# ---- Test workspace -----------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMPDIR="$(mktemp -d "${SCRIPT_DIR}/.cb-test-profile.XXXXXX")"
CONTAINER_NAME_BASE="cb-profile-$$-$RANDOM"

cleanup() {
  # Remove any containers spawned by this run (one per scenario)
  for c in $(docker ps -aq --filter "name=${CONTAINER_NAME_BASE}-" 2>/dev/null); do
    docker rm -f "$c" >/dev/null 2>&1 || true
  done
  rm -rf "$TMPDIR" || true
}
trap cleanup EXIT

# Initialize a git repo so the gitignore check on .env / .env--* passes
git init "$TMPDIR" >/dev/null 2>&1

mkdir -p "$TMPDIR/.booth"

# All profile env files (and base .env, if present) must be gitignored.
cat > "$TMPDIR/.booth/.gitignore" <<'EOF'
.booth.password
.env
.env--*
EOF

# Base — common to every run.
cat > "$TMPDIR/.booth/config.toml" <<'EOF'
variant = "base"
cmds = ["echo", "FROM_BASE"]
EOF

# Implicit "default" profile — applies when no --profile / BOOTH_PROFILES is set.
cat > "$TMPDIR/.booth/default--config.toml" <<'EOF'
cmds = ["echo", "FROM_DEFAULT"]
EOF

# "dev" profile — config + env.
#
# Notes on the cmds form:
#   - booth flattens cmds into one string and wraps as `bash -lc "<joined>"`
#     (booth.go:76), so quoting inside cmds tokens is lost. Pack the whole
#     command into ONE TOML element to keep it intact under that join.
#   - TOML literal strings ('...') preserve content verbatim — no TOML escapes.
#   - The \$PROFILE_KEY is shellexpand's escape (docs/BOOTH_VARS.md): booth
#     emits a literal $PROFILE_KEY into the cmd, deferring expansion to the
#     container's bash where .env--dev has set the value.
cat > "$TMPDIR/.booth/dev--config.toml" <<'EOF'
cmds = ['echo FROM_DEV: \$PROFILE_KEY']
EOF
cat > "$TMPDIR/.booth/.env--dev" <<'EOF'
PROFILE_KEY=dev-value
EOF

# "deploy" profile — config + env. Used to verify later-wins semantics.
cat > "$TMPDIR/.booth/deploy--config.toml" <<'EOF'
cmds = ['echo FROM_DEPLOY: \$PROFILE_KEY']
EOF
cat > "$TMPDIR/.booth/.env--deploy" <<'EOF'
PROFILE_KEY=deploy-value
EOF

# Spare config to point --config at for mutual-exclusion checks.
cat > "$TMPDIR/.booth/alt-config.toml" <<'EOF'
cmds = ["echo", "FROM_ALT"]
EOF

# ---- Helpers -----------------------------------------------------------------

# Run codingbooth from the tmpdir.
run_cb() {
  local scenario_id="$1"; shift
  pushd "$TMPDIR" >/dev/null
  local cname="${CONTAINER_NAME_BASE}-${scenario_id}"
  echo -e "${COLOR_BOOTH:-}> codingbooth --name $cname $*${COLOR_RESET:-}" >&2
  "$CB_SCRIPT" --name "$cname" --version latest "$@"
  local rc=$?
  popd >/dev/null
  return $rc
}

# Run codingbooth and expect failure. Captures combined output for inspection.
run_cb_expect_fail() {
  local scenario_id="$1"; shift
  pushd "$TMPDIR" >/dev/null
  local cname="${CONTAINER_NAME_BASE}-${scenario_id}"
  echo -e "${COLOR_BOOTH:-}> codingbooth --name $cname $* (expect failure)${COLOR_RESET:-}" >&2
  local out
  out=$("$CB_SCRIPT" --name "$cname" --version latest "$@" 2>&1) && {
    popd >/dev/null
    printf '%s\n' "$out"
    return 0  # unexpected success — caller checks rc
  }
  popd >/dev/null
  printf '%s\n' "$out"
  return 1  # expected: command failed
}

# ---- Assertions --------------------------------------------------------------
total_checks=0
failed_checks=0
failed_msgs=()

pass() {
  total_checks=$((total_checks + 1))
  print_test_result "true" "$0" "$total_checks" "$*"
}

fail() {
  total_checks=$((total_checks + 1))
  failed_checks=$((failed_checks + 1))
  failed_msgs+=("$*")
  print_test_result "false" "$0" "$total_checks" "$*"
}

assert_contains() {
  local needle="$1"
  local haystack="$2"
  local msg="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    pass "$msg"
  else
    fail "$msg (expected to contain '$needle', got: '$haystack')"
  fi
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local msg="$3"
  if [[ "$actual" == "$expected" ]]; then
    pass "$msg"
  else
    fail "$msg (expected '$expected', got '$actual')"
  fi
}

# ---- Tests -------------------------------------------------------------------

# Test 1: Implicit "default" profile applies when no --profile is set.
# (default--config.toml exists, so the default profile kicks in.)
out="$(run_cb t1 2>/dev/null | tr -d '\r\n')"
assert_eq "FROM_DEFAULT" "$out" "implicit default profile applies when present and no --profile"

# Test 2: --profile dev overrides default; default is NOT applied.
out="$(run_cb t2 --profile dev 2>/dev/null | tr -d '\r\n')"
assert_eq "FROM_DEV: dev-value" "$out" "--profile dev overrides default; .env--dev visible"

# Test 3: --profile dev,deploy → later wins for scalars, env layers (deploy wins).
out="$(run_cb t3 --profile dev,deploy 2>/dev/null | tr -d '\r\n')"
assert_eq "FROM_DEPLOY: deploy-value" "$out" "later profile wins; cmds and .env layered correctly"

# Test 4: --profile repeated flag form is equivalent to comma-separated.
out="$(run_cb t4 --profile dev --profile deploy 2>/dev/null | tr -d '\r\n')"
assert_eq "FROM_DEPLOY: deploy-value" "$out" "--profile repeated form equivalent to comma-separated"

# Test 5: BOOTH_PROFILES env var works.
out="$(BOOTH_PROFILES=dev run_cb t5 2>/dev/null | tr -d '\r\n')"
assert_eq "FROM_DEV: dev-value" "$out" "BOOTH_PROFILES env var selects the profile"

# Test 6: --profile beats BOOTH_PROFILES (no merging across sources).
out="$(BOOTH_PROFILES=deploy run_cb t6 --profile dev 2>/dev/null | tr -d '\r\n')"
assert_eq "FROM_DEV: dev-value" "$out" "--profile fully overrides BOOTH_PROFILES (env ignored)"

# Test 7 (error path, --dryrun): reserved name --profile common.
out="$(run_cb_expect_fail t7 --dryrun --profile common 2>&1 || true)"
assert_contains "reserved" "$out" "--profile common is rejected with a 'reserved' message"

# Test 8 (error path, --dryrun): unknown profile name.
out="$(run_cb_expect_fail t8 --dryrun --profile ghost 2>&1 || true)"
assert_contains "not found" "$out" "unknown --profile name is rejected with a 'not found' message"

# Test 9 (error path, --dryrun): --profile combined with --config.
out="$(run_cb_expect_fail t9 --dryrun --profile dev --config "$TMPDIR/.booth/alt-config.toml" 2>&1 || true)"
assert_contains "--config" "$out" "--profile + --config is rejected with a clear conflict message"

# Test 10 (error path, --dryrun): --profile combined with --env-file.
echo "EXTRA=1" > "$TMPDIR/extra.env"
out="$(run_cb_expect_fail t10 --dryrun --profile dev --env-file "$TMPDIR/extra.env" 2>&1 || true)"
assert_contains "--env-file" "$out" "--profile + --env-file is rejected with a clear conflict message"

# Test 11 (error path, --dryrun): BOOTH_PROFILES combined with --config.
out="$(BOOTH_PROFILES=dev run_cb_expect_fail t11 --dryrun --config "$TMPDIR/.booth/alt-config.toml" 2>&1 || true)"
assert_contains "--config" "$out" "BOOTH_PROFILES + --config is rejected"

# Test 12: No profiles at all (remove default to verify base-only path).
rm -f "$TMPDIR/.booth/default--config.toml"
out="$(run_cb t12 2>/dev/null | tr -d '\r\n')"
assert_eq "FROM_BASE" "$out" "with no default profile and no --profile, only base config applies"

# ---- Summary -----------------------------------------------------------------
if (( failed_checks == 0 )); then
  echo "All $total_checks checks passed."
  exit 0
else
  echo "$failed_checks out of $total_checks checks failed."
  echo "Failed checks:"
  for msg in "${failed_msgs[@]}"; do
    echo "  - $msg"
  done
  exit 1
fi
