#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin
run booth config $prj --no-tui --select "deno+tool:npm:cowsay"

boothfile="$prj/.booth/Boothfile"

assert-line "$boothfile" "arg DENO_TOOLS=" "npm:cowsay"        "DENO_TOOLS arg"
assert-line "$boothfile" "install deno " '${DENO_TOOLS}'      "install deno line"
finally
