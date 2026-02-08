#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin
run booth init new $prj --select "java"
assert-last "which java || echo 'not found'" "/usr/bin/java" "Java is installed"
finally
