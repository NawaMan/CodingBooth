#!/usr/bin/env bash
# Run one non-interactive Codex task and print the answer.
# Usage: scripts/ask-codex.sh ["prompt"]
set -euo pipefail

if [ -z "${CODEX_ACCESS_TOKEN:-}${CODEX_API_KEY:-}" ] && [ ! -f "$HOME/.codex/auth.json" ]; then
    echo "No Codex login found: ~/.codex/auth.json is missing in this booth." >&2
    echo "Run 'codex login' on the host, then restart the booth." >&2
    echo "See README.md." >&2
    exit 1
fi

prompt="${1:-}"
[ -n "$prompt" ] || prompt="List the files in the current directory and describe in two sentences what this project is."

# exec: run one task, print the answer and exit (no interactive session).
# --sandbox danger-full-access: Codex's own sandbox needs Linux namespaces
#     (bubblewrap), which a booth container does not provide, so with it on
#     not even `ls` can run. The booth is the sandbox here instead.
# --output-last-message: print only the final answer; the transcript is kept
#     aside and shown only if Codex fails.
out="$(mktemp)"
log="$(mktemp)"
trap 'rm -f "$out" "$log"' EXIT
if ! codex exec --sandbox danger-full-access --skip-git-repo-check \
        --output-last-message "$out" "$prompt" </dev/null >"$log" 2>&1; then
    cat "$log" >&2
    exit 1
fi
printf '%s\n' "$(cat "$out")"
