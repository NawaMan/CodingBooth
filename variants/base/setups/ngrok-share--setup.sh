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

Installs /usr/local/bin/ngrok-share: one command that shares a port in the
booth on a temporary public https URL through ngrok. Needs ngrok (setup ngrok)
and an ngrok authtoken (NGROK_AUTHTOKEN, or ngrok config add-authtoken).
USAGE
}

[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

cat > /usr/local/bin/ngrok-share <<'SCRIPT'
#!/usr/bin/env bash
# ngrok-share — share a port in this booth on a temporary public URL.
# Installed by ngrok-share--setup.sh (the ngrok+share extension).
set -uo pipefail

BOOTH_FRONT_DOOR_PORT=10000

usage() {
    cat <<'USAGE'
Usage: ngrok-share <port|url> [--ok-booth] [--verbose] [-- <ngrok http args>...]

Share a server running in this booth on a temporary https://<id>.ngrok-free.app
URL (or your plan's domain). The URL works until you press Ctrl+C, and anyone
who has it can reach the server.

Needs an ngrok authtoken: NGROK_AUTHTOKEN in the environment (the ngrok+share
extension passes it from the host) or `ngrok config add-authtoken <token>`.

Arguments:
  port|url      Port of the server in the booth (8080), or a full origin URL
                (http://localhost:3000, https://localhost:8443)

Options:
  --ok-booth    Allow sharing the booth's own port (10000). That port is the
                booth's terminal / IDE: sharing it hands a shell to anyone
                with the URL. Refused without this flag.
  --verbose     Show ngrok's own log lines, not only the URL and errors
  --            Pass the rest to `ngrok http` as is (--basic-auth, --url, ...)

Examples:
  ngrok-share 8080
  ngrok-share 8080 -- --basic-auth 'me:a-long-password'
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

command -v ngrok >/dev/null 2>&1 || {
    echo "Error: ngrok is not installed in this booth (select the ngrok template)." >&2
    exit 1
}

if [[ -z "${NGROK_AUTHTOKEN:-}" ]]; then
    cfg="${XDG_CONFIG_HOME:-$HOME/.config}/ngrok/ngrok.yml"
    if ! grep -qs '^[[:space:]]*authtoken:' "$cfg" "$HOME/.ngrok2/ngrok.yml"; then
        echo "Error: ngrok has no authtoken." >&2
        echo "       Get one at https://dashboard.ngrok.com/get-started/your-authtoken, then either" >&2
        echo "         - start the booth with NGROK_AUTHTOKEN set on the host (ngrok+share passes it), or" >&2
        echo "         - run: ngrok config add-authtoken <token>" >&2
        exit 1
    fi
fi

# bash /dev/tcp, not ss: the base image has no iproute2.
if [[ "$URL" =~ ^https?://(localhost|127\.0\.0\.1)(:|/|$) ]] && ! (exec 3<>"/dev/tcp/127.0.0.1/$PORT") 2>/dev/null; then
    echo "⚠️  Nothing is listening on port $PORT yet — the URL will answer an error until it does." >&2
fi

echo "Opening an ngrok tunnel to $URL ..."
# --log stdout: the URL is read from the log, so this works without a TTY too
# and the output looks the same as cloudflared-share's.
ngrok http "$URL" --log stdout --log-format logfmt "${EXTRA[@]}" 2>&1 | {
    shown=false
    while IFS= read -r line; do
        if [[ "$shown" == false && "$line" == *"started tunnel"* && "$line" =~ url=(https?://[^[:space:]]+) ]]; then
            shown=true
            echo ""
            echo "🌐 Shared: ${BASH_REMATCH[1]}  ->  $URL"
            echo "   Anyone with this URL can reach it. Press Ctrl+C to stop sharing."
            echo "   Requests: http://localhost:4040 (ngrok's inspector, inside the booth)"
            echo ""
        # Without --verbose: the one fatal log line, and anything that is not a log line.
        elif [[ "$VERBOSE" == true || "$line" == *"lvl=crit"* || "$line" != t=* ]]; then
            echo "$line"
        fi
    done
}
exit "${PIPESTATUS[0]}"
SCRIPT
chmod 755 /usr/local/bin/ngrok-share

echo "✅ ngrok-share installed."
cat <<'EON'
ℹ️ Ready to use:
- Share a server in the booth:  ngrok-share 8080
- Stop sharing:                 Ctrl+C
EON
