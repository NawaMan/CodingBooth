#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: the openssh setup's startup hook and its pinned GitHub host keys
#
# openssh+keys mounts one chosen host folder read-only at /etc/cb-ssh-keys (not
# the home seed, which +credential owns). The startup hook copies it into
# ~/.ssh: never over an existing file, private keys 600, .pub/known_hosts 644,
# ~/.ssh 700 -- ssh refuses a private key others can read. No folder, nothing.
#
# The setup also pins GitHub's host keys into /etc/ssh/ssh_known_hosts, so an
# agent- or key-folder booth needs no known_hosts. Their fingerprints are checked
# against GitHub's published ones (https://api.github.com/meta), so a typo in a
# key line fails here instead of as a "host key changed" in a booth.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SETUP_SCRIPT="$REPO_ROOT/variants/base/setups/openssh--setup.sh"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

STARTUP="$WORK/openssh--startup.sh"
awk '/> "\$STARTUP_FILE" <<.EOF.$/{flag=1;next}/^EOF$/{flag=0}flag' "$SETUP_SCRIPT" > "$STARTUP"
KEYS="$WORK/known-hosts"
awk '/^done <<.KEYS.$/{flag=1;next}/^KEYS$/{flag=0}flag' "$SETUP_SCRIPT" > "$KEYS"
if ! grep -q 'cb-ssh-keys' "$STARTUP" || [[ ! -s "$KEYS" ]]; then
    echo "❌ Could not extract the startup hook or the host keys from $SETUP_SCRIPT"
    exit 1
fi

ALL_PASSED=true
TEST_NUM=0
check() {
    local ok="$1" desc="$2" detail="${3:-}"
    TEST_NUM=$((TEST_NUM + 1))
    print_test_result "$ok" "$0" "$TEST_NUM" "$desc"
    if [[ "$ok" != "true" ]]; then
        [[ -n "$detail" ]] && echo "$detail" | sed 's/^/      /' | head -8
        ALL_PASSED=false
    fi
}

mode() { file_mode "$1" 2>/dev/null || echo missing; }

# run_startup HOME KEYS_DIR -- the hook in a clean environment (twice = a restart).
RUN_EXIT=0
run_startup() {
    mkdir -p "$1"
    env -i HOME="$1" PATH="/usr/bin:/bin" CB_SSH_KEYS_DIR="$2" \
        bash "$STARTUP" > /dev/null 2>&1 && RUN_EXIT=0 || RUN_EXIT=$?
}

# A key folder as a user would make it: modes loose on purpose (a copy from a
# FAT stick, a checkout), a subfolder that must not come along.
SRC="$WORK/booth-keys"
mkdir -p "$SRC/sub"
echo "PRIVATE" > "$SRC/id_deploy";       chmod 644 "$SRC/id_deploy"
echo "PUBLIC"  > "$SRC/id_deploy.pub";   chmod 600 "$SRC/id_deploy.pub"
echo "Host github.com" > "$SRC/config"; chmod 666 "$SRC/config"
echo "host key" > "$SRC/known_hosts";   chmod 600 "$SRC/known_hosts"
echo "nested" > "$SRC/sub/other"

run_startup "$WORK/home-none" "$WORK/does-not-exist"
[[ "$RUN_EXIT" -eq 0 && ! -e "$WORK/home-none/.ssh" ]] \
    && check "true"  "no key folder: ~/.ssh is not created" \
    || check "false" "no key folder: ~/.ssh is not created" "exit=$RUN_EXIT"

run_startup "$WORK/home-copy" "$SRC"
h="$WORK/home-copy/.ssh"
got="dir=$(mode "$h") key=$(mode "$h/id_deploy") pub=$(mode "$h/id_deploy.pub") config=$(mode "$h/config") known=$(mode "$h/known_hosts")"
[[ "$RUN_EXIT" -eq 0 && "$got" == "dir=700 key=600 pub=644 config=600 known=644" \
   && "$(cat "$h/id_deploy")" == "PRIVATE" ]] \
    && check "true"  "keys are copied with ssh's modes (700 dir, 600 private, 644 public)" \
    || check "false" "keys are copied with ssh's modes (700 dir, 600 private, 644 public)" "exit=$RUN_EXIT"$'\n'"$got"

[[ ! -e "$h/sub" ]] \
    && check "true"  "a subfolder of the key folder is not copied" \
    || check "false" "a subfolder of the key folder is not copied" "$(ls -la "$h")"

[[ "$(mode "$SRC/id_deploy")" == "644" ]] \
    && check "true"  "the host folder is not changed" \
    || check "false" "the host folder is not changed" "id_deploy is now $(mode "$SRC/id_deploy")"

mkdir -p "$WORK/home-clash/.ssh"
echo "FROM-CREDENTIAL" > "$WORK/home-clash/.ssh/id_deploy"
run_startup "$WORK/home-clash" "$SRC"
nh="$WORK/home-clash/.ssh"
[[ "$RUN_EXIT" -eq 0 && "$(cat "$nh/id_deploy")" == "FROM-CREDENTIAL" && -f "$nh/id_deploy.pub" ]] \
    && check "true"  "an existing file (e.g. from +credential) is not overwritten; the rest is added" \
    || check "false" "an existing file (e.g. from +credential) is not overwritten; the rest is added" \
         "id_deploy=$(cat "$nh/id_deploy" 2>/dev/null)"

run_startup "$WORK/home-copy" "$SRC"
[[ "$RUN_EXIT" -eq 0 && "$(ls "$h" | wc -l)" -eq 4 && "$(mode "$h/id_deploy")" == "600" ]] \
    && check "true"  "a restart copies nothing twice and does not fail" \
    || check "false" "a restart copies nothing twice and does not fail" "$(ls -la "$h")"

# ---- GitHub host keys ----
want=$'SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU\nSHA256:p2QAMXNIC1TJYWeIOttrVc98/R1BUFWu3/LiyKgUfQM\nSHA256:uNiVztksCsDhcc0u9e8BujQXVUpKZIDTMczCvj3tD2s'
got="$(ssh-keygen -lf "$KEYS" 2>/dev/null | awk '{print $2}' | sort)"
hosts="$(awk '{print $1}' "$KEYS" | sort -u)"
[[ "$got" == "$(echo "$want" | sort)" && "$hosts" == "github.com" ]] \
    && check "true"  "the pinned github.com host keys match GitHub's published fingerprints" \
    || check "false" "the pinned github.com host keys match GitHub's published fingerprints" "$got"$'\n'"hosts: $hosts"

$ALL_PASSED
