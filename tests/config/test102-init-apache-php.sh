#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin
run booth config $prj --no-tui --select "apache+php"

boothfile="$prj/.booth/Boothfile"

assert-line "$boothfile" "setup apache" ""              "apache setup without --with-php"
assert-line "$boothfile" "setup apache --php-only" ""  "php extension is --php-only, not a second Apache install"
finally
