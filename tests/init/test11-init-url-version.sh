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
python3 -m http.server 0 --directory "$recipe_dir" > "$recipe_dir/server.log" 2>&1 &
server_pid=$!
sleep 1
port=$(grep -oP 'port \K[0-9]+' "$recipe_dir/server.log")

run booth init new $prj --select "@@http://localhost:${port}/recipe.txt"

assert-last \
    "java -version 2>&1 | grep -q '\"21' && echo 'java21' || echo 'not found'" \
    "java21" \
    "Java version is 21"

assert-last \
    "go version | grep -q 'go1.24' && echo 'go1.24' || echo 'not found'" \
    "go1.24" \
    "Go version is 1.24.13"

assert-last \
    "which golangci-lint || echo 'not found'" \
    "/home/coder/go/bin/golangci-lint" \
    "Go linter extension is installed"

assert-last \
    "python3 --version 2>&1 | grep -q '3.12' && echo 'python3.12' || echo 'not found'" \
    "python3.12" \
    "Python version is 3.12.12"

assert-last \
    "which uv || echo 'not found'" \
    "/usr/local/uv/uv" \
    "uv extension is installed"

kill $server_pid 2>/dev/null
rm -rf "$recipe_dir"
finally
