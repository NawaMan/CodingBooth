#!/bin/bash
# TUI: saving regenerates .booth/Boothfile and config.toml from scratch, so it
# destroys anything a human wrote in them. When that is about to happen, Ctrl+S
# must not save — it raises a dialog offering both ways out:
#
#   Enter               keep the hand-written files, write the generated content
#                       beside them as <name>.new to merge (destroys nothing)
#   type "overwrite"    replace them, keeping a .bak
#   Esc                 back out, touching nothing
#
# The CLI equivalents are --beside and --overwrite (tests/config/test68).
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

# ── 0) The TUI says so up front, before any time is invested ─────────
# Discovering this only at save time means having configured the whole booth
# without knowing the result could not simply be written out.
run-tui frame

assert-frame "This booth contains hand-written files" "warns on open, before anything is configured"
assert-frame ".booth/Boothfile"                       "the startup warning names the file"
assert-frame "nothing is touched until you save"      "...but lets the user go in and look around"

# ── 1) Ctrl+S raises the dialog instead of saving ────────────────────
DISMISS_WARNING=true
run-tui frame 'Ctrl+S' 'Sleep 1s'

assert-frame "THESE FILES ARE HAND-WRITTEN" "Ctrl+S warns instead of saving"
assert-frame ".booth/Boothfile"             "the dialog names the file at risk"
assert-frame ".booth/Boothfile.new"         "the dialog offers to write the generated content beside it"
assert-frame "overwrite"                    "the dialog states the word to type to replace instead"

TEST_COUNT=$((TEST_COUNT + 1))
_print_test_header "backing out leaves the hand-edit untouched"
if cmp -s "$boothfile" "$prj/edited-boothfile"; then _pass; else _fail "Boothfile was modified despite not confirming"; fi

# ── 2) Enter takes the safe path: keep mine, write theirs as .new ────
run-tui save-beside 'Sleep 500ms'

TEST_COUNT=$((TEST_COUNT + 1))
_print_test_header "Enter keeps the hand-written Boothfile byte-identical"
if cmp -s "$boothfile" "$prj/edited-boothfile"; then _pass; else _fail "the hand-written Boothfile was modified"; fi

assert-file-contains "$boothfile.new" "# Configured by:" "the generated content lands as Boothfile.new"
assert-file-missing  "$boothfile.bak" "nothing was destroyed, so no .bak was made"

# ── 3) Typing the word replaces instead, and keeps a backup ──────────
run-tui save-confirm 'Sleep 500ms'

assert-file-contains "$boothfile" "# Configured by:"   "typing the word lets the overwrite through"
assert-file-not-contains "$boothfile" "install apt ripgrep" "the booth was regenerated from the selection"
assert-file-contains "$prj/.booth/Boothfile.bak" "install apt ripgrep" "the hand-edit is preserved in Boothfile.bak"

finally
