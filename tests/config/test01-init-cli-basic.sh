#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin
run booth config $prj --no-tui --select "java"

booth-collect "
echo -n '1: ' ; which java || echo 'not found' ;
"

assert-line "$tmpfile" "1: " "/usr/bin/java" "Java is installed"
finally
