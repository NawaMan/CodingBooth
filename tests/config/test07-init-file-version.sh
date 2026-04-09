#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin

recipe="$prj--recipe.txt"
cat > "$recipe" <<'EOF'
java:21
go:1.24.13+linter
python:3.12.12+uv
EOF

run booth config $prj --no-tui --select "@$recipe"

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
