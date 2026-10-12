#!/bin/bash
# mc: Midnight Commander comes from apt, now that the base image does not ship it.
source "$(dirname "$0")/../test-helpers--source.sh"

begin

boothfile="$prj/.booth/Boothfile"

run booth config $prj --no-tui --select 'mc'
assert-line "$boothfile" "install apt" " mc" "mc adds install apt mc"

finally
