#!/usr/bin/env bash
# Run one non-interactive Grok task and print the answer.
# Usage: scripts/ask-grok.sh ["prompt"]
set -euo pipefail

if [ -z "${XAI_API_KEY:-}" ] && [ ! -f "$HOME/.grok/auth.json" ]; then
    echo "No Grok login found: ~/.grok/auth.json is missing in this booth." >&2
    echo "Run 'grok login' on the host, then restart the booth." >&2
    echo "See README.md." >&2
    exit 1
fi

prompt="${1:-}"
[ -n "$prompt" ] || prompt="List the files in the current directory and describe in two sentences what this project is."

# -p: one turn, print the answer and exit (no interactive session).
# --tools: read-only built-in tools only, so the example cannot change anything.
# --output-format json + jq: print only the answer, not Grok's running commentary.
grok -p "$prompt" --tools read_file,grep,list_dir --output-format json </dev/null | jq -r '.text'
