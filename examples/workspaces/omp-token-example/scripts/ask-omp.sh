#!/usr/bin/env bash
# Run one non-interactive omp task and print the answer.
# Usage: scripts/ask-omp.sh ["prompt"]
set -euo pipefail

if [ -z "${ANTHROPIC_OAUTH_TOKEN:-}" ]; then
    echo "No omp login found: ANTHROPIC_OAUTH_TOKEN is not set in this booth." >&2
    echo "Create one with 'claude setup-token' on the host, export it there, then restart the booth." >&2
    echo "See README.md." >&2
    exit 1
fi

prompt="${1:-}"
[ -n "$prompt" ] || prompt="List the files in the current directory and describe in two sentences what this project is."

# -p: print the answer and exit (no interactive session).
# --no-session: do not save this one-off as a session.
# --tools: read-only tools only, so the example cannot change anything.
omp -p --no-session --tools read,grep,glob "$prompt" </dev/null
