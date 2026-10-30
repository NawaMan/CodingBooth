#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# prepare-test.sh  (EXPERIMENT -- see docs/REUSE_BOOTH.md)
#
# Tests `booth prepare` end to end in a throwaway plain ubuntu:26.04 container,
# with the binary ./build/cli-build.sh made (bin/codingbooth-linux-amd64, which
# carries the embedded kit). The example is copied in, never mounted, so nothing
# it builds lands in the checkout.
#
#   refusals  root without --add-user, a user without sudo, gha off a runner:
#             each must stop with its own message. Fast: nothing is provisioned.
#   gha       a simulated runner (user runner, GITHUB_ACTIONS/GITHUB_ENV/GITHUB_PATH,
#             --report in sticky /tmp), then a later step in plain bash that gets
#             the environment only from GITHUB_ENV and GITHUB_PATH and runs the
#             example's in-booth tests.
#   ubuntu    root with --add-user dev: the user is created and put in sudo, the
#             config.toml variant is replayed (APPLY line), the -e run-args are
#             rewritten to /home/dev; then the in-booth tests in dev's login shell.
#
# Usage:  prepare-test.sh refusals|gha|ubuntu [example-dir-relative-to-repo]
# Output: experiments/host-provision/.out/prepare-<mode>-<example>/
# Exits 1 when any check fails.
# -----------------------------------------------------------------------------

set -euo pipefail

MODE="${1:?usage: prepare-test.sh refusals|gha|ubuntu [example]}"
EXAMPLE_REL="${2:-examples/workspaces/go-example}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
EX_NAME="$(basename "$EXAMPLE_REL")"
BIN="$REPO/bin/codingbooth-linux-amd64"
case "$MODE" in refusals|gha|ubuntu) ;; *) echo "❌ mode must be refusals, gha or ubuntu" >&2; exit 2 ;; esac
[ -x "$BIN" ] || { echo "❌ $BIN is missing: run ./build/cli-build.sh first" >&2; exit 2; }
[ -d "$REPO/$EXAMPLE_REL" ] || { echo "❌ no example at $EXAMPLE_REL" >&2; exit 2; }

OUT="$HERE/.out/prepare-$MODE-$EX_NAME"
rm -rf "$OUT" && mkdir -p "$OUT"
NAME="cb-prepare-test-$MODE-$EX_NAME"
docker rm -f "$NAME" >/dev/null 2>&1 || true

# The container gets the binary and the example (files git tracks or would add)
# on stdin as one tar: /w/booth and /w/example.
STAGE="$(mktemp -d)"
chmod 755 "$STAGE"                  # tar carries this mode to /w: runner must reach /w/booth
trap 'rm -rf "$STAGE"' EXIT
install -m 0755 "$BIN" "$STAGE/booth"
mkdir -p "$STAGE/example"
(cd "$REPO/$EXAMPLE_REL" && git ls-files -co --exclude-standard -z . | tar --null -T - -cf -) | tar -xf - -C "$STAGE/example"
# What a later workflow step gets: each NAME<<DELIM block of $GITHUB_ENV, and each
# $GITHUB_PATH line put in front of PATH (the last line written ends up first).
cat > "$STAGE/load-github-env.sh" <<'EOS'
while IFS= read -r line; do
  [[ "$line" =~ ^([A-Za-z_0-9]+)\<\<(.*)$ ]] || continue
  key="${BASH_REMATCH[1]}"; delim="${BASH_REMATCH[2]}"; val=""; first=1
  while IFS= read -r l && [ "$l" != "$delim" ]; do
    if [ "$first" = 1 ]; then val="$l"; first=0; else val="$val"$'\n'"$l"; fi
  done
  export "$key=$val"
done < "$GITHUB_ENV"
while IFS= read -r l; do PATH="$l:$PATH"; done < "$GITHUB_PATH"
export PATH
EOS

set +e
tar -cf - -C "$STAGE" . | docker run -i --rm --name "$NAME" -e MODE="$MODE" -v "$OUT:/out" ubuntu:26.04 bash -c '
set -uo pipefail
mkdir -p /w && tar -xf - -C /w
apt-get update -qq && apt-get install -y -qq sudo ca-certificates >/dev/null 2>&1
userdel -r ubuntu 2>/dev/null || true
FAILS=0
check() {   # check <label> <command...>: PASS when the command succeeds
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then echo "PASS  $label"; else echo "FAIL  $label"; FAILS=$((FAILS + 1)); fi
}
no_home_coder() { [ ! -f /etc/profile.d/06-cb-config-env.sh ] || ! grep -q /home/coder /etc/profile.d/06-cb-config-env.sh; }
has_variant_apply() {   # a non-base config.toml variant must be APPLY in the report
  grep -q "^variant *= *\"\(base\|\)\"" /w/example/.booth/config.toml 2>/dev/null && return 0
  grep -q "^variant" /w/example/.booth/config.toml 2>/dev/null || return 0
  grep -q "^APPLY variant" "$1"
}
run_tests() {   # run_tests <dir> <command...>: the example in-booth tests, if it has any
  local dir="$1"; shift
  [ -f "$dir/.cb-tests/inBooth--run-all-tests.sh" ] || return 0
  "$@" "cd $dir && bash .cb-tests/inBooth--run-all-tests.sh" > /out/tests.log 2>&1
}

