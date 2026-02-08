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
python3 -m http.server 0 --directory "$recipe_dir" > "$recipe_dir/server.log" 2>&1 &
server_pid=$!
sleep 1
port=$(grep -oP 'port \K[0-9]+' "$recipe_dir/server.log")

run booth init new $prj --select "@@http://localhost:${port}/recipe.txt"

assert-last "which java || echo 'not found'" "/usr/bin/java"             "Java is installed"
assert-last "which mvn  || echo 'not found'" "/opt/maven-stable/bin/mvn" "Maven extension is installed"

assert-last "which go            || echo 'not found'" "/usr/local/go-current/bin/go"    "Go is installed"
assert-last "which golangci-lint || echo 'not found'" "/home/coder/go/bin/golangci-lint" "Go linter extension is installed"

assert-last "which python3 || echo 'not found'" "/opt/venvs/py3.13/bin/python3" "Python is installed"
assert-last "which uv      || echo 'not found'" "/usr/local/uv/uv"              "uv extension is installed"

kill $server_pid 2>/dev/null
rm -rf "$recipe_dir"
finally
