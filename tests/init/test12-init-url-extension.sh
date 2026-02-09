#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin

# Create recipe file and serve it via a simple HTTP server
recipe_dir=$(mktemp -d)
cat > "$recipe_dir/recipe.txt" <<'EOF'
java+maven
go+linter
python+uv
EOF
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

run booth init new $prj --select "@@http://localhost:${port}/recipe.txt"

kill $server_pid 2>/dev/null
rm -rf "$recipe_dir"

booth-collect "
echo -n '1: ' ; which java           || echo 'not found' ;
echo -n '2: ' ; which mvn            || echo 'not found' ;
echo -n '3: ' ; which go             || echo 'not found' ;
echo -n '4: ' ; which golangci-lint  || echo 'not found' ;
echo -n '5: ' ; which python3        || echo 'not found' ;
echo -n '6: ' ; which uv             || echo 'not found' ;
"

assert-line "$tmpfile" "1: " "/usr/bin/java"                    "Java is installed"
assert-line "$tmpfile" "2: " "/opt/maven-stable/bin/mvn"        "Maven extension is installed"
assert-line "$tmpfile" "3: " "/usr/local/go-current/bin/go"     "Go is installed"
assert-line "$tmpfile" "4: " "/home/coder/go/bin/golangci-lint" "Go linter extension is installed"
assert-line "$tmpfile" "5: " "/opt/venvs/py3.13/bin/python3"    "Python is installed"
assert-line "$tmpfile" "6: " "/usr/local/uv/uv"                 "uv extension is installed"
finally
