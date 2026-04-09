#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin
run booth config $prj --no-tui --select "ruby+gem-pkg:colorize"

booth-collect "
echo -n '1: ' ; ruby -e \"require 'colorize'; puts 'OK'\" 2>&1 ;
"

assert-line "$tmpfile" "1: " "OK"  "colorize is installed via gem"
finally
