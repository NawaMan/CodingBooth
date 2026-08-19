#!/bin/bash
# TUI: the cursor moves inside a text field — Left/Right put the next character
# where the cursor is, not at the end, and the caret is drawn where it will land.
#
# Left and Right are the tab switchers everywhere else in the TUI, so an open
# edit has to claim them; and the caret used to be pinned to the end of the
# field, which made a moved cursor invisible.
#
# (Home/End move the cursor too — they are covered by the unit tests in
# cli/src/pkg/boothinit/tui/textcursor_test.go, because VHS has no key for them.)
source "$(dirname "$0")/tui-helpers--source.sh"

begin

# Left switches to the Config tab; Down×5 lands on Name (a free-text field).
# The stops are Booth Version, Variant, Port, Offset Base, Name — "Offset Base"
# was added between Port and Name, so Down×4 now stops there instead and the
# frame reads "Offset Base:" rather than "Name:". Adding a field above Name means
# bumping both counts below.
#
# The cursor is a reversed cell, not a glyph, so it costs the value no columns and
# the captured frame — which VHS dumps as plain text, styling and all discarded —
# must read exactly "bth" with the cursor sitting invisibly on the "t". Where the
# reverse actually lands is asserted in caretText's unit tests, and the value below
# proves the model agrees with it.
run-tui frame \
    'Left' 'Sleep 500ms' \
    'Down' 'Down' 'Down' 'Down' 'Down' 'Sleep 400ms' \
    'Enter' 'Sleep 400ms' \
    'Type "bth"' 'Sleep 400ms' \
    'Left' 'Left' 'Sleep 400ms'

assert-frame "Name:   bth" "The block cursor takes no column of its own inside the value"

# Same field again, driven to a value only a working cursor can produce: typing
# "oo" into the middle makes "booth", and "-1" only lands at the end if Right
# moved back out there.
run-tui save \
    'Left' 'Sleep 500ms' \
    'Down' 'Down' 'Down' 'Down' 'Down' 'Sleep 400ms' \
    'Enter' 'Sleep 400ms' \
    'Type "bth"' 'Sleep 400ms' \
    'Left' 'Left' 'Sleep 300ms' \
    'Type "oo"' 'Sleep 400ms' \
    'Right' 'Right' 'Sleep 300ms' \
    'Type "-1"' 'Sleep 400ms' \
    'Enter' 'Sleep 400ms'

config="$prj/.booth/config.toml"
assert-line "$config" "name = " '"booth-1"' "Left inserts mid-value and Right walks back to the end"

finally
