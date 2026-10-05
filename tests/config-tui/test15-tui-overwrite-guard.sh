#!/bin/bash
# TUI: saving regenerates .booth/Boothfile and config.toml from scratch, so it
# destroys anything a human wrote in them. When that is about to happen, Ctrl+S
# must not save — it raises a dialog offering three numbered choices:
#
#   1                   apply: replace them, keeping a .bak
#   2 (Enter)           keep the hand-written files, write the generated content
#                       beside them as <name>.new to compare (destroys nothing)
#   3 + "overwrite"     replace them with no backup
#   Esc                 back out, touching nothing
#
# The CLI equivalents are --beside and --overwrite (tests/config/engine/test68).
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

assert-frame "have changes booth config did not make" "warns on open, before anything is configured"
assert-frame ".booth/Boothfile"                       "the startup warning names the file"
assert-frame "nothing is touched until you save"      "...but lets the user go in and look around"

# ── 1) Ctrl+S raises the dialog instead of saving ────────────────────
DISMISS_WARNING=true
run-tui frame 'Ctrl+S' 'Sleep 1s'

assert-frame "Your booth files have changes booth config did not make" "Ctrl+S warns instead of saving"
assert-frame "You are at risk of losing"    "the dialog leads with the risk"
assert-frame ".booth/Boothfile"             "the dialog names the file at risk"
assert-frame "Apply, and back up your files" "choice 1: apply with a backup"
assert-frame ".booth/Boothfile.bak"         "the dialog names the backup"
assert-frame ".booth/Boothfile.new"         "choice 2: write the generated content beside it"
assert-frame "Overwrite, with no backup"    "choice 3: overwrite outright"

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

# ── 3) Choice 1 replaces, and keeps a backup ──────────────────────────
rm -f "$boothfile.new"
run-tui save-apply 'Sleep 500ms'

assert-file-contains "$boothfile" "# Configured by:"   "choice 1 lets the replace through"
assert-file-not-contains "$boothfile" "install apt ripgrep" "the booth was regenerated from the selection"
assert-file-contains "$prj/.booth/Boothfile.bak" "install apt ripgrep" "the hand-edit is preserved in Boothfile.bak"

# ── 4) Choice 3 + the word replaces with no backup ───────────────────
rm -f "$boothfile.bak"
echo 'install apt ripgrep' >> "$boothfile"
run-tui save-confirm 'Sleep 500ms'

assert-file-contains "$boothfile" "# Configured by:"   "typing the word lets the overwrite through"
assert-file-not-contains "$boothfile" "install apt ripgrep" "the booth was regenerated from the selection"
assert-file-missing  "$boothfile.bak" "an outright overwrite keeps no backup"

finally
