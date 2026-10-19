#!/usr/bin/env bash
# Run one non-interactive omp task and print the answer.
# Usage: scripts/ask-omp.sh ["prompt"]
set -euo pipefail

# omp can log in to many providers, so there is no single file to check for;
# omp itself says what is missing.

prompt="${1:-}"
[ -n "$prompt" ] || prompt="List the files in the current directory and describe in two sentences what this project is."

# -p: print the answer and exit (no interactive session).
# --no-session: do not save this one-off as a session.
# --tools: read-only tools only, so the example cannot change anything.
omp -p --no-session --tools read,grep,glob "$prompt" </dev/null
