# Shared helpers for the share-example in-booth tests (sourced, not run).

fail() { echo "FAIL: $*"; exit 1; }

# Not 3001/8080, so a `just dev` the user left running is not in the way.
export NOTES_API_PORT=13001 NOTES_WEB_PORT=18080
# What a Console UI pane already has in its environment (start-ttyd-split exports
# its own API_PORT=<booth port>+7). The app must not pick these up: it once did,
# and `just dev` tried to bind the console's port.
export API_PORT=10007 WEB_PORT=10000
LOG_DIR="$(mktemp -d)"
PIDS=()
cleanup() {
    for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null || true; done
    pkill -f "node --watch (api|web)/server.js" -U "$(id -u)" 2>/dev/null || true
    rm -rf "$LOG_DIR"
}
trap cleanup EXIT

wait_http() {   # wait_http <url> — up to 15s
    for _ in $(seq 1 75); do
        curl -fsS -o /dev/null "$1" 2>/dev/null && return 0
        sleep 0.2
    done
    return 1
}

# start_app — ./dev.sh (API + front end) on the test ports, as `just dev` would.
start_app() {
    "$HOME/code/dev.sh" >"$LOG_DIR/dev.log" 2>&1 &
    PIDS+=($!)
    wait_http "http://localhost:$NOTES_API_PORT/api/health" || { cat "$LOG_DIR/dev.log"; fail "API did not start on :$NOTES_API_PORT"; }
    wait_http "http://localhost:$NOTES_WEB_PORT/"           || { cat "$LOG_DIR/dev.log"; fail "front end did not start on :$NOTES_WEB_PORT"; }
}

# share <cmd> <port> [args] — start a share in the background, print its public URL.
share() {
    local cmd="$1" port="$2" log; shift 2
    log="$LOG_DIR/share-$cmd-$port.log"
    "$cmd" "$port" "$@" >"$log" 2>&1 &
    PIDS+=($!)
    local url=""
    for _ in $(seq 1 120); do
        url="$(grep -oE 'Shared: https://[^ ]+' "$log" | head -1 | cut -d' ' -f2 || true)"
        [[ -n "$url" ]] && { echo "$url"; return 0; }
        sleep 0.5
    done
    cat "$log" >&2
    return 1
}

# fetch_until <url> <grep-pattern> [curl args] — retries ~90s: a fresh tunnel's
# DNS name can take a while to resolve.
fetch_until() {
    local url="$1" pattern="$2"; shift 2
    for _ in $(seq 1 45); do
        if curl -fsS --max-time 10 "$@" "$url" 2>/dev/null | grep -q "$pattern"; then
            return 0
        fi
        sleep 2
    done
    return 1
}
