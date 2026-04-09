#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin
run booth config $prj --no-tui --select "java+maven+mvn-install"

boothfile="$prj/.booth/Boothfile"

assert-line "$boothfile" "run --mount=type=bind,target=/tmp/ctx " "if [ -f /tmp/ctx/pom.xml ]; then mkdir -p /opt/mvn-cache && cp /tmp/ctx/pom.xml /opt/mvn-cache/ && cd /opt/mvn-cache && mvn dependency:resolve -B -q; fi"  "mvn deps mount bind line"
finally
