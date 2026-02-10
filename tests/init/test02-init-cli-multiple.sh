#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin
run booth init new $prj --select "java/go/python"

booth-collect "
echo -n '1: ' ; which java    || echo 'not found' ;
echo -n '2: ' ; which go      || echo 'not found' ;
echo -n '3: ' ; which python3 || echo 'not found' ;
"

assert-line "$tmpfile" "1: " "/usr/bin/java"                    "Java is installed"
assert-line "$tmpfile" "2: " "/usr/local/go-current/bin/go"     "Go is installed"
assert-line "$tmpfile" "3: " "/opt/venvs/py3.13/bin/python3"    "Python is installed"
finally
