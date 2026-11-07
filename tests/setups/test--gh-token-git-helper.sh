#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: the gh startup points git at gh when a token is in the environment
#
# gh+token passes GH_TOKEN / GITHUB_TOKEN (and GH_ENTERPRISE_TOKEN / GH_HOST) into the booth.
# gh reads it, but git does not: `git push` over HTTPS asks git's credential
# helper, and without one it prompts for a username. A helper copied in from
# the host's ~/.gitconfig is no better -- it names the host's gh path. So the
# startup hook runs `gh auth setup-git` for each host it has a token for, and
# nothing when it has none (a booth without a token keeps its git config).
#
# The helper is for HTTPS only, and an SSH remote (git@github.com:owner/repo)
# cannot use the token. A booth with no ssh client cannot reach it at all, so the
# hook then also points git at HTTPS for that host (url.<https>.insteadOf, in
# ~/.gitconfig only). A booth with ssh keeps SSH. Real git checks the rewrite.
#
# The startup hook is extracted from gh--setup.sh and run against a stub gh that
# records how it was called. The real thing -- gh logged in from GH_TOKEN and
# `git credential fill` handing git the token -- was checked in a booth by hand.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SETUP_SCRIPT="$REPO_ROOT/variants/base/setups/gh--setup.sh"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

STARTUP="$WORK/gh--startup.sh"
awk '/> "\$\{STARTUP_FILE\}" <<.EOF.$/{flag=1;next}/^EOF$/{flag=0}flag' \
    "$SETUP_SCRIPT" > "$STARTUP"
if ! grep -q 'setup-git' "$STARTUP"; then
    echo "❌ Could not extract the startup heredoc from $SETUP_SCRIPT"
    exit 1
fi

mkdir -p "$WORK/bin"
GH_LOG="$WORK/gh.log"
cat > "$WORK/bin/gh" <<EOF
#!/bin/sh
echo "gh \$*" >> "$GH_LOG"
[ -n "\${STUB_GH_FAIL:-}" ] && exit 1
exit 0
EOF
chmod +x "$WORK/bin/gh"

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

# PATHs that decide whether the booth "has ssh", whatever the host has:
# nossh holds only what the hook needs besides gh; withssh adds a stub ssh.
mkdir -p "$WORK/nossh" "$WORK/withssh"
for tool in git grep; do ln -s "$(command -v "$tool")" "$WORK/nossh/$tool"; done
printf '#!/bin/sh\nexit 0\n' > "$WORK/withssh/ssh"
chmod +x "$WORK/withssh/ssh"
PATH_NOSSH="$WORK/bin:$WORK/nossh"
PATH_WITHSSH="$WORK/bin:$WORK/nossh:$WORK/withssh"
BASH_BIN="$(command -v bash)"
GIT_BIN="$(command -v git)"

# run_startup [VAR=value…] -- a clean environment, nothing from the host's.
# RUN_PATH picks the booth's PATH; the home is per test, so calling it twice in
# one test is a restart.
RUN_EXIT=0
RUN_PATH="$PATH_WITHSSH"
run_startup() {
    local home="$WORK/home-$TEST_NUM"
    mkdir -p "$home"
    : > "$GH_LOG"
    env -i HOME="$home" PATH="$RUN_PATH" "$@" \
        "$BASH_BIN" "$STARTUP" > /dev/null 2>&1 && RUN_EXIT=0 || RUN_EXIT=$?
}

# insteadof HOST -- the SSH forms the test's home rewrites to https://HOST/.
insteadof() {
    HOME="$WORK/home-$TEST_NUM" "$GIT_BIN" config --global --get-all "url.https://$1/.insteadOf" 2>/dev/null || true
}
# resolved URL -- what git would really fetch/push for URL in the test's home.
resolved() {
    HOME="$WORK/home-$TEST_NUM" "$GIT_BIN" ls-remote --get-url "$1" 2>/dev/null || true
}

run_startup
[[ "$RUN_EXIT" -eq 0 && ! -s "$GH_LOG" ]] \
    && check "true"  "no token: git's helper is left alone" \
    || check "false" "no token: git's helper is left alone" "exit=$RUN_EXIT"$'\n'"$(cat "$GH_LOG")"

run_startup GH_TOKEN=t0ken
[[ "$RUN_EXIT" -eq 0 && "$(cat "$GH_LOG")" == "gh auth setup-git --hostname github.com" ]] \
    && check "true"  "GH_TOKEN: git's github.com helper is set to gh" \
    || check "false" "GH_TOKEN: git's github.com helper is set to gh" "exit=$RUN_EXIT"$'\n'"$(cat "$GH_LOG")"

