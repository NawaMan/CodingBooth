#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: code-server's integrated terminal actually renders the Fira Code Nerd
# Font, and its welcome banner survives VS Code's hidden shell-env probe.
#
# Font: code-server's terminal renders client-side in the browser via
# xterm.js — same architecture as ttyd (tests/basic/test023--ttyd-nerd-font.sh)
# — so `terminal.integrated.fontFamily` in settings.json only *names* the
# font; it doesn't supply it. start-booth-wrapped's nginx now serves the font
# at /booth-assets/fonts/ and sub_filter-injects an @font-face into the
# wrapped root document. Same gzip gotcha as ttyd: sub_filter can't rewrite a
# compressed body, and a real browser sends Accept-Encoding: gzip by default,
# so this has to check with `curl --compressed` — plain curl would falsely
# pass even with the old bug.
#
# Welcome banner: VS Code (and code-server) resolve what env vars your shell
# profile sets by spawning a *hidden* probe — an interactive login shell
# (`bash -i -l -c 'node -p "...JSON.stringify(process.env)..."'`) whose
# stdout is captured and parsed as JSON, never shown to any user — then seed
# every REAL terminal it opens afterward with that resolved environment.
# 99z-cb--profile.sh used to `export TIP_SHOWN=1` after printing the banner,
# so the hidden probe's own run of the profile consumed the one-time flag,
# and that got captured into the env snapshot code-server applies to real
# terminals too — the banner never reached any terminal a user actually saw.
# Fixed by no longer exporting TIP_SHOWN (a plain shell variable still
# dedupes ~/.bashrc's own re-source of /etc/profile.d/*-cb-*.sh within one
# process, but is invisible to a spawned child's process.env).
# -----------------------------------------------------------------------------

set -uo pipefail

source ../common--source.sh

FAILED=0

NAME="codeserver-terminal-$RANDOM"
PORT="$(pick_free_port)"

