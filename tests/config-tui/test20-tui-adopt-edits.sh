#!/bin/bash
# TUI: a booth edited outside booth config, with an edit booth config could have
# written itself, is read back rather than treated as hand-written:
#
#   open     no hand-written warning — it asks about the edit made outside booth
#            config instead, naming what it read back; nothing is written by viewing
#   Ctrl+S   names the comments a save removes, and waits
#   Enter    saves: the edit survives, the comment does not, no .bak
#
# The --no-tui side is tests/config/engine/test124.
source "$(dirname "$0")/tui-helpers--source.sh"

begin

run() { "$@" >> "$log" 2>&1 ; }
configtoml="$prj/.booth/config.toml"

run "$BOOTH_BIN" config "$prj" --no-tui --select go --templates-path "$TEMPLATES_PATH"
if [[ ! -f "$configtoml" ]]; then
    skip "seed step did not produce a .booth/config.toml"
fi
printf '# the team is in Bangkok\ntimezone = "Asia/Bangkok"\n' >> "$configtoml"
cp "$configtoml" "$prj/edited-config.toml"

# ── 0) Opening shows no hand-written warning, and writes nothing ─────
run-tui frame

assert-frame "changed outside booth config"  "opening says the booth was edited outside booth config"
assert-frame "+ --set timezone=Asia/Bangkok" "...and names the edit it read back"

TEST_COUNT=$((TEST_COUNT + 1))
_print_test_header "a readable edit raises no hand-written warning"
if grep -q "hand-written" "$prj/frame.clean.txt"; then _fail "the startup warning appeared"; else _pass; fi

TEST_COUNT=$((TEST_COUNT + 1))
_print_test_header "viewing leaves the edited file untouched"
if cmp -s "$configtoml" "$prj/edited-config.toml"; then _pass; else _fail "config.toml was modified"; fi

# ── 1) Ctrl+S names the comments it would remove ─────────────────────
DISMISS_WARNING=true   # OK on the opening question
run-tui frame 'Ctrl+S' 'Sleep 1s'

assert-frame "Comments will be removed"   "Ctrl+S asks before removing comments"
assert-frame "# the team is in Bangkok"   "the dialog lists the comment"

TEST_COUNT=$((TEST_COUNT + 1))
_print_test_header "backing out leaves the edited file untouched"
if cmp -s "$configtoml" "$prj/edited-config.toml"; then _pass; else _fail "config.toml was modified"; fi

# ── 2) Enter saves: the edit survives, the comment does not ──────────
run-tui raw 'Ctrl+S' 'Sleep 1s' 'Enter' 'Sleep 3s'

assert-file-contains     "$configtoml" 'timezone = "Asia/Bangkok"'   "the edited setting survives the save"
assert-file-contains     "$configtoml" "--set timezone=Asia/Bangkok" "the edit is recorded in the header"
assert-file-not-contains "$configtoml" "the team is in Bangkok"      "the comment is removed, as warned"
assert-file-missing      "$configtoml.bak"                          "nothing was destroyed, so no .bak was made"

finally
