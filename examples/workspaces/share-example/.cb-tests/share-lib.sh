# Shared helpers for the share-example in-booth tests (sourced, not run).

fail() { echo "FAIL: $*"; exit 1; }

PORT=18080      # not 8080, so a `just serve` the user left running is not in the way
LOG_DIR="$(mktemp -d)"
PIDS=()
cleanup() {
    for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null || true; done
    pkill -f "caddy file-server --listen :$PORT" 2>/dev/null || true
    rm -rf "$LOG_DIR"
}
trap cleanup EXIT

start_site() {
    caddy file-server --listen ":$PORT" --root "$HOME/code/site" >"$LOG_DIR/caddy.log" 2>&1 &
    PIDS+=($!)
    for _ in $(seq 1 50); do
        curl -fsS -o /dev/null "http://localhost:$PORT/" 2>/dev/null && return 0
        sleep 0.2
    done
    cat "$LOG_DIR/caddy.log"; fail "caddy did not start on :$PORT"
}

# wait_for_url <log> — print the URL from the "🌐 Shared:" line, waiting up to 60s.
wait_for_url() {
    local log="$1" url=""
    for _ in $(seq 1 120); do
        url="$(grep -oE 'Shared: https://[^ ]+' "$log" | head -1 | cut -d' ' -f2 || true)"
        [[ -n "$url" ]] && { echo "$url"; return 0; }
        sleep 0.5
    done
    cat "$log" >&2
    return 1
}

# fetch_marker <url> [curl args] — the public URL serves this site's page (retries
# up to ~90s: a fresh tunnel's DNS name can take a while to resolve).
fetch_marker() {
    local url="$1"; shift
    for _ in $(seq 1 45); do
        if curl -fsS --max-time 10 "$@" "$url/" 2>/dev/null | grep -q 'share-example is live'; then
            return 0
        fi
        sleep 2
    done
    return 1
}
