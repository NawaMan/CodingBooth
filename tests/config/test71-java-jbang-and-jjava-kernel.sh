#!/bin/bash
# The two Java extensions added alongside the demo port.
#
# `java/kernel-jjava` installs the JJava kernel (dflib/jjava) INSTEAD of the IJava one
# that `java/kernel` installs. Both register the kernelspec under the same name (`java`
# suffixed with the JDK version, e.g. `java25`), so the kernelspec alone cannot tell you
# which one landed — this test pins the presence of JJava's workdir (/opt/jjava) and the
# ABSENCE of IJava's (/opt/ijava).
#
# `java/jbang` pre-warms the jbang dependency cache at build time. jbang itself ships
# with the JDK setup, so `which jbang` proves nothing about the extension — what it does
# is populate JBANG_CACHE_DIR (/opt/jbang-cache), which is empty without it.
source "$(dirname "$0")/test-helpers--source.sh"

begin

run booth config $prj --no-tui --select "java+jbang+kernel-jjava/notebook"

booth-collect "
echo -n '1: ' ; test -d /opt/jjava            && echo 'jjava'      || echo 'not found' ;
echo -n '2: ' ; test -d /opt/ijava            && echo 'ijava'      || echo 'absent' ;
echo -n '3: ' ; jupyter kernelspec list 2>/dev/null | grep -qE '^[[:space:]]+java[0-9]+[[:space:]]' && echo 'registered' || echo 'not found' ;
echo -n '4: ' ; test -n \"\$(ls -A /opt/jbang-cache 2>/dev/null)\" && echo 'warm' || echo 'empty' ;
echo -n '5: ' ; which jbang                   || echo 'not found' ;
"

assert-line "$tmpfile" "1: " "jjava"                "JJava kernel is installed (kernel-jjava extension)"
assert-line "$tmpfile" "2: " "absent"               "IJava kernel is NOT installed (kernel-jjava replaces it)"
assert-line "$tmpfile" "3: " "registered"           "the java kernelspec is registered with Jupyter"
assert-line "$tmpfile" "4: " "warm"                 "jbang dependency cache is pre-warmed at build time"
assert-line "$tmpfile" "5: " "/usr/local/bin/jbang" "jbang is on PATH"
finally
