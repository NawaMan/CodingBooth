#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# check-go-example.sh  (EXPERIMENT -- see docs/REUSE_BOOTH.md)
#
# Run as the real user, as the command booth-entry ends with. Checks that the
# provisioned tools are reachable from each kind of shell, that the startup
# hooks ran, and that the example's own work passes. Appends to $REPORT.
# -----------------------------------------------------------------------------

set -uo pipefail

REPORT="${REPORT:-$HOME/host-provision-report.txt}"
FAILS=0

check() {   # check <label> <shell: login|interactive|zsh> <command>
  local label="$1" shell="$2" cmd="$3" out rc
  case "$shell" in
    login)       out="$(bash -lc  "$cmd" 2>&1 < /dev/null)"; rc=$? ;;
    interactive) out="$(bash -ic  "$cmd" 2>&1 < /dev/null)"; rc=$? ;;
    zsh)         out="$(zsh  -ic  "$cmd" 2>&1 < /dev/null)"; rc=$? ;;
  esac
  out="$(printf '%s' "$out" | grep -v -E 'cannot set terminal process group|no job control' | tail -n 1 | cut -c1-110)"
  if [ "$rc" -eq 0 ]; then
    printf 'PASS  %-46s %s\n' "$label [$shell]" "$out" | tee -a "$REPORT"
  else
    printf 'FAIL  %-46s %s\n' "$label [$shell]" "$out" | tee -a "$REPORT"
    FAILS=$((FAILS + 1))
  fi
}

echo "== checks as $(id -un) (uid $(id -u)), HOME=$HOME, cwd=$PWD" | tee -a "$REPORT"

for sh in login interactive zsh; do
  check "go is the setup's go"      "$sh" 'p=$(command -v go) && "$p" version | grep -q go1.25.7 && echo "$p"'
done
check "GOPATH under real home"      login '[ "$GOPATH" = "$HOME/go" ] && echo "$GOPATH"'
check "gopls installed"             login 'command -v gopls'
check "dlv installed"               login 'command -v dlv'
check "GOBIN owned by user"         login '[ "$(stat -c %U "$GOBIN")" = "$(id -un)" ] && echo ok || { stat -c "%U %n" "$GOBIN"; false; }'
check "python is the setup's"       login 'command -v python && python --version'
check "base: just"                  login 'command -v just'
check "base: lazygit"               login 'command -v lazygit'
check "base: gpg 2.5"               login 'gpg --version | head -n 1 | grep -q " 2\.5\." && gpg --version | head -n 1'
check "base: setups dir on PATH"    login 'command -v go--setup.sh'
check "startup hooks ran (go)"      login '[ -f "$HOME/.go-startup-done" ] && echo ok'
check "startup log written"         login 'grep -c "Running startup script" /tmp/startups.log'
check "rc profile block present"    login 'grep -q "CodingBooth profile" "$HOME/.bashrc" && echo ok'
check "codeserver installed"        login 'command -v code-server'
check "jupyter installed"           login 'command -v jupyter'
check "go kernel registered"        login 'jupyter kernelspec list | grep -wE "^ *go"'
check "example: go test"            login './run-go-test.sh > /tmp/go-test.log 2>&1 && tail -n 1 /tmp/go-test.log || { tail -n 1 /tmp/go-test.log; false; }'
check "example: build"              login './build.sh > /tmp/go-build.log 2>&1 && ls bin | head -n 1 || { grep -v "^\\s*$" /tmp/go-build.log | tail -n 1; false; }'

echo "== $FAILS failed check(s)" | tee -a "$REPORT"
exit 0
