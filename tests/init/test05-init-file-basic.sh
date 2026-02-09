#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin

recipe="$prj--recipe.txt"
echo "java" > "$recipe"

run booth init new $prj --select "@$recipe"

booth-collect "
echo -n '1: ' ; which java || echo 'not found' ;
"

assert-line "$tmpfile" "1: " "/usr/bin/java" "Java is installed"
finally
