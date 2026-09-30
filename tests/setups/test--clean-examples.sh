#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: build/clean-examples.sh removes example assets and nothing else
#
# The script exists to replace `docker system prune -a --volumes`, so the bug that
# matters is a pattern that reaches past the examples — a look-alike project
# (go-examplex), a non-example project (myproj), a shared service volume
# (booth-pgdata), a running booth or the image it uses.
#
# $BOOTH_ENGINE points at a fake engine: it serves canned listings (already
# narrowed the way the real engine's --filter would narrow them) and records every
# removal. What is asserted is the script's own selection and ordering, not the
# engine's filters — those were checked against a real daemon when it was written.
#
# Example names come from the real examples/workspaces/ tree: go-example,
# js-example and server-example-2 (a name that itself ends in -<digits>).
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CLEAN="$REPO_ROOT/build/clean-examples.sh"

ALL_PASSED=true
TEST_NUM=0

report() {  # report <ok> <desc> [detail-lines...]
    local ok="$1" desc="$2"; shift 2
    TEST_NUM=$((TEST_NUM + 1))
    if [ "$ok" = true ]; then
        print_test_result "true" "$0" "$TEST_NUM" "$desc"
    else
        print_test_result "false" "$0" "$TEST_NUM" "$desc"
        for line in "$@"; do echo "      $line"; done
        ALL_PASSED=false
    fi
}

FAKE_DIR="$(mktemp -d)"
trap 'rm -rf "$FAKE_DIR"' EXIT

# --- Fake engine --------------------------------------------------------------

# id|name|state|cb.code-path|cb.role|cb.parent — every cb.managed container.
cat > "$FAKE_DIR/containers" <<'EOF'
c1|go-example|exited|/x/examples/workspaces/go-example||
c2|go-example-10000-dind|exited||sidecar|go-example-10000
c3|myproj|exited|/x/myproj||
c4|js-example|running|/y/worktree/z/examples/workspaces/js-example||
c5|myproj-dind|exited||sidecar|myproj
c6|go-examplex-dind|exited||sidecar|go-examplex
c7|server-example-2|created|/x/examples/workspaces/server-example-2||
EOF
# Images a running container uses (`ps --format {{.Image}}`).
echo "codingbooth-local:js-example-base-1.0" > "$FAKE_DIR/running-images"
# ref|size — what `images --filter reference=codingbooth-local` returns.
cat > "$FAKE_DIR/images" <<'EOF'
codingbooth-local:go-example-base-1.0|1GB
codingbooth-local:server-example-2-desktop-xfce-1.0|9GB
codingbooth-local:go-examplex-base-1.0|1GB
codingbooth-local:myproj-base-1.0|1GB
codingbooth-local:js-example-base-1.0|1GB
EOF
cat > "$FAKE_DIR/volumes" <<'EOF'
cb-home-go-example
cb-home-go-example-10000
cb-home-go-examplex
cb-home-myproj
booth-pgdata
EOF
cat > "$FAKE_DIR/networks" <<'EOF'
bridge
go-example-10000-net
go-example-10000-egress-net
go-example-net
myproj-10000-net
EOF

cat > "$FAKE_DIR/engine" <<'EOF'
#!/bin/bash
D="$(dirname "$0")"
args=" $* "
fail_on() { [[ -f "$D/fail" ]] && grep -qxF "$1" "$D/fail"; }
case "$1" in
    info)
        [[ -f "$D/down" ]] && exit 1; exit 0 ;;
    ps)
        if [[ "$args" == *'{{.Image}}'* ]]; then
            cat "$D/running-images"
        elif [[ "$args" == *' -a '* ]]; then
            cat "$D/containers"
        else
            awk -F'|' '$3 == "running" { print $2 "|" $4 }' "$D/containers"
        fi ;;
    images)  cat "$D/images" ;;
    volume)  if [[ "$2" == ls ]]; then cat "$D/volumes"
             else fail_on "$3" && exit 1; echo "volume rm $3" >> "$D/log"; fi ;;
    network) if [[ "$2" == ls ]]; then cat "$D/networks"
             else fail_on "$3" && exit 1; echo "network rm $3" >> "$D/log"; fi ;;
    rm|rmi)  fail_on "$2" && exit 1; echo "$1 $2" >> "$D/log" ;;
    image|builder)
             echo "$1 $2" >> "$D/log"; echo "Total reclaimed space: 0B" ;;
    *)       echo "fake engine: unexpected: $*" >&2; exit 2 ;;
esac
EOF
chmod +x "$FAKE_DIR/engine"
export BOOTH_ENGINE="$FAKE_DIR/engine"

reset_log() { : > "$FAKE_DIR/log"; rm -f "$FAKE_DIR/fail" "$FAKE_DIR/down"; }
removed() { sort "$FAKE_DIR/log"; }

