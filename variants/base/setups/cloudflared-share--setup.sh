#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.1.0

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0

Installs /usr/local/bin/cloudflared-share: one command that shares a port in
the booth on a temporary public https URL through a Cloudflare quick tunnel.
Needs cloudflared (setup cloudflared) — no Cloudflare account.
USAGE
}

[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

cat > /usr/local/bin/cloudflared-share <<'SCRIPT'
#!/usr/bin/env bash
# cloudflared-share — share a port in this booth on a temporary public URL.
# Installed by cloudflared-share--setup.sh (the cloudflared+share extension).
set -uo pipefail

BOOTH_FRONT_DOOR_PORT=10000

usage() {
    cat <<'USAGE'
Usage: cloudflared-share <port|url> [--ok-booth] [--verbose] [-- <cloudflared args>...]

Share a server running in this booth on a temporary https://<words>.trycloudflare.com
URL (a Cloudflare quick tunnel; no account needed). The URL works until you
press Ctrl+C, and anyone who has it can reach the server.

Arguments:
  port|url      Port of the server in the booth (8080), or a full origin URL
                (http://localhost:3000, https://localhost:8443)

Options:
  --ok-booth    Allow sharing the booth's own port (10000). That port is the
                booth's terminal / IDE: sharing it hands a shell to anyone
                with the URL. Refused without this flag.
  --verbose     Show cloudflared's own log lines, not only the URL and errors
  --            Pass the rest to `cloudflared tunnel` as is

Examples:
  cloudflared-share 8080
  cloudflared-share http://localhost:5173
USAGE
}

TARGET=""; OK_BOOTH=false; VERBOSE=false; EXTRA=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --ok-booth) OK_BOOTH=true; shift ;;
        --verbose|-v) VERBOSE=true; shift ;;
        --) shift; EXTRA=("$@"); break ;;
        -*) echo "Error: unknown option: $1" >&2; usage >&2; exit 2 ;;
        *)  [[ -z "$TARGET" ]] || { echo "Error: one port or URL only" >&2; exit 2; }
            TARGET="$1"; shift ;;
    esac
done
[[ -n "$TARGET" ]] || { usage >&2; exit 2; }

if [[ "$TARGET" =~ ^[0-9]+$ ]]; then
    PORT="$TARGET"; URL="http://localhost:$PORT"
elif [[ "$TARGET" =~ ^https?://[^/:]+(:([0-9]+))?(/.*)?$ ]]; then
    URL="$TARGET"; PORT="${BASH_REMATCH[2]}"
    [[ -n "$PORT" ]] || { [[ "$TARGET" == https* ]] && PORT=443 || PORT=80; }
else
    echo "Error: '$TARGET' is not a port or an http(s):// URL" >&2; exit 2
fi

if [[ "$PORT" == "$BOOTH_FRONT_DOOR_PORT" && "$OK_BOOTH" != true ]]; then
    echo "Error: port $PORT is this booth's own terminal / IDE." >&2
    echo "       Sharing it gives anyone with the URL a shell in the booth." >&2
    echo "       Pass --ok-booth if that is what you mean." >&2
    exit 1
fi

command -v cloudflared >/dev/null 2>&1 || {
    echo "Error: cloudflared is not installed in this booth (select the cloudflared template)." >&2
    exit 1
}

# bash /dev/tcp, not ss: the base image has no iproute2.
if [[ "$URL" =~ ^https?://(localhost|127\.0\.0\.1)(:|/|$) ]] && ! (exec 3<>"/dev/tcp/127.0.0.1/$PORT") 2>/dev/null; then
    echo "⚠️  Nothing is listening on port $PORT yet — the URL will answer 502 until it does." >&2
fi

echo "Opening a Cloudflare quick tunnel to $URL ..."
# --no-autoupdate: the binary lives in /usr/local/bin and is the image's to update.
cloudflared tunnel --no-autoupdate --url "$URL" "${EXTRA[@]}" 2>&1 | {
    shown=false
    while IFS= read -r line; do
        if [[ "$shown" == false && "$line" =~ (https://[-a-z0-9]+\.trycloudflare\.com) ]]; then
            shown=true
            echo ""
            echo "🌐 Shared: ${BASH_REMATCH[1]}  ->  $URL"
            echo "   Anyone with this URL can reach it. Press Ctrl+C to stop sharing."
            echo ""
        # Without --verbose: error log lines, and anything that is not a log line.
        elif [[ "$VERBOSE" == true || "$line" == *" ERR "* || ! "$line" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]; then
            echo "$line"
        fi
    done
}
exit "${PIPESTATUS[0]}"
SCRIPT
chmod 755 /usr/local/bin/cloudflared-share

echo "✅ cloudflared-share installed."
cat <<'EON'
ℹ️ Ready to use:
- Share a server in the booth:  cloudflared-share 8080
- Stop sharing:                 Ctrl+C
EON
