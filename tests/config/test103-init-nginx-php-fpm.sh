#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin
run booth config $prj --no-tui --select "nginx+php-fpm"

boothfile="$prj/.booth/Boothfile"

assert-line "$boothfile" "setup nginx" ""               "nginx setup without --with-php-fpm"
assert-line "$boothfile" "setup nginx --fpm-only" ""    "php-fpm extension is --fpm-only, not a second nginx install"
finally
