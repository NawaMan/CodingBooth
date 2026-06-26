#!/bin/bash
# TUI: a variadic package param (apt-pkg's APT_PKGS) is edited as a multi-row
# list in the RIGHT panel — add several packages as separate rows.
#
# Flow: Tools tab → select apt-pkg → Enter (focus right panel) →
#       Space on "(+ add)" → type a package → Enter, repeated → save.
# Each add is its own row. They are entered out of order and with a duplicate
# (jq, htop, jq) to confirm the serialize-time canonicalization: on save the
# value is deduped + sorted into `install apt ${APT_PKGS}` with APT_PKGS=htop,jq.
source "$(dirname "$0")/tui-helpers--source.sh"

begin

# Launch is on the Languages tab; apt-pkg lives under Tools (Right ×2).
run-tui save \
    'Right' 'Sleep 300ms' 'Right' 'Sleep 500ms' \
    'Tab' 'Type "apt-pkg"' 'Sleep 700ms' 'Tab' 'Sleep 300ms' \
    'Space' 'Sleep 500ms' \
    'Enter' 'Sleep 500ms' \
    'Space' 'Sleep 300ms' 'Type "jq"'   'Sleep 300ms' 'Enter' 'Sleep 500ms' \
    'Space' 'Sleep 300ms' 'Type "htop"' 'Sleep 300ms' 'Enter' 'Sleep 500ms' \
    'Space' 'Sleep 300ms' 'Type "jq"'   'Sleep 300ms' 'Enter' 'Sleep 500ms'

boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" "arg APT_PKGS=" "htop,jq" "Rows are deduped + sorted on save (jq,htop,jq → htop,jq)"
assert-file-contains "$boothfile" "install apt" "apt-pkg compiles to 'install apt'"

finally
