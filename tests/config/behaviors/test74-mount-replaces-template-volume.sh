#!/bin/bash
# A template's named volume is per booth, and a user's --mount on the same
# container path replaces it.
#
# The service templates used to mount one machine-wide volume (booth-pgdata), and
# booth config had no way to swap it: --mount added a second entry beside the
# template's -v (a duplicate mount point Docker refuses), --remove-mount only saw
# the user's own mounts, and --set run-args wrote a second `run-args =` key that
# made config.toml unreadable. Each of those is pinned here.
source "$(dirname "$0")/../test-helpers--source.sh"

begin
config="$prj/.booth/config.toml"

# has <file> <substring> — 0 when the file contains it
function has() { grep -qF -- "${2}" "${1}" 2>/dev/null ; }

# check <0-if-ok> <message>
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
# The template's volume is named per booth
# ---------------------------------------------------------------------------
run booth config $prj --no-tui --overwrite --select "postgresql"
has "$config" '"-v", "booth-pgdata-{name}:/var/lib/postgresql"' ; check $? "postgresql mounts booth-pgdata-{name}"

# ---------------------------------------------------------------------------
# A user mount on the same path replaces it, and survives a reconfigure
# ---------------------------------------------------------------------------
run booth config $prj --no-tui --overwrite --add-mount "myproj-pgdata:/var/lib/postgresql"
has   "$config" '"--volume", "myproj-pgdata:/var/lib/postgresql"' ; check $? "--add-mount puts the user's volume on the path"
! has "$config" 'booth-pgdata-{name}'                         ; check $? "...and drops the template's volume on that path"

run booth config $prj --no-tui --overwrite
has   "$config" '"--volume", "myproj-pgdata:/var/lib/postgresql"' ; check $? "a plain reconfigure keeps the user's volume"
! has "$config" 'booth-pgdata-{name}'                         ; check $? "...and does not bring the template's back"

# ---------------------------------------------------------------------------
# Removing the user mount brings the template's back
# ---------------------------------------------------------------------------
run booth config $prj --no-tui --overwrite --remove-mount "/var/lib/postgresql"
has   "$config" '"-v", "booth-pgdata-{name}:/var/lib/postgresql"' ; check $? "--remove-mount restores the template's volume"
! has "$config" 'myproj-pgdata'                                    ; check $? "...and the user's volume is gone"

# ---------------------------------------------------------------------------
# --set run-args merges into the one run-args key
# ---------------------------------------------------------------------------
run booth config $prj --no-tui --overwrite --set run-args=--cap-add --set run-args=SYS_PTRACE
[[ "$(grep -c '^run-args' "$config")" == "1" ]] ; check $? "--set run-args leaves exactly one run-args key"
has "$config" '"--cap-add", "SYS_PTRACE"'        ; check $? "...holding the --set entries"
has "$config" 'booth-pgdata-{name}'           ; check $? "...next to the template's entries"

finally