# --- 1. Dry run lists the example assets and removes nothing --------------------

reset_log
OUT="$("$CLEAN" --dry-run 2>&1)" && RC=0 || RC=$?
if [[ $RC -eq 0 && ! -s "$FAKE_DIR/log" && "$OUT" == *"cb-home-go-example"* && "$OUT" == *"Dry run"* ]]; then
    report true "--dry-run lists example assets and removes nothing"
else
    report false "--dry-run lists example assets and removes nothing" "rc=$RC" "$OUT" "log: $(removed)"
fi

# --- 2. --yes removes exactly the example set, containers first ---------------

EXPECTED="$(sort <<'EOF'
rm c1
rm c2
rm c7
rmi codingbooth-local:go-example-base-1.0
rmi codingbooth-local:server-example-2-desktop-xfce-1.0
volume rm cb-home-go-example
volume rm cb-home-go-example-10000
network rm go-example-10000-net
network rm go-example-10000-egress-net
EOF
)"
reset_log
OUT="$("$CLEAN" --yes 2>&1)" && RC=0 || RC=$?
if [[ $RC -eq 0 && "$(removed)" == "$EXPECTED" ]]; then
    report true "--yes removes exactly the example assets"
else
    report false "--yes removes exactly the example assets" "rc=$RC" \
        "expected:" "$EXPECTED" "got:" "$(removed)" "output:" "$OUT"
fi

# Containers go before images, volumes and networks, or those stay "in use".
FIRST_NON_RM="$(grep -n -v '^rm ' "$FAKE_DIR/log" | head -n1 | cut -d: -f1)"
LAST_RM="$(grep -n '^rm ' "$FAKE_DIR/log" | tail -n1 | cut -d: -f1)"
if [[ -n "$FIRST_NON_RM" && -n "$LAST_RM" && $LAST_RM -lt $FIRST_NON_RM ]]; then
    report true "containers are removed before what they use"
else
    report false "containers are removed before what they use" "$(cat "$FAKE_DIR/log")"
fi

# --- 3. The running example booth is reported, not touched --------------------

if [[ "$OUT" == *"Skipped — running example booths"* && "$OUT" == *"  js-example"* ]]; then
    report true "a running example booth is reported as skipped"
else
    report false "a running example booth is reported as skipped" "$OUT"
fi

# --- 4. Cross-project prunes only run when asked --------------------------------

if ! grep -qE '^(image|builder) ' "$FAKE_DIR/log"; then
    report true "no dangling-image or build-cache prune without the flags"
else
    report false "no dangling-image or build-cache prune without the flags" "$(removed)"
fi

reset_log
"$CLEAN" --yes --dangling --build-cache >/dev/null 2>&1 || true
if grep -qx 'image prune' "$FAKE_DIR/log" && grep -qx 'builder prune' "$FAKE_DIR/log"; then
    report true "--dangling and --build-cache run their prunes"
else
    report false "--dangling and --build-cache run their prunes" "$(removed)"
fi

# --- 5. One refusal does not stop the rest ----------------------------------------

reset_log
echo "codingbooth-local:go-example-base-1.0" > "$FAKE_DIR/fail"
OUT="$("$CLEAN" --yes 2>&1)" && RC=0 || RC=$?
if [[ $RC -eq 0 && "$OUT" == *"kept    image codingbooth-local:go-example-base-1.0"* ]] \
        && grep -qx 'network rm go-example-10000-egress-net' "$FAKE_DIR/log"; then
    report true "a refused removal is reported as kept and the rest continue"
else
    report false "a refused removal is reported as kept and the rest continue" "rc=$RC" "$OUT"
fi

# --- 6. Without a terminal it refuses unless --yes --------------------------------

reset_log
OUT="$("$CLEAN" < /dev/null 2>&1)" && RC=0 || RC=$?
if [[ $RC -ne 0 && ! -s "$FAKE_DIR/log" && "$OUT" == *"pass --yes"* ]]; then
    report true "no terminal and no --yes: refuses and removes nothing"
else
    report false "no terminal and no --yes: refuses and removes nothing" "rc=$RC" "$OUT"
fi

# --- 7. An unreachable engine is an error, not an empty clean --------------------

reset_log
touch "$FAKE_DIR/down"
OUT="$("$CLEAN" --yes 2>&1)" && RC=0 || RC=$?
if [[ $RC -ne 0 && ! -s "$FAKE_DIR/log" && "$OUT" == *"not reachable"* ]]; then
    report true "an unreachable engine exits non-zero"
else
    report false "an unreachable engine exits non-zero" "rc=$RC" "$OUT"
fi

if [ "$ALL_PASSED" = true ]; then
    exit 0
else
    exit 1
fi
