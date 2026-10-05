#!/bin/bash
# TUI: a booth edited outside booth config, whose edits booth config can read
# back, opens on a question rather than a warning. It names the files and what
# the edits became:
#
#   OK (Enter)        accept them and carry on into the TUI
#   Cancel (→ Enter)  quit with nothing changed, to review the files first
#
# When only .booth/.generated disagrees with the files, OK also rewrites it.
source "$(dirname "$0")/tui-helpers--source.sh"

begin

run() { "$@" >> "$log" 2>&1 ; }
manifest="$prj/.booth/.generated"

run "$BOOTH_BIN" config "$prj" --no-tui --select go --templates-path "$TEMPLATES_PATH"
if [[ ! -f "$manifest" ]]; then
    skip "seed step did not produce a .booth/.generated"
fi
sed -i 's/=sha256:[0-9a-f]*/=sha256:0000/' "$manifest"
cp "$manifest" "$prj/stale-generated"

# ── 0) Opening asks, and warns about nothing hand-written ────────────
run-tui frame

assert-frame "changed outside booth config" "opening asks about the edit made outside booth config"
assert-frame ".booth/Boothfile"             "the question names the files"
assert-frame "If you did not expect this"   "Cancel is offered to review the files first"
TEST_COUNT=$((TEST_COUNT + 1))
_print_test_header "no hand-written warning for a readable edit"
if grep -q "did not make" "$prj/frame.clean.txt"; then _fail "the hand-written warning appeared"; else _pass; fi

# ── 1) Cancel quits, leaving everything as it was ────────────────────
run-tui raw 'Right' 'Sleep 300ms' 'Enter' 'Sleep 1s'

assert-frame "Cancelled — nothing was changed" "Cancel quits and says so"
TEST_COUNT=$((TEST_COUNT + 1))
_print_test_header "Cancel leaves .booth/.generated untouched"
if cmp -s "$manifest" "$prj/stale-generated"; then _pass; else _fail ".generated was modified"; fi

# ── 2) OK accepts, rewriting the stale fingerprint, without saving ───
run-tui raw 'Enter' 'Sleep 500ms' 'Ctrl+E' 'Sleep 500ms' 'Enter' 'Sleep 800ms'

assert-file-not-contains "$manifest" "sha256:0000" "OK rewrites the stale fingerprint"
TEST_COUNT=$((TEST_COUNT + 1))
_print_test_header "after OK the booth no longer counts as edited"
if "$BOOTH_BIN" config "$prj" --no-tui --dryrun --templates-path "$TEMPLATES_PATH" 2>&1 | grep -q "edited outside"; then
    _fail "the booth still reads as edited"
else
    _pass
fi

finally
