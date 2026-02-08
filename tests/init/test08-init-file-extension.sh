#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin

recipe="$prj--recipe.txt"
cat > "$recipe" <<'EOF'
java+maven
go+linter
python+uv
EOF

run booth init new $prj --select "@$recipe"

assert-last "which java || echo 'not found'" "/usr/bin/java"             "Java is installed"
assert-last "which mvn  || echo 'not found'" "/opt/maven-stable/bin/mvn" "Maven extension is installed"

assert-last "which go            || echo 'not found'" "/usr/local/go-current/bin/go"    "Go is installed"
assert-last "which golangci-lint || echo 'not found'" "/home/coder/go/bin/golangci-lint" "Go linter extension is installed"

assert-last "which python3 || echo 'not found'" "/opt/venvs/py3.13/bin/python3" "Python is installed"
assert-last "which uv      || echo 'not found'" "/usr/local/uv/uv"              "uv extension is installed"

finally
