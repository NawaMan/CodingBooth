#!/usr/bin/env bash
# 031 — when there are zero rc files, shell-config falls back to printing the
#       booth() function so the user can `eval "$(./booth shell-config)"`.
source "$(dirname "$0")/_lib.sh"

LAST_OUTPUT=$(run_in_container <<'BASH'
set -e
cp /booth/booth ./booth
rm -f ~/.bashrc ~/.zshrc ~/.bash_profile ~/.profile
./booth shell-config 2>&1 || true
BASH
)

assert_contains "$LAST_OUTPUT" "No shell config files found"
assert_contains "$LAST_OUTPUT" 'eval "$(./booth shell-config)"'
# The fallback output should include the raw function on stdout so the eval works.
assert_contains "$LAST_OUTPUT" "booth()"
assert_contains "$LAST_OUTPUT" "# booth function v6"
pass
