#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin
run booth init new $prj --select "nodejs+yarn-pkg:typescript"

boothfile="$prj/.booth/Boothfile"

assert-line "$boothfile" "arg YARN_PKGS=" "typescript"       "YARN_PKGS arg"
assert-line "$boothfile" "install yarn " '${YARN_PKGS}'      "install yarn line"
finally
