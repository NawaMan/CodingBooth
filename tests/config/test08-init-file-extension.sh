#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin

recipe="$prj--recipe.txt"
cat > "$recipe" <<'EOF'
java+maven
go+linter
python+uv
EOF

run booth config $prj --no-tui --select "@$recipe"

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
