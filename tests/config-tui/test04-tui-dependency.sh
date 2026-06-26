#!/bin/bash
# TUI: selecting `kotlin` auto-selects its dependency `java`.
source "$(dirname "$0")/tui-helpers--source.sh"

begin

# Frame check: dependency-resolution notice in the footer.
run-tui frame \
    'Tab' 'Type "kotlin"' 'Sleep 600ms' \
    'Tab' 'Sleep 300ms' 'Space' 'Sleep 600ms'

assert-frame "Dependency: java" "Footer announces the java dependency"

# File check: both kotlin and its java dependency compile into the Boothfile.
rm -Rf "$prj"; mkdir -p "$prj"
run-tui save \
    'Tab' 'Type "kotlin"' 'Sleep 600ms' \
    'Tab' 'Sleep 300ms' 'Space' 'Sleep 600ms'

boothfile="$prj/.booth/Boothfile"
assert-file-contains "$boothfile" "setup kotlin" "kotlin is set up"
assert-file-contains "$boothfile" "setup jdk"    "java dependency (jdk) is auto set up"

finally
