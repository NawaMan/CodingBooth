#!/bin/bash
# TUI: a template whose tool the variant image already holds is marked "=" in
# the list, and selecting it says so in the footer. The mark follows the
# variant: firefox is unmarked on the default (base) variant and marked on
# desktop-xfce, whose image ships Firefox.
source "$(dirname "$0")/tui-helpers--source.sh"

# The TUI opens on Languages; a search filters every tab but stays put, so each
# case steps right to the tab its template lives on (Tools: 3, Desktop: 6).

begin

# glow is in the base image, so in every variant.
run-tui frame \
    'Tab' 'Type "glow"' 'Sleep 600ms' \
    'Tab' 'Sleep 300ms' 'Right 3' 'Sleep 400ms' 'Space' 'Sleep 600ms'

assert-frame "[x] =glow"                        "glow row carries the = mark"
assert-frame "glow is already in the base image" "selecting glow says it is already in the image"

# firefox on the default variant: not in base, so no mark.
rm -Rf "$prj"; mkdir -p "$prj"
run-tui frame \
    'Tab' 'Type "firefox"' 'Sleep 600ms' 'Tab' 'Sleep 300ms' 'Right 6' 'Sleep 400ms'

assert-frame "[ ] firefox" "firefox is unmarked on the base variant"

# firefox on desktop-xfce: the image ships it.
rm -Rf "$prj"; mkdir -p "$prj"
LAUNCH_ARGS=(--variant desktop-xfce)
run-tui frame \
    'Tab' 'Type "firefox"' 'Sleep 600ms' 'Tab' 'Sleep 300ms' 'Right 6' 'Sleep 400ms'

assert-frame "[ ] =firefox" "firefox is marked on desktop-xfce"

finally
