#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin

recipe="$prj--recipe.txt"
echo "java" > "$recipe"

run booth init new $prj --select "@$recipe"
assert-last "which java || echo 'not found'" "/usr/bin/java" "Java is installed"
finally
