#!/bin/bash
source "$(dirname "$0")/../test-helpers--source.sh"

begin

# Create recipe file and serve it via a simple HTTP server
recipe_dir=$(mktemp -d)
echo "java" > "$recipe_dir/recipe.txt"
serve_dir_http "$recipe_dir" &
server_pid=$!
port=$(http_port_of "$recipe_dir") || echo "recipe server did not come up" >&2

run booth config $prj --no-tui --select "@@http://localhost:${port}/recipe.txt"

kill $server_pid 2>/dev/null
rm -rf "$recipe_dir"

booth-collect "
echo -n '1: ' ; which java || echo 'not found' ;
"

assert-line "$tmpfile" "1: " "/usr/bin/java" "Java is installed"
finally
