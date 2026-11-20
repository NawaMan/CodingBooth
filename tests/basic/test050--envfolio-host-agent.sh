#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -uo pipefail

source ../common--source.sh

# -------------------------------------------------------
# Test: envfolio+host-agent — gpg in a booth is served by the host's gpg-agent
#
# A throwaway gpg home is made on the host (its own GNUPGHOME, never the user's
# ~/.gnupg), with a key that HAS a passphrase, and its agent's pinentry set to
# /bin/false so nothing can ever ask on this machine. The home goes to the booth
# through +store-host (FOLIO_HOST_GNUPG); +host-agent then has the booth's gpg
# use that home's agent on the host.
#
#   1. The key is unlocked on the host: the booth decrypts with no passphrase.
#   2. That is the host's agent (same pid), found at /run/user/<uid>/gnupg.
#   3. A login shell in the booth has GPG_TTY=/dev/null.
#   4. The host's cache is emptied: the booth's decrypt fails, and does not ask.
#   5. The start warns about what the booth can now do.
#
# Linux host only (a host socket does not reach an engine VM), and needs gpg on
# the host; skipped otherwise.
# Deliberately NOT `set -e`: see test016--viewmd.sh.
# -------------------------------------------------------

if [[ "$(uname -s)" != Linux ]] || ! command -v gpg >/dev/null 2>&1 || ! command -v gpg-connect-agent >/dev/null 2>&1; then
  echo "⏭️  basic/test050: needs a Linux host with gpg; skipped"
  exit 0
fi

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d)"
PROJECT="$WORK/project"
mkdir -p "$PROJECT" "$WORK/store"
export GNUPGHOME="$WORK/gnupg"
cleanup() { gpgconf --kill all >/dev/null 2>&1 || true; rm -rf "$WORK"; }
trap cleanup EXIT

FAILED=0
fail() { print_test_result "false" "$0" "$1" "$2"; echo "  $3"; FAILED=$((FAILED + 1)); }

# The host side: a key with a passphrase, a message encrypted to it, and an agent that can
# never ask (so a test that goes wrong fails instead of putting a prompt on this machine).
mkdir -m 700 "$GNUPGHOME"
echo 'pinentry-program /bin/false' > "$GNUPGHOME/gpg-agent.conf"
if ! { gpg --batch --pinentry-mode loopback --passphrase hostpass \
           --quick-gen-key 'Booth Agent Test <agent-test@example.com>' default default never \
       && echo from-host | gpg --batch --trust-model always -e -r agent-test@example.com -o "$PROJECT/msg.gpg"; } >/dev/null 2>&1; then
  fail 0 "the throwaway host key is made" "could not make the host gpg home in $WORK"
  exit 1
fi
unlock() { gpg --batch --pinentry-mode loopback --passphrase hostpass -d "$PROJECT/msg.gpg" >/dev/null 2>&1; }
HOST_PID=$(gpg-connect-agent 'getinfo pid' /bye 2>/dev/null | awk '$1 == "D" { print $2 }')

SCRIPT='
echo GOT=$(timeout 30 gpg --batch --decrypt ~/code/msg.gpg 2>/dev/null)
echo AGENT_PID=$(gpg-connect-agent --no-autostart "getinfo pid" /bye 2>/dev/null | awk "\$1 == \"D\" { print \$2 }")
echo SOCKET=$(gpgconf --list-dirs agent-socket)
echo TTY=$(bash -lc "echo \$GPG_TTY")
'
run_booth() {
  run_coding_booth express --code "$PROJECT" --templates-path "$REPO/templates" \
    --select "envfolio+store-host:\"$WORK/store\",\"$WORK/gnupg\"+host-agent" -- "$SCRIPT" 2>&1
}

unlock
OUT=$(run_booth) || true

# -------------------------------------------------------
# Test 1: unlocked on the host, the booth decrypts with no passphrase
# -------------------------------------------------------
if grep -qxF "GOT=from-host" <<<"$OUT"; then
  print_test_result "true" "$0" "1" "a key unlocked on the host decrypts in the booth, with no passphrase asked"
else
  fail 1 "a key unlocked on the host decrypts in the booth, with no passphrase asked" "Output: $(tail -8 <<<"$OUT")"
fi

# -------------------------------------------------------
# Test 2: it is the host's agent, at the socket the booth's gpg looks for
# -------------------------------------------------------
if [[ -n "$HOST_PID" ]] && grep -qxF "AGENT_PID=$HOST_PID" <<<"$OUT" \
   && grep -qxE "SOCKET=/run/user/[0-9]+/gnupg/S\.gpg-agent" <<<"$OUT"; then
  print_test_result "true" "$0" "2" "the booth's gpg talks to the host's gpg-agent (same pid), at /run/user/<uid>/gnupg"
else
  fail 2 "the booth's gpg talks to the host's gpg-agent (same pid), at /run/user/<uid>/gnupg" \
    "host pid: ${HOST_PID:-none}; $(grep -E '^(AGENT_PID|SOCKET)=' <<<"$OUT" | tr '\n' ' ')"
fi

# -------------------------------------------------------
# Test 3: a login shell names no terminal for the host's pinentry
# -------------------------------------------------------
if grep -qxF "TTY=/dev/null" <<<"$OUT"; then
  print_test_result "true" "$0" "3" "a login shell in the booth has GPG_TTY=/dev/null"
else
  fail 3 "a login shell in the booth has GPG_TTY=/dev/null" "$(grep '^TTY=' <<<"$OUT")"
fi

# -------------------------------------------------------
# Test 5 (from the same run): the start says what the booth can do
# -------------------------------------------------------
if grep -qF "Warning: envfolio+host-agent: gpg in this booth uses the host's gpg-agent" <<<"$OUT"; then
  print_test_result "true" "$0" "5" "the start warns that the booth can use every key the host has unlocked"
else
  fail 5 "the start warns that the booth can use every key the host has unlocked" "no warning in the output"
fi

# -------------------------------------------------------
# Test 4: nothing cached on the host: the booth cannot decrypt, and does not ask
# -------------------------------------------------------
gpg-connect-agent reloadagent /bye >/dev/null 2>&1
OUT=$(run_booth) || true
if grep -qxF "GOT=" <<<"$OUT" && grep -qxF "AGENT_PID=$HOST_PID" <<<"$OUT"; then
  print_test_result "true" "$0" "4" "with nothing unlocked on the host the booth's decrypt fails, and nothing is asked"
else
  fail 4 "with nothing unlocked on the host the booth's decrypt fails, and nothing is asked" \
    "$(grep -E '^(GOT|AGENT_PID)=' <<<"$OUT" | tr '\n' ' ')"
fi

if [[ "$FAILED" -ne 0 ]]; then
  exit 1
fi
