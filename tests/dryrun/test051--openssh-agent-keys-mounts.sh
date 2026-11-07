#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# openssh+agent and openssh+keys: the mounts the run would make
#
# +agent mounts the host ssh-agent socket read-only (a writable host mount would
# need consent) and points SSH_AUTH_SOCK at it. With no agent, SSH_AUTH_SOCK
# falls back to a path that does not exist, so the mount is skipped with a
# notice -- an empty source would reach Docker as "-v :/..." and stop the booth.
#
# +keys mounts one chosen folder at /etc/cb-ssh-keys, not at the home seed
# (/etc/cb-home-seed/.ssh) that +credential uses, so the two combine: Docker
# refuses two mounts on one target. A missing folder is skipped.
#
# HOME is a temp folder, so +credential's ~/.ssh is the test's, not the machine's.
# The agent "socket" is a plain file: the missing-mount filter only checks that
# the path exists.
# -----------------------------------------------------------------------------

set -euo pipefail

source ../common--source.sh

strip_ansi() { sed -r 's/\x1B\[[0-9;]*[A-Za-z]//g'; }

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PROJECT="$WORK/project"
FAKE_HOME="$WORK/home"
KEYS="$WORK/booth-keys"
SOCK="$WORK/agent.sock"
mkdir -p "$PROJECT" "$FAKE_HOME/.ssh" "$KEYS"
: > "$SOCK"

# dry SELECTION [AGENT_SOCK] -- the dryrun output of express with that selection,
# with SSH_AUTH_SOCK set to AGENT_SOCK, or unset when it is not given.
dry() {
  local selection="$1" sock="${2:-}"
  (
    export HOME="$FAKE_HOME"
    if [[ -n "$sock" ]]; then export SSH_AUTH_SOCK="$sock"; else unset SSH_AUTH_SOCK; fi
    run_coding_booth express --dryrun --code "$PROJECT" --templates-path "$REPO/templates" \
      --select "$selection" -- true 2>&1 | strip_ansi || true
  )
}

TEST_NUM=0
check() {
  TEST_NUM=$((TEST_NUM + 1))
  if [[ "$1" == "true" ]]; then
    print_test_result "true" "$0" "$TEST_NUM" "$2"
  else
    print_test_result "false" "$0" "$TEST_NUM" "$2"
    echo "$3" | grep -i -E 'ssh|skipping' | sed 's/^/      /' | head -12
    exit 1
  fi
}
has()  { printf '%s\n' "$1" | grep -F -- "$2" >/dev/null; }

# ---- +agent ----

OUT=$(dry 'openssh+agent' "$SOCK")
has "$OUT" "$SOCK:/run/cb-ssh-agent.sock:ro" && has "$OUT" "SSH_AUTH_SOCK=/run/cb-ssh-agent.sock" \
  && check "true"  "+agent with an agent: socket mounted read-only, SSH_AUTH_SOCK points at it" \
  || check "false" "+agent with an agent: socket mounted read-only, SSH_AUTH_SOCK points at it" "$OUT"

OUT=$(dry 'openssh+agent')
! has "$OUT" ":/run/cb-ssh-agent.sock" \
  && has "$OUT" "Skipping volume mount: host path does not exist: /nonexistent/no-ssh-agent.sock" \
  && ! printf '%s\n' "$OUT" | grep -E -- "-v '?:/" >/dev/null \
  && check "true"  "+agent with no agent: the mount is skipped with a notice, no empty -v source" \
  || check "false" "+agent with no agent: the mount is skipped with a notice, no empty -v source" "$OUT"

# ---- +keys ----

OUT=$(dry "openssh+keys:\"$KEYS\"")
has "$OUT" "$KEYS:/etc/cb-ssh-keys:ro" && ! has "$OUT" "/etc/cb-home-seed/.ssh" \
  && check "true"  "+keys: the chosen folder is mounted read-only at /etc/cb-ssh-keys, not the home seed" \
  || check "false" "+keys: the chosen folder is mounted read-only at /etc/cb-ssh-keys, not the home seed" "$OUT"

OUT=$(dry 'openssh+keys')
! has "$OUT" ":/etc/cb-ssh-keys" \
  && has "$OUT" "Skipping volume mount: host path does not exist: $FAKE_HOME/.ssh/booth" \
  && check "true"  "+keys with the default ~/.ssh/booth missing: skipped with a notice" \
  || check "false" "+keys with the default ~/.ssh/booth missing: skipped with a notice" "$OUT"

OUT=$(dry "openssh+keys:\"$KEYS\"+credential")
has "$OUT" "$KEYS:/etc/cb-ssh-keys:ro" && has "$OUT" "$FAKE_HOME/.ssh:/etc/cb-home-seed/.ssh:ro" \
  && check "true"  "+keys with +credential: both mounted, each on its own target" \
  || check "false" "+keys with +credential: both mounted, each on its own target" "$OUT"
