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
#
# envfolio+host-agent (with +store-host) mounts the host's gpg-agent socket in a
# tmpfs of the booth user's own, sets GPG_TTY=/dev/null and warns; without
# +store-host it is refused. A dry run names the default socket without asking
# the host's gpgconf.
#
# gnupg+store-host is store-host for the gpg home alone: one mount, the same
# tmpfs and warning, the same refusal of a second key (gnupg+keys, envfolio+seed)
# and of envfolio+store-host, which mounts the same folder. It is enough for
# envfolio+host-agent.
#
# gnupg+seed-host mounts the host's gpg home read-only at a side path, for the
# startup hook to copy from, and warns; it refuses gnupg+keys and both
# store-hosts.
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

OUT=$(dry 'envfolio+store-host+host-agent')
U=$(id -u) G=$(id -g)
if [[ "$(uname -s)" == Linux ]]; then
  ok=false
  printf '%s\n' "$OUT" | grep -F -- "--tmpfs '/run/user/$U/gnupg:uid=$U,gid=$G,mode=0700'" >/dev/null \
    && printf '%s\n' "$OUT" | grep -F -- "-v /run/user/$U/gnupg/S.gpg-agent:/run/user/$U/gnupg/S.gpg-agent" >/dev/null \
    && printf '%s\n' "$OUT" | grep -F -- "-e 'GPG_TTY=/dev/null'" >/dev/null \
    && ok=true
  result "$ok" 8 "host-agent mounts the host's gpg-agent socket in the booth user's own tmpfs, with no terminal named" "$OUT"

  ok=false
  printf '%s\n' "$OUT" | grep -F "Warning: envfolio+host-agent: gpg in this booth uses the host's gpg-agent" >/dev/null && ok=true
  result "$ok" 9 "host-agent warns that the booth can use every key the host has unlocked" "$OUT"
else
  # macOS / Windows: the engine's VM cannot reach a host socket. The dry run must say so, as the
  # real run does, and show no socket mount and no GPG_TTY.
  ok=false
  ! printf '%s\n' "$OUT" | grep -E "S\.gpg-agent|GPG_TTY" >/dev/null \
    && printf '%s\n' "$OUT" | grep -F "Info: envfolio+host-agent: the host's gpg-agent socket cannot be shared" >/dev/null \
    && ok=true
  result "$ok" 8 "host-agent on $(uname -s): no socket mount, no GPG_TTY, and it says why" "$OUT"

  ok=false
  ! printf '%s\n' "$OUT" | grep -F "Warning: envfolio+host-agent:" >/dev/null && ok=true
  result "$ok" 9 "host-agent on $(uname -s): no warning about the host's unlocked keys" "$OUT"
fi

OUT=$(dry 'envfolio+host-agent')
ok=false
printf '%s\n' "$OUT" | grep -F "envfolio+host-agent: needs envfolio+store-host or gnupg+store-host" >/dev/null && ok=true
result "$ok" 10 "host-agent without store-host is refused" "$OUT"

OUT=$(dry 'gnupg+store-host')
ok=false
printf '%s\n' "$OUT" | grep -F -- "-v $HOME/.gnupg:/home/coder/.gnupg" >/dev/null \
  && printf '%s\n' "$OUT" | grep -F -- "--tmpfs '/run/user/$U:uid=$U,gid=$G,mode=0700'" >/dev/null \
  && printf '%s\n' "$OUT" | grep -F "Warning: gnupg+store-host: the host's gpg home ($HOME/.gnupg)" >/dev/null \
  && ! printf '%s\n' "$OUT" | grep -F -- ":/home/coder/.folio" >/dev/null \
  && ok=true
result "$ok" 11 "gnupg+store-host mounts the host's gpg home alone, with the socket tmpfs and the warning" "$OUT"

ok=true
out=$(dry 'gnupg+store-host+keys:"me@example.com"')
printf '%s\n' "$out" | grep -F "gnupg+store-host: cannot be used with gnupg+keys" >/dev/null || { ok=false; OUT="$out"; }
out=$(dry 'gnupg+store-host/envfolio+seed:"--secrets gh"')
printf '%s\n' "$out" | grep -F "gnupg+store-host: cannot be used with envfolio+seed" >/dev/null || { ok=false; OUT="$out"; }
out=$(dry 'gnupg+store-host/envfolio+store-host')
printf '%s\n' "$out" | grep -F "gnupg+store-host: cannot be used with envfolio+store-host" >/dev/null || { ok=false; OUT="$out"; }
result "$ok" 12 "gnupg+store-host refuses gnupg+keys, envfolio+seed and envfolio+store-host" "$OUT"

OUT=$(dry 'gnupg+store-host/envfolio+host-agent')
ok=false
printf '%s\n' "$OUT" | grep -F -- "-v /run/user/$U/gnupg/S.gpg-agent:/run/user/$U/gnupg/S.gpg-agent" >/dev/null \
  && printf '%s\n' "$OUT" | grep -F -- "-e 'GPG_TTY=/dev/null'" >/dev/null \
  && ok=true
result "$ok" 13 "host-agent works with gnupg+store-host too: the host's agent socket is mounted" "$OUT"

OUT=$(dry 'gnupg+seed-host')
ok=false
printf '%s\n' "$OUT" | grep -F -- "-v $HOME/.gnupg:/etc/cb-gnupg-host:ro" >/dev/null \
  && printf '%s\n' "$OUT" | grep -F -- "CB_GNUPG_SEED_HOST=1" >/dev/null \
  && printf '%s\n' "$OUT" | grep -F "Warning: gnupg+seed-host: the host's gpg keyring ($HOME/.gnupg)" >/dev/null \
  && ! printf '%s\n' "$OUT" | grep -F -- ":/home/coder/.gnupg" >/dev/null \
  && ! printf '%s\n' "$OUT" | grep -F "writable mount of host" >/dev/null \
  && ok=true
result "$ok" 14 "gnupg+seed-host mounts the host's gpg home read-only beside the booth's, and warns" "$OUT"

ok=true
out=$(dry 'gnupg+seed-host+keys:"me@example.com"')
printf '%s\n' "$out" | grep -F "gnupg+seed-host: cannot be used with gnupg+keys" >/dev/null || { ok=false; OUT="$out"; }
out=$(dry 'gnupg+seed-host+store-host')
printf '%s\n' "$out" | grep -F "gnupg+store-host: cannot be used with gnupg+seed-host" >/dev/null || { ok=false; OUT="$out"; }
out=$(dry 'gnupg+seed-host/envfolio+store-host')
printf '%s\n' "$out" | grep -F "envfolio+store-host: cannot be used with gnupg+seed-host" >/dev/null || { ok=false; OUT="$out"; }
result "$ok" 15 "gnupg+seed-host refuses gnupg+keys, and both store-hosts refuse it" "$OUT"

OUT=$(dry 'envfolio+store-host')
ok=false
! printf '%s\n' "$OUT" | grep -E "S\.gpg-agent|GPG_TTY|/run/user/$U/gnupg" >/dev/null && ok=true
result "$ok" 16 "store-host alone mounts no agent socket and leaves GPG_TTY alone" "$OUT"