cleanup() {
  docker stop "$NAME" >/dev/null 2>&1 || true
  docker rm   "$NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

wait_for_200() {
  local url="$1"
  for i in {1..60}; do
    if curl -s -o /dev/null -w '%{http_code}' "$url" 2>/dev/null | grep -q 200; then
      return 0
    fi
    sleep 1
  done
  return 1
}

run_coding_booth --variant codeserver --name "$NAME" --port "$PORT" --daemon > "$0.log" 2>&1

if ! wait_for_200 "http://127.0.0.1:${PORT}/__booth/health"; then
  print_test_result "false" "$0" "0" "Booth '$NAME' never answered /__booth/health"
  docker logs "$NAME" 2>&1 | tail -30 >&2
  exit 1
fi

# code-server itself can take a while to come up behind the wrapper even
# after the wrapper's own health check is green (it proxies to the inner
# service, which reports healthy on redirects/errors too) — give the actual
# workbench page a moment to start answering with real content.
for i in {1..30}; do
  CODE=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${PORT}/?_booth_inner=1" 2>/dev/null)
  [[ "$CODE" == "200" ]] && break
  sleep 1
done

# -------------------------------------------------------
# Test 1: the wrapped root document carries the @font-face style even when
# gzip'd — the exact case plain curl would miss and falsely pass
# -------------------------------------------------------
ROOT_HTML=$(curl -sL --compressed "http://127.0.0.1:${PORT}/?_booth_inner=1")

if [[ "$ROOT_HTML" == *"@font-face"* && "$ROOT_HTML" == *"FiraCode Nerd Font Mono"* ]]; then
  print_test_result "true" "$0" "1" "wrapped root document carries the @font-face style even when gzip'd"
else
  print_test_result "false" "$0" "1" "wrapped root document should carry the @font-face style when gzip'd"
  echo "  First 300 chars of response: ${ROOT_HTML:0:300}"
  FAILED=$((FAILED + 1))
fi

# -------------------------------------------------------
# Test 2: the font referenced by that style is actually fetchable
# -------------------------------------------------------
FONT_CODE=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${PORT}/booth-assets/fonts/FiraCodeNerdFontMono-Regular.ttf")

if [[ "$FONT_CODE" == "200" ]]; then
  print_test_result "true" "$0" "2" "/booth-assets/fonts/ serves the referenced font file (200)"
else
  print_test_result "false" "$0" "2" "/booth-assets/fonts/ should serve the font file (200)"
  echo "  Actual status: $FONT_CODE"
  FAILED=$((FAILED + 1))
fi

# -------------------------------------------------------
# Test 3: the welcome banner still appears in a real terminal even after
# VS Code's hidden env-resolution probe has already run once.
#
# Two separate `docker exec` calls never share environment on their own —
# that's not what leaks TIP_SHOWN in the real bug. VS Code's own mechanism
# is: capture the probe's resolved process.env, then explicitly pass that
# captured environment into every real terminal it spawns afterward. So
# this test has to do the same explicit capture-and-replay to actually
# reproduce it, rather than just running two independent execs.
#
# `docker exec -it` isn't available non-interactively, so the real terminal
# is a genuine pty allocated via Python's pty.fork() (python3 is already on
# this image — codeserver--setup.sh installs it) running `bash -l`, exactly
# matching codeserver--setup.sh's "bash-login" terminal.integrated profile.
# -------------------------------------------------------

# The probe: interactive + login + a command (-c) — stdout is not a tty,
# same shape as VS Code's real one. `-u coder` (not `su -`) matches how
# code-server actually spawns it: code-server already runs as coder and
# hands node's child_process.spawn an explicit env object directly — no
# privilege switch or login-style environment reset in between, which `su -`
# would otherwise perform and which would mask exactly the leak this test
# exists to catch.
#
# Reading TIP_SHOWN has to go through a real child process (`env`), not a
# bash builtin like `echo` — a builtin sees the variable directly from the
# running shell's own memory regardless of export status, which would make
# this probe "see" TIP_SHOWN even under the fix and defeat the whole test.
# VS Code's actual probe has exactly this shape: `node -p
# "MARKER"+JSON.stringify(process.env)+"MARKER"` reads process.env in a
# separate node process, which only inherits what the parent shell exported.
# The banner (if it fires) shares this same stdout, so the same
# sentinel-marker trick is needed to pull the value back out cleanly.
PROBE_RAW=$(docker exec -u coder "$NAME" bash -i -l -c 'echo -n "MARK_$(env | grep -c '"'"'^TIP_SHOWN='"'"')_MARK"' 2>/dev/null)
PROBE_TIP_SHOWN=$(echo "$PROBE_RAW" | grep -o 'MARK_.*_MARK' | sed -e 's/^MARK_//' -e 's/_MARK$//')

PTY_SCRIPT='
import pty, os, time, select
pid, fd = pty.fork()
if pid == 0:
    os.execvp("bash", ["bash", "-l"])
else:
    time.sleep(2)
    os.write(fd, b"exit\n")
    time.sleep(1)
    out = b""
    while True:
        r, _, _ = select.select([fd], [], [], 0.3)
        if not r:
            break
        try:
            chunk = os.read(fd, 65536)
        except OSError:
            break
        if not chunk:
            break
        out += chunk
    print(out.decode(errors="replace"))
'
# Replay whatever the probe resolved TIP_SHOWN to into the real terminal's
# own environment — the explicit hand-off VS Code performs. When the fix
# holds this is "0" (never exported) and nothing gets injected; when the
# bug is present this is "1" and reintroduces exactly the leak it causes.
if [[ "$PROBE_TIP_SHOWN" == "1" ]]; then
  TERM_OUTPUT=$(docker exec -u coder -e "TIP_SHOWN=$PROBE_TIP_SHOWN" "$NAME" python3 -c "$PTY_SCRIPT" 2>/dev/null)
else
  TERM_OUTPUT=$(docker exec -u coder "$NAME" python3 -c "$PTY_SCRIPT" 2>/dev/null)
fi
BANNER_COUNT=$(echo "$TERM_OUTPUT" | grep -c "Welcome to CodingBooth")

if [[ "$BANNER_COUNT" == "1" ]]; then
  print_test_result "true" "$0" "3" "welcome banner appears once in a real terminal after the env-probe already ran"
else
  print_test_result "false" "$0" "3" "welcome banner should appear exactly once in a real terminal after the env-probe already ran"
  echo "  Banner occurrences: ${BANNER_COUNT:-<none>} (want 1)"
  echo "  Terminal output: ${TERM_OUTPUT:0:500}"
  FAILED=$((FAILED + 1))
fi

exit $FAILED
