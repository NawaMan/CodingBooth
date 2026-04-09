#!/bin/bash
# Template test: Java + Kotlin + Scala + Clojure (JVM family)
source "$(dirname "$0")/../test-helpers--source.sh"

begin
run booth config $prj --no-tui --select "java:21/kotlin/scala/clojure"

booth-collect "
echo -n '1: ' ; command -v java    >/dev/null 2>&1 && echo 'OK' || echo 'FAIL' ;
echo -n '2: ' ; command -v kotlin  >/dev/null 2>&1 && echo 'OK' || echo 'FAIL' ;
echo -n '3: ' ; command -v scala   >/dev/null 2>&1 && echo 'OK' || echo 'FAIL' ;
echo -n '4: ' ; command -v clojure >/dev/null 2>&1 && echo 'OK' || echo 'FAIL' ;
"

assert-line "$tmpfile" "1: " "OK"  "Java is installed"
assert-line "$tmpfile" "2: " "OK"  "Kotlin is installed"
assert-line "$tmpfile" "3: " "OK"  "Scala is installed"
assert-line "$tmpfile" "4: " "OK"  "Clojure is installed"
finally
