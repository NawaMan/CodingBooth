#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin
run booth config $prj --no-tui --select "php+composer"

boothfile="$prj/.booth/Boothfile"

assert-line "$boothfile" "setup php --version " '${PHP_VERSION}' "php setup with version"
assert-line "$boothfile" "setup php --composer-only" ""          "composer extension is --composer-only, not a second PHP install"
finally
