#!/bin/bash
# --add-expose/--remove-expose, --add-env/--remove-env, and --add-mount/--remove-mount
# edit an existing booth's run-args in place — keyed on the container port, the
# env KEY, and the container path respectively — instead of the plain flag's
# whole-list replace.
source "$(dirname "$0")/../test-helpers--source.sh"

begin
config="$prj/.booth/config.toml"

function has() { grep -qF -- "${2}" "${1}" 2>/dev/null ; }
function check() {
    TEST_COUNT=$((TEST_COUNT + 1))
    local ok="${1}" message="${2}" width=64
    local label="${message} "
    local pad_len=$((width - ${#label}))
    if (( pad_len < 3 )); then pad_len=3; fi
    local pad
    pad=$(printf '%*s' "$pad_len" '' | tr ' ' '.')
    local test="Test ${TEST_COUNT}: ${label}"
    echo -n "${test}${pad} "
    if [[ "${ok}" == "0" ]]; then
        PASS_COUNT=$((PASS_COUNT + 1))
        echo -e "\033[32mPASSED\033[0m"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAIL_TESTS+=("${test}")
        echo -e "\033[31mFAILED\033[0m"
    fi
}

# ---------------------------------------------------------------------------
# --add-expose adds a new mapping, keeping the existing one.
# ---------------------------------------------------------------------------
run booth config $prj --no-tui --select "go" --expose 8080
run booth config $prj --no-tui --overwrite --add-expose 9090
has "$config" '"--publish", "8080:8080",' ; check $? "the original expose survives"
has "$config" '"--publish", "9090:9090"'  ; check $? "the added expose is present"

# ---------------------------------------------------------------------------
# --add-expose for a container port already exposed updates that mapping's
# host port in place, rather than binding the container port twice.
# ---------------------------------------------------------------------------
run rm -Rf $prj/.booth
run booth config $prj --no-tui --select "go" --expose 8080
run booth config $prj --no-tui --overwrite --add-expose 9000:8080
! has "$config" '"8080:8080"'               ; check $? "the old host port is gone"
has   "$config" '"--publish", "9000:8080"'  ; check $? "the new mapping replaces it, keyed on the container port"

# ---------------------------------------------------------------------------
# --remove-expose drops one mapping, keeping the rest.
# ---------------------------------------------------------------------------
run rm -Rf $prj/.booth
run booth config $prj --no-tui --select "go" --expose 8080 --expose 9090
run booth config $prj --no-tui --overwrite --remove-expose 8080
! has "$config" '"8080:8080"'              ; check $? "8080 was removed"
has   "$config" '"--publish", "9090:9090"' ; check $? "9090 survives"

# ---------------------------------------------------------------------------
# --add-env adds a new var, keeping the existing one.
# ---------------------------------------------------------------------------
run rm -Rf $prj/.booth
run booth config $prj --no-tui --select "go" --env FOO=1
run booth config $prj --no-tui --overwrite --add-env BAR=2
has "$config" '"--env", "FOO=1",' ; check $? "the original env survives"
has "$config" '"--env", "BAR=2"'  ; check $? "the added env is present"

# ---------------------------------------------------------------------------
# --add-env for an existing KEY updates its value in place, rather than
# emitting the key twice.
# ---------------------------------------------------------------------------
run rm -Rf $prj/.booth
run booth config $prj --no-tui --select "go" --env FOO=1
run booth config $prj --no-tui --overwrite --add-env FOO=2
! has "$config" '"FOO=1"'          ; check $? "the old value is gone"
has   "$config" '"--env", "FOO=2"' ; check $? "the new value replaces it, keyed on the KEY"

# ---------------------------------------------------------------------------
# --remove-env drops one var by KEY, keeping the rest.
# ---------------------------------------------------------------------------
run rm -Rf $prj/.booth
run booth config $prj --no-tui --select "go" --env FOO=1 --env BAR=2
run booth config $prj --no-tui --overwrite --remove-env FOO
! has "$config" '"FOO=1"'          ; check $? "FOO was removed"
has   "$config" '"--env", "BAR=2"' ; check $? "BAR survives"

# ---------------------------------------------------------------------------
# --add-mount adds a new mount, keeping the existing one.
# ---------------------------------------------------------------------------
run rm -Rf $prj/.booth
run booth config $prj --no-tui --select "go" --mount /data:/app/data
run booth config $prj --no-tui --overwrite --add-mount /logs:/app/logs
has "$config" '"--volume", "/data:/app/data",' ; check $? "the original mount survives"
has "$config" '"--volume", "/logs:/app/logs"'  ; check $? "the added mount is present"

# ---------------------------------------------------------------------------
# --add-mount for a container path already mounted updates the host side in
# place, rather than mounting the container path twice.
# ---------------------------------------------------------------------------
run rm -Rf $prj/.booth
run booth config $prj --no-tui --select "go" --mount /data:/app/data
run booth config $prj --no-tui --overwrite --add-mount /other:/app/data
! has "$config" '"/data:/app/data"'              ; check $? "the old host path is gone"
has   "$config" '"--volume", "/other:/app/data"' ; check $? "the new mount replaces it, keyed on the container path"

# ---------------------------------------------------------------------------
# --remove-mount drops one mount by container path, keeping the rest.
# ---------------------------------------------------------------------------
run rm -Rf $prj/.booth
run booth config $prj --no-tui --select "go" --mount /data:/app/data --mount /logs:/app/logs
run booth config $prj --no-tui --overwrite --remove-mount /app/data
! has "$config" '"/data:/app/data"'             ; check $? "/app/data was removed"
has   "$config" '"--volume", "/logs:/app/logs"' ; check $? "/app/logs survives"

# ---------------------------------------------------------------------------
# A plain flag combined with its own --remove-* is refused: the plain flag
# already replaces the whole list, so there is nothing left to remove from.
# Shared logic (mergeKeyedList) backs --expose/--env/--mount alike; --expose
# stands in for all three here.
# ---------------------------------------------------------------------------
run rm -Rf $prj/.booth
run booth config $prj --no-tui --select "go" --expose 8080
if run booth config $prj --no-tui --overwrite --expose 9090 --remove-expose 8080; then ok=1; else ok=0; fi
check $ok "combining --expose with --remove-expose is refused"

finally
