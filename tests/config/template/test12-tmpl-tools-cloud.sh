#!/bin/bash
# Template test: AWS CLI + gcloud + Firebase (cloud tools)
# Firebase needs Node.js (npm), so nodejs is included.
source "$(dirname "$0")/../test-helpers--source.sh"

begin
run booth config $prj --no-tui --select "nodejs/aws-cli/gcloud/firebase"

booth-collect "
echo -n '1: ' ; command -v aws      >/dev/null 2>&1 && echo 'OK' || echo 'FAIL' ;
echo -n '2: ' ; command -v gcloud   >/dev/null 2>&1 && echo 'OK' || echo 'FAIL' ;
echo -n '3: ' ; command -v firebase >/dev/null 2>&1 && echo 'OK' || echo 'FAIL' ;
"

assert-line "$tmpfile" "1: " "OK"  "AWS CLI is installed"
assert-line "$tmpfile" "2: " "OK"  "gcloud is installed"
assert-line "$tmpfile" "3: " "OK"  "Firebase CLI is installed"
finally
