#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin

recipe="$prj--recipe.txt"
cat > "$recipe" <<'EOF'
java
go
python
EOF

run booth init new $prj --select "@$recipe"
assert-last "which java    || echo 'not found'" "/usr/bin/java"                 "Java is installed"
assert-last "which go      || echo 'not found'" "/usr/local/go-current/bin/go"  "Go is installed"
assert-last "which python3 || echo 'not found'" "/opt/venvs/py3.13/bin/python3" "Python is installed"
finally
