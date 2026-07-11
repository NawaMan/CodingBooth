#!/bin/bash
# TUI: saving regenerates .booth/Boothfile and config.toml from scratch, so it
# destroys anything a human wrote in them. When that is about to happen, Ctrl+S
# must not save — it must raise a confirmation the user has to type their way
# through. Esc backs out leaving the files untouched.
#
# The CLI equivalent is --overwrite (tests/config/test68).
source "$(dirname "$0")/tui-helpers--source.sh"

begin

run() { "$@" >> "$log" 2>&1 ; }
boothfile="$prj/.booth/Boothfile"

# Seed a normal booth, then hand-edit it. The "# Configured by:" header survives
# the edit, so only the content hash reveals that a human has been here.
run "$BOOTH_BIN" config "$prj" --no-tui --select go --templates-path "$TEMPLATES_PATH"
if [[ ! -f "$boothfile" ]]; then
    skip "seed step did not produce a .booth/Boothfile"
fi
echo 'install apt ripgrep' >> "$boothfile"
cp "$boothfile" "$prj/edited-boothfile"

# ── 1) Ctrl+S raises the confirmation instead of saving ──────────────
run-tui frame 'Ctrl+S' 'Sleep 1s'

assert-frame "THIS WILL DESTROY HAND-WRITTEN FILES" "Ctrl+S warns instead of saving"
assert-frame ".booth/Boothfile"                     "the warning names the file at risk"
assert-frame "overwrite"                            "the warning states the word to type"

TEST_COUNT=$((TEST_COUNT + 1))
_print_test_header "backing out leaves the hand-edit untouched"
if cmp -s "$boothfile" "$prj/edited-boothfile"; then _pass; else _fail "Boothfile was modified despite not confirming"; fi

# ── 2) Typing the word saves, and keeps a backup ─────────────────────
run-tui save-confirm 'Sleep 500ms'

assert-file-contains "$boothfile" "# Configured by:"   "typing the word lets the save through"
assert-file-not-contains "$boothfile" "install apt ripgrep" "the booth was regenerated from the selection"
assert-file-contains "$prj/.booth/Boothfile.bak" "install apt ripgrep" "the hand-edit is preserved in Boothfile.bak"

finally
