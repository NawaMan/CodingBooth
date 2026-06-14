#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0

Examples:
  $0                         # install grok CLI (no version pinning needed)

Notes:
- Installs a lightweight 'grok' command-line client for xAI Grok models.
- Talks directly to the official xAI API (https://api.x.ai).
- Authenticates via the XAI_API_KEY environment variable (recommended).
- Also checks common credential file locations on startup.
- See: https://x.ai/ and https://console.x.ai/
USAGE
}

[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends curl ca-certificates jq
rm -rf /var/lib/apt/lists/*

STARTUP_FILE="/usr/share/startup.d/70-cb-grok--startup.sh"
PROFILE_FILE="/etc/profile.d/70-cb-grok--profile.sh"

# Install the grok wrapper CLI (self-contained bash + curl + jq)
cat > /usr/local/bin/grok <<'GROKCLI'
#!/usr/bin/env bash
# grok — lightweight CLI for xAI Grok (https://x.ai)
# Copyright 2025-2026 : Nawa Manusitthipol (for CodingBooth packaging)
set -euo pipefail

# Resolve API key (env var takes precedence, then common file locations)
API_KEY="${XAI_API_KEY:-${XAI_KEY:-}}"

if [[ -z "$API_KEY" ]]; then
    for f in \
        "$HOME/.config/xai/key" \
        "$HOME/.config/xai/api_key" \
        "$HOME/.xai/key" \
        "$HOME/.xai/api_key" \
        "$HOME/.xai/credentials" \
        "/etc/cb-home-seed/.config/xai/key" \
        "/etc/cb-home-seed/.xai/key"
    do
        if [[ -f "$f" ]]; then
            API_KEY="$(tr -d ' \t\n\r' < "$f" 2>/dev/null || true)"
            [[ -n "$API_KEY" ]] && break
        fi
    done
fi

MODEL="${GROK_MODEL:-grok-3-latest}"
API_URL="https://api.x.ai/v1/chat/completions"

usage() {
    cat <<EOF
grok — chat with Grok (xAI)

Usage:
  grok "your prompt here"          # one-shot question / coding help
  echo "explain this" | grok       # read prompt from stdin
  grok                             # interactive REPL (type 'exit' or Ctrl-D to quit)

Environment:
  XAI_API_KEY     Your xAI API key (recommended)
  GROK_MODEL      Model to use (default: grok-3-latest)
                  Common values: grok-3-latest, grok-2-latest, grok-2-1212

Get a key: https://console.x.ai/

Inside a CodingBooth you can also pass it at launch:
  XAI_API_KEY=sk-... booth
  # or put it in .booth/.env and it will be picked up
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

if [[ -z "$API_KEY" ]]; then
    echo "❌ No xAI API key found." >&2
    echo "" >&2
    echo "Set it one of these ways:" >&2
    echo "  export XAI_API_KEY=sk-..." >&2
    echo "  XAI_API_KEY=sk-... grok \"hello\"" >&2
    echo "" >&2
    echo "Or store it in a file (will be picked up automatically):" >&2
    echo "  mkdir -p ~/.config/xai && echo 'sk-xxx' > ~/.config/xai/key" >&2
    echo "" >&2
    echo "To make it available inside the booth, add to .booth/.env or use:" >&2
    echo "  booth --env XAI_API_KEY=sk-..." >&2
    echo "" >&2
    usage >&2
    exit 1
fi

call_api() {
    local prompt="$1"
    local payload
    payload=$(jq -nc \
        --arg model "$MODEL" \
        --arg content "$prompt" \
        '{
            model: $model,
            messages: [ { role: "user", content: $content } ],
            temperature: 0.7,
            max_tokens: 4096
        }')

    curl -sS "$API_URL" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $API_KEY" \
        -d "$payload" | \
    jq -r '
        if .error then
            "ERROR: " + (.error.message // .error | tostring)
        else
            .choices[0].message.content // "No response"
        end
    '
}

# One-shot mode (argument or stdin)
if [[ $# -ge 1 ]]; then
    call_api "$*"
    exit 0
fi

# If stdin is not a tty, treat as one-shot from pipe
if [[ ! -t 0 ]]; then
    prompt="$(cat)"
    [[ -n "$prompt" ]] && call_api "$prompt"
    exit 0
fi

# Interactive REPL
echo "grok (${MODEL}) — xAI Grok chat  (type 'exit' or Ctrl-D to quit)"
echo "────────────────────────────────────────────────────────────────"
while IFS= read -r -p "grok> " line; do
    line="${line#"${line%%[![:space:]]*}"}"   # trim leading
    line="${line%"${line##*[![:space:]]}"}"   # trim trailing
    [[ -z "$line" ]] && continue
    [[ "$line" == "exit" || "$line" == "quit" ]] && break
    echo
    call_api "$line"
    echo
done
echo "bye 👋"
GROKCLI

chmod 755 /usr/local/bin/grok

# ---- Create startup file (runs on container start as the coder user) ----
cat > "${STARTUP_FILE}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Grok (xAI) startup script
# Seeds credentials from cb-home-seed into the user's home if present.
# The grok CLI will automatically discover keys in:
#   ~/.config/xai/key
#   ~/.xai/key
#   and respects XAI_API_KEY env var.

SEED_DIR="/etc/cb-home-seed"

copy_if_missing() {
    local src="$1"
    local dst="$2"
    if [[ -e "$src" && ! -e "$dst" ]]; then
        mkdir -p "$(dirname "$dst")"
        cp -a "$src" "$dst"
        # tighten perms on key-like files
        if [[ "$dst" == *key* || "$dst" == *credential* || "$dst" == *api* ]]; then
            chmod 600 "$dst" 2>/dev/null || true
        fi
    fi
}

# Seed possible credential/config locations (no-clobber)
copy_if_missing "$SEED_DIR/.config/xai"          "$HOME/.config/xai"
copy_if_missing "$SEED_DIR/.xai"                 "$HOME/.xai"

# If a top-level key file exists in seed but not yet in home config, help populate
if [[ -f "$SEED_DIR/xai.key" && ! -f "$HOME/.config/xai/key" ]]; then
    mkdir -p "$HOME/.config/xai"
    cp -a "$SEED_DIR/xai.key" "$HOME/.config/xai/key"
    chmod 600 "$HOME/.config/xai/key" 2>/dev/null || true
fi
EOF
chmod 755 "${STARTUP_FILE}"

# ---- Create profile file ----
cat > "${PROFILE_FILE}" <<'EOF'
# Profile: Grok CLI (xAI)
#   grok "explain bubble sort in Rust"
#   grok                 # start interactive chat
#   GROK_MODEL=grok-2-latest grok "quick question"
#
# Set your key via env (or store in ~/.config/xai/key):
#   export XAI_API_KEY=sk-...
EOF
chmod 644 "${PROFILE_FILE}"

echo ""
echo "✅ Grok CLI installed."
echo "   Binary:  /usr/local/bin/grok"
echo "   Startup: ${STARTUP_FILE}"
echo "   Profile: ${PROFILE_FILE}"
echo ""
echo "Usage examples:"
echo "  grok \"write a python one-liner to sum a list\""
echo "  grok                           # interactive"
echo "  GROK_MODEL=grok-2-latest grok \"hello\""
echo ""
echo "=== Authentication ==="
echo "Set XAI_API_KEY (preferred):"
echo "  export XAI_API_KEY=sk-..."
echo "  # or pass at launch: XAI_API_KEY=sk-... booth"
echo ""
echo "Or store in a file (auto-detected by the grok CLI):"
echo "  mkdir -p ~/.config/xai && echo 'sk-xxx' > ~/.config/xai/key"
echo ""
echo "To seed credentials from your host machine, add to .booth/config.toml:"
echo ""
echo '  run-args = ['
echo '      # xAI / Grok credentials'
echo '      "-v", "~/.config/xai:/etc/cb-home-seed/.config/xai:ro",'
echo '      "-v", "~/.xai:/etc/cb-home-seed/.xai:ro"'
echo '  ]'
echo ""
