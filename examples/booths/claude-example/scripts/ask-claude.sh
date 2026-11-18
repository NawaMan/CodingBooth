#!/usr/bin/env bash
# Run one non-interactive Claude Code task and print the answer.
# Usage: scripts/ask-claude.sh ["prompt"]
set -euo pipefail

if [ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" ] && [ ! -f "$HOME/.claude/.credentials.json" ]; then
    echo "No Claude login found: ~/.claude/.credentials.json is missing in this booth." >&2
    echo "Run 'claude' and '/login' on the host, then restart the booth." >&2
    echo "See README.md." >&2
    exit 1
fi

prompt="${1:-}"
[ -n "$prompt" ] || prompt="List the files in the current directory and describe in two sentences what this project is."

# -p: print the answer and exit (no interactive session).
# --allowedTools: read-only tools only, so the example cannot change anything.
claude -p "$prompt" --allowedTools "Read" "Glob" "Grep" "Bash(ls:*)" </dev/null
