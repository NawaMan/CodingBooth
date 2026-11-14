#!/bin/bash
# TUI: a template whose tool the variant image already holds shows [=]. Space
# cycles a removable one [=] → [ ] (saved as ~name) → [x] → [=]. The state
# follows the variant: firefox is [ ] on the default (base) variant and [=] on
# desktop-xfce, whose image ships Firefox.
source "$(dirname "$0")/tui-helpers--source.sh"

# The TUI opens on Languages; a search filters every tab but stays put, so each
# case steps right to the tab its template lives on (Tools: 3, Desktop: 6).
GLOW=('Tab' 'Type "glow"' 'Sleep 600ms' 'Tab' 'Sleep 300ms' 'Right 3' 'Sleep 400ms')
FIREFOX=('Tab' 'Type "firefox"' 'Sleep 600ms' 'Tab' 'Sleep 300ms' 'Right 6' 'Sleep 400ms')

begin

# glow is in the base image: [=] before anything is pressed.
run-tui frame "${GLOW[@]}"
assert-frame "[=] glow" "glow shows [=] on the base variant"

# One Space removes it, and the save records ~glow.
rm -Rf "$prj"; mkdir -p "$prj"
run-tui frame "${GLOW[@]}" 'Space' 'Sleep 600ms'
assert-frame "[ ] glow"   "one Space removes glow"
assert-frame "~glow: the booth takes glow out of the base image" "the footer names the removal"

rm -Rf "$prj"; mkdir -p "$prj"
run-tui save "${GLOW[@]}" 'Space' 'Sleep 500ms'
assert-file-contains "$prj/.booth/Boothfile" "--select ~glow"            "the save records ~glow"
assert-file-contains "$prj/.booth/Boothfile" "run rm -f /usr/local/bin/glow" "and emits glow's remove step"

# A second Space selects the template's own release.
rm -Rf "$prj"; mkdir -p "$prj"
run-tui frame "${GLOW[@]}" 'Space' 'Sleep 400ms' 'Space' 'Sleep 600ms'
assert-frame "[x] glow"                         "a second Space selects glow"
assert-frame "glow is already in the base image" "selecting says it is already in the image"

# firefox: not in base, in desktop-xfce.
rm -Rf "$prj"; mkdir -p "$prj"
run-tui frame "${FIREFOX[@]}"
assert-frame "[ ] firefox" "firefox is [ ] on the base variant"

rm -Rf "$prj"; mkdir -p "$prj"
LAUNCH_ARGS=(--variant desktop-xfce)
run-tui frame "${FIREFOX[@]}"
assert-frame "[=] firefox" "firefox is [=] on desktop-xfce"

finally
