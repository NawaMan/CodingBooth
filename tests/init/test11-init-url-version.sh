#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin

# Create recipe file and serve it via a simple HTTP server
recipe_dir=$(mktemp -d)
cat > "$recipe_dir/recipe.txt" <<'EOF'
java:21
go:1.24.13+linter
python:3.12.12+uv
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
echo -n '1: ' ; java -version 2>&1 | grep -q '\"21' && echo 'java21' || echo 'not found' ;
echo -n '2: ' ; go version | grep -q 'go1.24' && echo 'go1.24' || echo 'not found' ;
echo -n '3: ' ; which golangci-lint || echo 'not found' ;
echo -n '4: ' ; python3 --version 2>&1 | grep -q '3.12' && echo 'python3.12' || echo 'not found' ;
echo -n '5: ' ; which uv || echo 'not found' ;
"

assert-line "$tmpfile" "1: " "java21"                          "Java version is 21"
assert-line "$tmpfile" "2: " "go1.24"                          "Go version is 1.24.13"
assert-line "$tmpfile" "3: " "/home/coder/go/bin/golangci-lint" "Go linter extension is installed"
assert-line "$tmpfile" "4: " "python3.12"                      "Python version is 3.12.12"
assert-line "$tmpfile" "5: " "/usr/local/uv/uv"               "uv extension is installed"
finally
