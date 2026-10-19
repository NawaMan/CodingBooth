#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: [[owner-permission]] reaches the FILES inside a mount, not only its
# directories.
#
# Docker seeds a fresh named volume from whatever the image holds at that path,
# so a package cache written at image build time (a Boothfile `install go …`
# runs `go install`, which fills GOCACHE) arrives owned by the build-time uid,
# 1000. booth-entry aligns coder to HOST_UID instead, and its home sweep is
# -xdev, so only these entries reach inside the mount. They used to chown
# `-type d` alone: every directory came out coder:coder 1777 while the files
# kept the foreign uid, and on any host off uid 1000 — every Mac, which is 501 —
# `go build` died on `failed to trim cache: open …/trim.txt: permission denied`,
# because a 1777 directory does not help an open on a file that already exists.
#
# 1) booth config generates .booth/ from the project-local template.
# 2) The volume is seeded the way docker seeds one from an image: a foreign uid
#    on the directories, the files and a symlink pointing out of the tree.
# 3) One booth start, and from inside it:
#    - coder can write a seeded file (the regression);
#    - that file is coder-owned and still mode 644 (the mode stays dir-only on
#      purpose: a Go module cache keeps its files read-only and go checks that);
#    - the directories are coder-owned 1777, as they always were;
#    - the symlink did not redirect the chown out of the mount.
#
# It lives in complex/ rather than basic/ because it needs a fixture directory:
# an owner-permission entry can only come from a template, and the project-local
# one here brings the mount without any of the real cache extensions' setups —
# so this runs on the base image, and on a volume the test owns and removes
# instead of the machine-wide booth-cache-* the catalog mounts.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../../common--source.sh

echo "=== Test: owner-permission reaches files inside a mount ==="

# The volume is seeded and removed with the docker CLI, and a named volume is
# not what `container volume` makes. The suites pin CB_ENGINE=docker, so this
# only steps aside on a run made with another engine on purpose.
ENGINE="$(printf '%s' "${CB_ENGINE:-docker}" | tr '[:upper:]' '[:lower:]')"
if [[ "$ENGINE" != "docker" ]]; then
  echo "SKIP: this test seeds a docker named volume; CB_ENGINE is '$ENGINE'."
  exit 0
fi

# Must match the mount in .booth/templates/opcache.toml.
VOL="cb-test-op-files"
MOUNT="/home/coder/.cache/cb-op-test"
# A uid that is neither the image's build-time 1000 nor any likely HOST_UID: on
# a host that happens to be 1000 the seeded files would already be coder's and
# the cases below would pass against the old dir-only sweep too. Case 0 checks
# the booth did not land on it anyway.
SEED_UID=4242

FAILED=0
NUM=0
check() {
  local ok="$1" desc="$2"
  NUM=$((NUM + 1))
  print_test_result "$ok" "$0" "$NUM" "$desc"
  [[ "$ok" == "true" ]] || FAILED=$((FAILED + 1))
}

REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
if [[ ! -d "$REPO_ROOT/templates" ]]; then
  echo "ERROR: stock templates not found at $REPO_ROOT/templates" >&2
  exit 1
fi
export CB_TEMPLATES_PATH="$REPO_ROOT/templates"

CB_STDERR_LOG="$(mktemp)"
export CB_STDERR_LOG

cleanup() {
  docker volume rm -f "$VOL" >/dev/null 2>&1 || true
  rm -f .booth/Boothfile .booth/config.toml .booth/.generated .booth/owner-permission.yaml
  reset_booth_tmp
  rm -f "$CB_STDERR_LOG"
}
trap cleanup EXIT

# --- Step 1: generate .booth/ from the project-local template ----------------
rm -f .booth/Boothfile .booth/config.toml .booth/.generated .booth/owner-permission.yaml
reset_booth_tmp
if ! run_coding_booth config --no-tui --overwrite --select opcache \
  >"$CB_STDERR_LOG" 2>&1; then
  echo "ERROR: booth config failed" >&2
  cat "$CB_STDERR_LOG" >&2
  exit 1
fi

if grep -qF "path: \"$MOUNT\"" .booth/owner-permission.yaml 2>/dev/null \
  && grep -qF "$VOL:$MOUNT" .booth/config.toml 2>/dev/null; then
  check true "config wrote the volume mount and its owner-permission entry"
else
  check false "config should mount $VOL on $MOUNT and list it in owner-permission.yaml"
  cat .booth/config.toml .booth/owner-permission.yaml 2>/dev/null | sed 's/^/    /'
  exit 1
fi

# --- Step 2: seed the volume the way docker seeds one from an image -----------
# Everything under the mount owned by a uid that is not the booth's coder,
# directories 0755 and files 0644, plus a symlink out of the tree.
SEED_IMAGE="nawaman/codingbooth:base-latest"
if ! docker image inspect "$SEED_IMAGE" >/dev/null 2>&1; then
  echo "SKIP: $SEED_IMAGE is not available to seed the volume with."
  exit 0
