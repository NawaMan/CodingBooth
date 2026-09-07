#!/bin/bash
# TUI: selecting `kotlin` asks to pull in its `java` requirement; confirming
# selects both (and they compile into the Boothfile).
#
# Space does not select immediately — kotlin requires java, so the TUI poses
# "Kotlin requires Java — add it too? [y/n]". Enter/Y accepts it. Ctrl+S is
# swallowed while that prompt is up, so a tape that Spaces then saves writes
# nothing.
source "$(dirname "$0")/tui-helpers--source.sh"

begin

# Frame check: the y/n prompt, then the post-confirm dependency footer.
run-tui frame \
    'Tab' 'Type "kotlin"' 'Sleep 600ms' \
    'Tab' 'Sleep 300ms' 'Space' 'Sleep 600ms' \
    'Enter' 'Sleep 600ms'

assert-frame "Kotlin requires Java — add it too?" "Footer asks to pull in the java dependency"
assert-frame "Dependency: java" "Footer announces the java dependency"

# File check: both kotlin and its java dependency compile into the Boothfile.
rm -Rf "$prj"; mkdir -p "$prj"
run-tui save \
    'Tab' 'Type "kotlin"' 'Sleep 600ms' \
    'Tab' 'Sleep 300ms' 'Space' 'Sleep 600ms' \
    'Enter' 'Sleep 600ms'

boothfile="$prj/.booth/Boothfile"
assert-file-contains "$boothfile" "setup kotlin" "kotlin is set up"
assert-file-contains "$boothfile" "setup jdk"    "java dependency (jdk) is auto set up"

finally
