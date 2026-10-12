#!/bin/bash
# --set merges into an existing booth key by key: a key given now replaces that
# key's recorded value (a list key included), every other recorded key is kept,
# and the header records the whole value so a regenerate reproduces the file.
# Value lists split on commas; argv lists (run-args) never do. --unset drops a
# key, and an --unset or --remove-* that matches nothing is refused with nothing
# written.
source "$(dirname "$0")/../test-helpers--source.sh"

begin
boothfile="$prj/.booth/Boothfile"
config="$prj/.booth/config.toml"
errors="$prj/errors.txt"

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

# The booth is regenerated from its header alone (no flags) and must come back
# byte-identical: the header holds the whole configuration.
function round-trips() {
    cp "$boothfile" "$prj/Boothfile.before"
    cp "$config" "$prj/config.toml.before"
    booth config $prj --no-tui --overwrite >/dev/null 2>&1 \
        && cmp -s "$boothfile" "$prj/Boothfile.before" \
        && cmp -s "$config" "$prj/config.toml.before"
}

# ---------------------------------------------------------------------------
# A --set on a reconfigure keeps every other recorded key. It used to replace
# the whole baseline, so setting one key silently dropped timezone here.
# ---------------------------------------------------------------------------
run booth config $prj --no-tui --select "go" --set egress-allowlist=a.com --set timezone=Asia/Bangkok
run booth config $prj --no-tui --overwrite --set egress-allowlist=b.com
has   "$config" 'timezone = "Asia/Bangkok"'         ; check $? "a key not given now is kept"
has   "$config" 'egress-allowlist = ["b.com"]'      ; check $? "the list key is replaced, not appended"
has   "$boothfile" '--set timezone=Asia/Bangkok'    ; check $? "the kept key stays in the header"
round-trips                                          ; check $? "the booth round-trips from its header"

# ---------------------------------------------------------------------------
# A list key read back from config.toml (cache-dirs) is replaced too, and the
# header records the value — it used to append, with the old value missing
# from the header.
# ---------------------------------------------------------------------------
run rm -Rf $prj/.booth
run booth config $prj --no-tui --select "go" --set cache-dirs=home/coder/one
run booth config $prj --no-tui --overwrite --set cache-dirs=home/coder/two
! has "$config" 'home/coder/one'                    ; check $? "the old cache dir is gone"
has   "$config" 'cache-dirs = ["home/coder/two"]'   ; check $? "the new cache dir replaces it"
has   "$boothfile" '--set cache-dirs=home/coder/two' ; check $? "the header records it"
round-trips                                          ; check $? "the booth round-trips from its header"

# ---------------------------------------------------------------------------
# A comma separates the values of a value list, and the header records one
# --set per value. An argv list keeps the comma inside its token.
# ---------------------------------------------------------------------------
run rm -Rf $prj/.booth
run booth config $prj --no-tui --select "go" --set "egress-allowlist=c.com, d.com" --set run-args=--label --set run-args=a=1,b=2
has "$boothfile" '--set egress-allowlist=c.com --set egress-allowlist=d.com' ; check $? "the header records one --set per value"
has "$config" '"c.com",'                             ; check $? "c.com is its own item"
has "$config" '"d.com"'                              ; check $? "d.com is its own item"
has "$config" '"a=1,b=2"'                            ; check $? "a run-args token keeps its comma"
round-trips                                          ; check $? "the booth round-trips from its header"

# ---------------------------------------------------------------------------
# --unset drops a recorded key, from the header and config.toml alike.
# ---------------------------------------------------------------------------
run rm -Rf $prj/.booth
run booth config $prj --no-tui --select "go" --set timezone=Asia/Bangkok --set cache-dirs=home/coder/one --set dind
run booth config $prj --no-tui --overwrite --unset timezone --unset cache-dirs
! has "$config" 'timezone'                           ; check $? "timezone is gone from config.toml"
! has "$config" 'home/coder/one'                     ; check $? "the cache dir is gone from config.toml"
! has "$boothfile" '--set timezone'                  ; check $? "timezone is gone from the header"
has   "$boothfile" '--set dind'                      ; check $? "the other key is kept"

# ---------------------------------------------------------------------------
# An --unset of a key the booth does not hold is refused, and nothing is
# written. So is an unknown key, and --set with --unset of the same key.
# ---------------------------------------------------------------------------
cp "$boothfile" "$prj/Boothfile.before"
if booth config $prj --no-tui --overwrite --unset timezone 2> "$errors" >/dev/null; then ok=1; else ok=0; fi
check $ok "unsetting a key the booth does not hold is refused"
has "$errors" '--unset timezone: the existing booth does not set it' ; check $? "the error names the key"
cmp -s "$boothfile" "$prj/Boothfile.before"          ; check $? "the booth was not rewritten"
if booth config $prj --no-tui --overwrite --unset timezon 2> "$errors" >/dev/null; then ok=1; else ok=0; fi
check $ok "an unknown --unset key is refused"
has "$errors" 'Did you mean "timezone"'              ; check $? "the error suggests the real key"
if booth config $prj --no-tui --overwrite --set dind --unset dind >/dev/null 2>&1; then ok=1; else ok=0; fi
check $ok "--set and --unset of one key are refused together"

# ---------------------------------------------------------------------------
# --remove-env KEY=VALUE drops the entry when the value matches, and is
# refused — showing the recorded entry — when it does not. It used to match
# nothing either way and carry on.
# ---------------------------------------------------------------------------
run rm -Rf $prj/.booth
run booth config $prj --no-tui --select "go" --env FOO=1 --env BAR=2
cp "$config" "$prj/config.toml.before"
if booth config $prj --no-tui --overwrite --remove-env FOO=2 2> "$errors" >/dev/null; then ok=1; else ok=0; fi
check $ok "--remove-env with a different value is refused"
has "$errors" '(it has "FOO=1")'                     ; check $? "the error shows the recorded entry"
cmp -s "$config" "$prj/config.toml.before"           ; check $? "the booth was not rewritten"
run booth config $prj --no-tui --overwrite --remove-env FOO=1
! has "$config" 'FOO=1'                              ; check $? "--remove-env FOO=1 drops FOO=1"
has   "$config" '"--env", "BAR=2"'                   ; check $? "BAR survives"

finally
