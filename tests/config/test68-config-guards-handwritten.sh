#!/bin/bash
# `booth config` regenerates .booth/Boothfile and config.toml from scratch, so a
# reconfigure destroys whatever a human wrote in them. It must refuse rather than
# clobber; --overwrite is the explicit way through, and keeps a .bak.
#
# The case that forces content hashing rather than trusting the "# Configured by:"
# header: a file that WAS generated and then hand-edited still carries the header,
# so the header alone cannot tell "still ours" from "someone edited this".
source "$(dirname "$0")/test-helpers--source.sh"

boothfile="$prj/.booth/Boothfile"
configtoml="$prj/.booth/config.toml"

out=""   # stdout+stderr of the last config run
code=0

# config — run `booth config`, capturing output and exit code without aborting.
function config() {
    out="$(booth config "$@" 2>&1)"; code=$?
    { echo ""; echo "> booth config $*"; echo "$out"; echo "(exit ${code})"; } >> $log
}

# check <0-if-ok> <message>
function check() {
    TEST_COUNT=$((TEST_COUNT + 1))
    local ok="${1}"
    local message="${2}"
    local width=64
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
        echo "  output: ${out}"
    fi
}

# says <substring> — 0 when the last config run mentioned it
function says() {
    grep -q -- "${1}" <<< "$out"
}

begin
mkdir -p "$prj/.booth"

# ---------------------------------------------------------------------------
# 1) A hand-written Boothfile (no header, never generated) must not be clobbered.
# ---------------------------------------------------------------------------
original="$prj/original-boothfile"   # byte-exact copy to compare against
printf 'setup go\ninstall apt ripgrep\nrun echo "my own booth"\n' > "$boothfile"
cp "$boothfile" "$original"

config $prj --no-tui --select go
[[ $code -ne 0 ]] ; check $? "refuses to overwrite a hand-written Boothfile"
says "Refusing to overwrite hand-written files" ; check $? "explains why it refused"
cmp -s "$boothfile" "$original" ; check $? "hand-written Boothfile left byte-identical"

# ---------------------------------------------------------------------------
# 2) --overwrite is the explicit way through, and keeps a backup.
# ---------------------------------------------------------------------------
config $prj --no-tui --overwrite --select go
[[ $code -eq 0 ]] ; check $? "--overwrite proceeds"
grep -q "^# Configured by:" "$boothfile" ; check $? "Boothfile was regenerated"
cmp -s "$boothfile.bak" "$original" ; check $? "original preserved as Boothfile.bak"

# ---------------------------------------------------------------------------
# 3) Our own freshly-generated output is not treated as hand-written.
# ---------------------------------------------------------------------------
config $prj --no-tui --select go
if says "Refusing to overwrite hand-written files"; then r=1; else r=0; fi
check $r "regenerating our own untouched output raises no drift warning"

# ---------------------------------------------------------------------------
# 4) The case the header cannot catch: generated, THEN hand-edited.
#    The "# Configured by:" line survives the edit — only the hash reveals it.
# ---------------------------------------------------------------------------
run booth config $prj --no-tui --overwrite --select go
echo 'install apt ripgrep' >> "$boothfile"
edited="$prj/edited-boothfile"
cp "$boothfile" "$edited"

config $prj --no-tui --select go
[[ $code -ne 0 ]] ; check $? "catches an edit to a file booth config itself generated"
grep -q "^# Configured by:" "$boothfile" ; check $? "...even though the generated header is still present"
cmp -s "$boothfile" "$edited" ; check $? "the hand-edit is left intact"

# ---------------------------------------------------------------------------
# 5) config.toml is guarded on the same terms.
# ---------------------------------------------------------------------------
printf 'variant = "base"\n' > "$configtoml"
config $prj --no-tui --select go
says "config.toml" ; check $? "a hand-written config.toml is guarded too"

# ---------------------------------------------------------------------------
# 6) --beside: keep the hand-written file, write the generated one alongside.
#    This is the way through that loses nothing — the user merges the two.
# ---------------------------------------------------------------------------
run rm -Rf $prj ; mkdir -p "$prj/.booth"
printf 'setup go\ninstall apt ripgrep\n' > "$boothfile"
cp "$boothfile" "$original"

config $prj --no-tui --beside --select go
[[ $code -eq 0 ]] ; check $? "--beside proceeds"
cmp -s "$boothfile" "$original" ; check $? "the hand-written Boothfile is untouched"
grep -q "^# Configured by:" "$boothfile.new" ; check $? "the generated content lands as Boothfile.new"
[[ ! -f "$boothfile.bak" ]] ; check $? "nothing was destroyed, so no .bak was made"

# The kept file must still be guarded next time — writing .new must not bless it
# as ours, or the next run would clobber it silently.
config $prj --no-tui --select go
says "Refusing to overwrite hand-written files" ; check $? "the kept file is still guarded on the next run"

finally