run_startup GITHUB_TOKEN=t0ken
[[ "$RUN_EXIT" -eq 0 && "$(cat "$GH_LOG")" == "gh auth setup-git --hostname github.com" ]] \
    && check "true"  "GITHUB_TOKEN: git's github.com helper is set to gh" \
    || check "false" "GITHUB_TOKEN: git's github.com helper is set to gh" "exit=$RUN_EXIT"$'\n'"$(cat "$GH_LOG")"

run_startup GH_ENTERPRISE_TOKEN=t0ken GH_HOST=ghe.example.com
[[ "$RUN_EXIT" -eq 0 && "$(cat "$GH_LOG")" == "gh auth setup-git --hostname ghe.example.com" ]] \
    && check "true"  "GH_ENTERPRISE_TOKEN + GH_HOST: the enterprise host's helper is set to gh" \
    || check "false" "GH_ENTERPRISE_TOKEN + GH_HOST: the enterprise host's helper is set to gh" "exit=$RUN_EXIT"$'\n'"$(cat "$GH_LOG")"

run_startup GH_ENTERPRISE_TOKEN=t0ken
[[ "$RUN_EXIT" -eq 0 && ! -s "$GH_LOG" ]] \
    && check "true"  "GH_ENTERPRISE_TOKEN without GH_HOST: nothing to point git at" \
    || check "false" "GH_ENTERPRISE_TOKEN without GH_HOST: nothing to point git at" "exit=$RUN_EXIT"$'\n'"$(cat "$GH_LOG")"

run_startup GH_TOKEN=t0ken STUB_GH_FAIL=1
[[ "$RUN_EXIT" -eq 0 ]] \
    && check "true"  "a failing gh auth setup-git does not fail the booth's start" \
    || check "false" "a failing gh auth setup-git does not fail the booth's start" "exit=$RUN_EXIT"

# ---- SSH remotes: rewritten to HTTPS only when the booth has no ssh ----

RUN_PATH="$PATH_NOSSH"
run_startup GH_TOKEN=t0ken
want=$'git@github.com:\nssh://git@github.com/'
got_scp="$(resolved git@github.com:o/r.git)"
got_url="$(resolved ssh://git@github.com/o/r.git)"
[[ "$RUN_EXIT" -eq 0 && "$(insteadof github.com)" == "$want" \
   && "$got_scp" == "https://github.com/o/r.git" && "$got_url" == "https://github.com/o/r.git" ]] \
    && check "true"  "GH_TOKEN, no ssh: git reaches git@github.com remotes over HTTPS" \
    || check "false" "GH_TOKEN, no ssh: git reaches git@github.com remotes over HTTPS" \
         "exit=$RUN_EXIT"$'\n'"insteadOf: $(insteadof github.com)"$'\n'"scp-form -> $got_scp"$'\n'"url-form -> $got_url"

run_startup GH_TOKEN=t0ken
[[ "$RUN_EXIT" -eq 0 && "$(insteadof github.com)" == "$want" ]] \
    && check "true"  "a restart does not add the rewrite twice" \
    || check "false" "a restart does not add the rewrite twice" "$(insteadof github.com)"

RUN_PATH="$PATH_WITHSSH"
run_startup GH_TOKEN=t0ken
[[ "$RUN_EXIT" -eq 0 && -z "$(insteadof github.com)" \
   && "$(resolved git@github.com:o/r.git)" == "git@github.com:o/r.git" ]] \
    && check "true"  "GH_TOKEN with ssh: SSH remotes stay SSH" \
    || check "false" "GH_TOKEN with ssh: SSH remotes stay SSH" "$(insteadof github.com)"

RUN_PATH="$PATH_NOSSH"
run_startup
[[ "$RUN_EXIT" -eq 0 && ! -e "$WORK/home-$TEST_NUM/.gitconfig" ]] \
    && check "true"  "no token, no ssh: ~/.gitconfig is not touched" \
    || check "false" "no token, no ssh: ~/.gitconfig is not touched" \
         "$(cat "$WORK/home-$TEST_NUM/.gitconfig" 2>/dev/null)"

run_startup GH_ENTERPRISE_TOKEN=t0ken GH_HOST=ghe.example.com
[[ "$RUN_EXIT" -eq 0 && -z "$(insteadof github.com)" \
   && "$(resolved git@ghe.example.com:o/r.git)" == "https://ghe.example.com/o/r.git" ]] \
    && check "true"  "GH_ENTERPRISE_TOKEN + GH_HOST, no ssh: only the enterprise host is rewritten" \
    || check "false" "GH_ENTERPRISE_TOKEN + GH_HOST, no ssh: only the enterprise host is rewritten" \
         "github.com: $(insteadof github.com)"$'\n'"ghe: $(insteadof ghe.example.com)"

$ALL_PASSED
