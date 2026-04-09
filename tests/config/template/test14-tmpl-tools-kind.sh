#!/bin/bash
# Template test: kind (Kubernetes in Docker) — separate from dind/compose/buildx
# because kind download can fail (transient GitHub 500s) and abort the whole build.
source "$(dirname "$0")/../test-helpers--source.sh"

begin
run booth config $prj --no-tui --select "dind/kind"

booth-collect-dind "
echo -n '1: ' ; command -v kind    >/dev/null 2>&1 && echo 'OK' || echo 'FAIL' ;
echo -n '2: ' ; command -v kubectl >/dev/null 2>&1 && echo 'OK' || echo 'FAIL' ;
"

assert-line "$tmpfile" "1: " "OK"  "kind is installed"
assert-line "$tmpfile" "2: " "OK"  "kubectl is installed"
finally
