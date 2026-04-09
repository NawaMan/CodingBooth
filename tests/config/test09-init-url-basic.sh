#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin

# Create recipe file and serve it via a simple HTTP server
recipe_dir=$(mktemp -d)
echo "java" > "$recipe_dir/recipe.txt"
python3 -c "
import http.server, socketserver, os, sys
os.chdir('$recipe_dir')
s = socketserver.TCPServer(('',0), http.server.SimpleHTTPRequestHandler)
open('$recipe_dir/port', 'w').write(str(s.server_address[1]))
s.serve_forever()
" &
server_pid=$!
sleep 1
port=$(cat "$recipe_dir/port")

run booth config $prj --no-tui --select "@@http://localhost:${port}/recipe.txt"

kill $server_pid 2>/dev/null
rm -rf "$recipe_dir"

booth-collect "
echo -n '1: ' ; which java || echo 'not found' ;
"

assert-line "$tmpfile" "1: " "/usr/bin/java" "Java is installed"
finally
