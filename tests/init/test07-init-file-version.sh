#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin

recipe="$prj--recipe.txt"
cat > "$recipe" <<'EOF'
java:21
go:1.24.13+linter
python:3.12.12+uv
EOF

run booth init new $prj --select "@$recipe"

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

finally
