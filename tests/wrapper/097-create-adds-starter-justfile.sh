#!/usr/bin/env bash
# 097 — `booth create <dir>` ends with `booth just-init`, so a new project starts
#       with a Justfile whose recipes run in the booth. A pinned binary older than
#       the command is skipped (create still succeeds), and a Justfile already in
#       <dir> is left alone when there is no terminal to ask about a backup.
#
#       The release in the cache may predate just-init, so the test swaps in this
#       checkout's binary and, for the old-binary case, a stub that knows no
#       commands — re-signing the cached sha256 each time, and creating with that
#       cached version pinned so nothing re-downloads it.
#
#       The binary it swaps in has to be a Linux one, because it runs in the
#       container, and which file that is depends on who built it:
#
#         bin/codingbooth-linux-<arch>   cli-build.sh's cross-build, written on
#                                        every host, so this is what a developer
#                                        machine has;
#         codingbooth                    the repo-root build — which IS a Linux
#                                        binary on a Linux host and in CI (the
#                                        workflow builds exactly this), a Mach-O
#                                        one on macOS, and on Windows a leftover
#                                        that cli-build.sh does not write at all
#                                        (it writes codingbooth.exe there).
#
#       So the container picks the cross-build when there is one and falls back
#       to the repo-root file only when that is really an ELF. `-x` was the old
#       test and is no test at all: on Windows Git Bash reads executability off
#       the content, so it is false for the Linux build sitting right there.
#       See tests/README.md.
source "$(dirname "$0")/_lib.sh"

[[ -s "$REPO_ROOT/codingbooth" \
   || -s "$REPO_ROOT/bin/codingbooth-linux-amd64" \
   || -s "$REPO_ROOT/bin/codingbooth-linux-arm64" ]] \
    || { echo "Build the CLI first: ./build/cli-build.sh" >&2; exit 2; }

LAST_OUTPUT=$(run_in_container <<'BASH'
set -euo pipefail
cp /booth/booth ./booth
./booth install >/dev/null

bin=$(find ~/.cache/codingbooth/versions -name 'codingbooth-*' -type f ! -name '*.sha256' | head -1)
[[ -n "$bin" ]] || { echo "ERROR: binary not found in shared cache"; exit 99; }
sha="$(dirname "$bin")/codingbooth.sha256"
name="$(basename "$bin")"
# create installs this cached version, not "latest": latest always re-downloads,
# which would put the release back over the swapped binary.
ver="$(basename "$(dirname "$bin")")"

# swap <file>: put <file> in the cache as the binary, and re-sign it.
swap() {
    chmod +w "$bin" "$sha" 2>/dev/null || true
    rm -f "$bin"; cp "$1" "$bin"; chmod +x "$bin"
    echo "$(sha256sum "$bin" | awk '{print $1}')  $name" > "$sha"
}

# This checkout's Linux binary: the cross-build when cli-build.sh wrote one,
# else the repo-root build, which is a Linux binary on a Linux host and in CI.
# The ELF check is what keeps a macOS or Windows file from being swapped in to
# fail unreadably a moment later.
case "$(uname -m)" in
    aarch64|arm64) arch=arm64 ;;
    *)             arch=amd64 ;;
esac
if [[ -s "/booth/bin/codingbooth-linux-$arch" ]]; then
    checkout_binary="/booth/bin/codingbooth-linux-$arch"
elif [[ -s /booth/codingbooth ]] && [[ "$(head -c 4 /booth/codingbooth)" == $'\x7fELF' ]]; then
    checkout_binary=/booth/codingbooth
else
    echo "ERROR: no Linux build of this checkout to swap in; run ./build/cli-build.sh"
    exit 98
fi

# --- a binary with just-init ---
swap "$checkout_binary"
./booth create app "$ver" </dev/null 2>&1
[[ -f app/Justfile ]] && echo "app: Justfile" || echo "app: no Justfile"
grep -q 'run-in-booth := ' app/Justfile && echo "app: starter"

# --- a Justfile already there, no terminal: left as it is, create still succeeds ---
mkdir -p mine && printf 'mine:\n    echo mine\n' > mine/Justfile
if ./booth create mine "$ver" </dev/null 2>&1; then echo "mine: create ok"; fi
grep -q '^mine:' mine/Justfile && echo "mine: untouched"
[[ -e mine/Justfile.bak ]] && echo "mine: backed up" || true

# --- an older binary, without just-init: skipped, create still succeeds ---
printf '#!/bin/sh\necho "Unknown command: $1" >&2\nexit 1\n' > /tmp/old-binary
swap /tmp/old-binary
if ./booth create old "$ver" </dev/null 2>&1; then echo "old: create ok"; fi
[[ -f old/Justfile ]] && echo "old: Justfile" || echo "old: no Justfile"
BASH
)

assert_contains     "$LAST_OUTPUT" "app: Justfile"
assert_contains     "$LAST_OUTPUT" "app: starter"
assert_contains     "$LAST_OUTPUT" "mine: create ok"
assert_contains     "$LAST_OUTPUT" "mine: untouched"
assert_not_contains "$LAST_OUTPUT" "mine: backed up"
assert_contains     "$LAST_OUTPUT" "Run again with --yes"
assert_contains     "$LAST_OUTPUT" "old: create ok"
assert_contains     "$LAST_OUTPUT" "old: no Justfile"
assert_not_contains "$LAST_OUTPUT" "Unknown command"
pass
