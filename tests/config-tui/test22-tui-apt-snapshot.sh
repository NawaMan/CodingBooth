#!/bin/bash
# TUI: the Apt Snapshot field shows the snapshot the booth already freezes apt to,
# keeps it on a save that does not touch it, moves it with TODAY, and clearing it
# turns the freeze off — written as an empty `env APT_SNAPSHOT=` line that the
# next save keeps, rather than re-stamping today's date.
#
# Left switches to the Config tab; Down×8 lands on Apt Snapshot. The stops are
# Booth Version, Variant, Port, Offset Base, Name, Container Engine, Templates
# Version, Apt Snapshot — adding a field above it means bumping every count below.
source "$(dirname "$0")/tui-helpers--source.sh"

begin

# CB_APT_SNAPSHOT would override the booth's own line and hide the behaviour under test.
unset CB_APT_SNAPSHOT

run() { "$@" >> "$log" 2>&1 ; }
echo "=== seed existing .booth via --no-tui ===" >> "$log"
run "$BOOTH_BIN" config "$prj" --no-tui --select go --templates-path "$TEMPLATES_PATH" \
    --apt-snapshot 20250101T000000Z

boothfile="$prj/.booth/Boothfile"
if ! grep -qx "env APT_SNAPSHOT=20250101T000000Z" "$boothfile" 2>/dev/null; then
    skip "seed step did not produce a Boothfile frozen to 20250101T000000Z"
fi

to_field=('Left' 'Sleep 500ms' 'Down' 'Down' 'Down' 'Down' 'Down' 'Down' 'Down' 'Down' 'Sleep 400ms')

run-tui frame "${to_field[@]}"
assert-frame "Apt Snapshot:" "The cursor lands on the Apt Snapshot field"
assert-frame "20250101T000000Z" "The field is preloaded with the booth's own snapshot"

run-tui save "${to_field[@]}"
assert-file-contains "$boothfile" "env APT_SNAPSHOT=20250101T000000Z" \
    "A save that does not touch the field keeps the snapshot"

# A value apt cannot use is refused in the field itself: Enter keeps the edit open
# with the reason showing, and Ctrl+S saves nothing.
run-tui frame "${to_field[@]}" \
    'Enter' 'Sleep 400ms' \
    'Backspace 20' 'Sleep 300ms' \
    'Type "2026-01-01"' 'Sleep 400ms' \
    'Enter' 'Sleep 400ms'
assert-frame '✗ "2026-01-01" is not a snapshot id' "A malformed id is refused with the reason"
assert-frame "Esc puts back 20250101T000000Z" "The refusal says what Esc goes back to"

# Ctrl+S from inside the edit: the TUI must still be up, showing the reason. Had
# it saved, the frame would be the shell it exited to.
run-tui frame "${to_field[@]}" \
    'Enter' 'Sleep 400ms' \
    'Backspace 20' 'Sleep 300ms' \
    'Type "2026-01-01"' 'Sleep 400ms' \
    'Ctrl+S' 'Sleep 800ms'
assert-frame '✗ "2026-01-01" is not a snapshot id' "Ctrl+S with a malformed id stays in the TUI"
assert-file-contains "$boothfile" "env APT_SNAPSHOT=20250101T000000Z" \
    "Ctrl+S with a malformed id saves nothing"

today="$(date -u +%Y%m%d)T000000Z"
run-tui save "${to_field[@]}" \
    'Enter' 'Sleep 400ms' \
    'Backspace 20' 'Sleep 300ms' \
    'Type "TODAY"' 'Sleep 400ms' \
    'Enter' 'Sleep 400ms'
assert-file-contains "$boothfile" "env APT_SNAPSHOT=${today}" "TODAY moves the snapshot to today"

run-tui save "${to_field[@]}" \
    'Enter' 'Sleep 400ms' \
    'Backspace 20' 'Sleep 300ms' \
    'Enter' 'Sleep 400ms'
assert-line "$boothfile" "env APT_SNAPSHOT=" "" "Clearing the field turns the freeze off"

run-tui save "${to_field[@]}"
assert-line "$boothfile" "env APT_SNAPSHOT=" "" "The next save keeps the freeze off"

finally