case "$MODE" in
refusals)
  out=$(/w/booth prepare ubuntu --code /w/example --yes 2>&1); rc=$?
  check "root without --add-user stops"                  test "$rc" -ne 0
  check "  ... and names --add-user <name>"              grep -q -- "--add-user <name>" <<< "$out"
  useradd -m -s /bin/bash nosudo
  out=$(runuser -u nosudo -- /w/booth prepare ubuntu --code /w/example --yes < /dev/null 2>&1); rc=$?
  check "a user without sudo stops"                      test "$rc" -ne 0
  check "  ... and says it needs a user that can sudo"   grep -q "needs a user that can sudo" <<< "$out"
  out=$(runuser -u nosudo -- /w/booth prepare gha --code /w/example < /dev/null 2>&1); rc=$?
  check "gha off a runner stops"                         test "$rc" -ne 0
  check "  ... and says it runs on a GitHub Actions runner" grep -q "GitHub Actions runner" <<< "$out"
  ;;
gha)
  useradd -m -u 1001 -s /bin/bash runner
  echo "runner ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/runner
  P=/home/runner/work/project; mkdir -p "$P" && cp -a /w/example/. "$P" && chown -R runner: /home/runner/work
  install -d -m 0777 /tmp/gh; touch /tmp/gh/env /tmp/gh/path; chmod 666 /tmp/gh/*
  runuser -u runner -- env -i HOME=/home/runner USER=runner PATH=/usr/bin:/bin \
    GITHUB_ACTIONS=true GITHUB_ENV=/tmp/gh/env GITHUB_PATH=/tmp/gh/path \
    bash -c "cd $P && /w/booth prepare gha --report /tmp/report.txt" < /dev/null > /out/prepare.log 2>&1; rc=$?
  cp /tmp/report.txt /out/report.txt 2>/dev/null; cp /tmp/gh/env /out/github_env; cp /tmp/gh/path /out/github_path
  check "booth prepare gha exits 0"                      test "$rc" -eq 0
  check "the report (in sticky /tmp) has lines"          test -s /tmp/report.txt
  check "the report has no FAIL line"                    bash -c "! grep -q \"^FAIL \" /tmp/report.txt"
  check "GITHUB_ENV and GITHUB_PATH were written"        test -s /tmp/gh/env -a -s /tmp/gh/path
  check "config.toml -e values point at /home/runner"    no_home_coder
  check "APT_SNAPSHOT is not applied (DROP)"             bash -c "! grep -q \"^APT_SNAPSHOT<<\" /tmp/gh/env"
  # A later step: plain bash, nothing from a profile, only what GitHub would carry over.
  check "a later plain-bash step passes the in-booth tests" run_tests "$P" \
    runuser -u runner -- env -i HOME=/home/runner USER=runner PATH=/usr/bin:/bin \
      GITHUB_ENV=/tmp/gh/env GITHUB_PATH=/tmp/gh/path bash --noprofile --norc -c "source /w/load-github-env.sh && eval \"\$0\""
  ;;
ubuntu)
  P=/srv/project; mkdir -p "$P" && cp -a /w/example/. "$P" && chmod -R a+rwX "$P"
  /w/booth prepare ubuntu --add-user dev --code "$P" --yes --report /tmp/report.txt < /dev/null > /out/prepare.log 2>&1; rc=$?
  cp /tmp/report.txt /out/report.txt 2>/dev/null
  check "booth prepare ubuntu --add-user dev exits 0"    test "$rc" -eq 0
  check "the report has no FAIL line"                    bash -c "! grep -q \"^FAIL \" /tmp/report.txt"
  check "dev exists and is in sudo"                      bash -c "id -nG dev | grep -qw sudo"
  check "a non-base config.toml variant is APPLY"        has_variant_apply /tmp/report.txt
  check "config.toml -e values point at /home/dev"       no_home_coder
  check "the in-booth tests pass in dev login shell"     run_tests "$P" runuser -l dev -c
  ;;
esac
chown -R "$(stat -c %u:%g /out)" /out 2>/dev/null
echo "== $FAILS failed check(s)"
[ "$FAILS" -eq 0 ]
' 2>&1 | tee "$OUT/run.log"
rc=${PIPESTATUS[1]}
set -e
echo "Output: $OUT"
exit "$rc"