fi

docker volume rm -f "$VOL" >/dev/null 2>&1 || true
if ! docker run --rm --user 0:0 --entrypoint /bin/bash -v "$VOL":/seed "$SEED_IMAGE" -c "
    set -euo pipefail
    mkdir -p /seed/ab
    printf 'seed\n' > /seed/trim.txt
    printf 'blob\n' > /seed/ab/entry-a
    ln -sfn /etc/shadow /seed/escape
    chmod 0755 /seed /seed/ab
    chmod 0644 /seed/trim.txt /seed/ab/entry-a
    chown -R $SEED_UID:$SEED_UID /seed
    chown -h $SEED_UID:$SEED_UID /seed/escape
  " >>"$CB_STDERR_LOG" 2>&1; then
  echo "ERROR: could not seed volume $VOL" >&2
  tail -20 "$CB_STDERR_LOG" >&2
  exit 1
fi

# --- Step 3: one booth start, read the state from inside it ------------------
PROBE='id -u | sed "s/^/CODER_UID=/"
       id -g | sed "s/^/CODER_GID=/"
       stat -c "DIR=%u:%g:%a" '"$MOUNT"'
       stat -c "SUBDIR=%u:%g:%a" '"$MOUNT"'/ab
       stat -c "FILE=%u:%g:%a" '"$MOUNT"'/trim.txt
       stat -c "SUBFILE=%u:%g:%a" '"$MOUNT"'/ab/entry-a
       stat -c "SHADOW=%u:%g" /etc/shadow   # the symlink in the mount points here
       if echo rewritten > '"$MOUNT"'/trim.txt 2>/dev/null; then echo WRITE=ok; else echo WRITE=failed; fi'

OUT="$(capture_codingbooth "cat" --silence-build -- "$PROBE")" || OUT=""
field() { printf '%s\n' "$OUT" | grep -o "^$1=.*" | head -1 | cut -d= -f2- | tr -d '\r'; }

CODER_UID="$(field CODER_UID)"
# coder's group is HOST_GID, which is not HOST_UID — on a Mac it is staff, 20.
CODER_GID="$(field CODER_GID)"
if [[ -z "$CODER_UID" ]]; then
  echo "ERROR: the booth produced no output" >&2
  printf '%s\n' "$OUT" | sed 's/^/    /'
  tail -40 "$CB_STDERR_LOG" 2>/dev/null | sed 's/^/    /' || true
  exit 1
fi

if [[ "$CODER_UID" == "$SEED_UID" ]]; then
  echo "SKIP: coder is uid $CODER_UID in this booth, the uid the volume was seeded with,"
  echo "      so a file owned by it proves nothing. Pick another SEED_UID."
  exit 0
fi

# 2) The regression: a seeded file is writable by coder.
if [[ "$(field WRITE)" == "ok" ]]; then
  check true "coder can write a file the image left inside the mount"
else
  check false "coder should be able to write a file the image left inside the mount"
  printf '%s\n' "$OUT" | sed 's/^/    /'
fi

# 3) Ownership reached the files; the mode did not.
if [[ "$(field FILE)" == "$CODER_UID:$CODER_GID:644" ]]; then
  check true "a file in the mount is coder-owned and keeps its own mode (644)"
else
  check false "file in the mount should be $CODER_UID:$CODER_GID:644, got '$(field FILE)'"
fi

if [[ "$(field SUBFILE)" == "$CODER_UID:$CODER_GID:644" ]]; then
  check true "a file in a subdirectory of the mount is coder-owned too"
else
  check false "file under the mount should be $CODER_UID:$CODER_GID:644, got '$(field SUBFILE)'"
fi

# 4) Directories keep the behaviour they always had.
if [[ "$(field DIR)" == "$CODER_UID:$CODER_GID:1777" && "$(field SUBDIR)" == "$CODER_UID:$CODER_GID:1777" ]]; then
  check true "the mount and its subdirectories are coder-owned, mode 1777"
else
  check false "directories should be $CODER_UID:$CODER_GID:1777, got '$(field DIR)' and '$(field SUBDIR)'"
fi

# 5) A symlink inside the mount must not redirect the chown out of it.
if [[ "$(field SHADOW)" != "$CODER_UID:"* ]]; then
  check true "a symlink in the mount did not hand the chown a target outside it"
else
  check false "/etc/shadow is coder-owned ('$(field SHADOW)'): the chown followed the symlink out"
fi

echo ""
if [[ "$FAILED" -eq 0 ]]; then
  echo "✅ All owner-permission file-ownership checks passed"
  exit 0
fi
echo "❌ $FAILED owner-permission check(s) failed"
exit 1
