#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin
run booth config $prj --no-tui --select "python+uv-pkg:ruff"

boothfile="$prj/.booth/Boothfile"

assert-line "$boothfile" "arg UV_PKGS=" "ruff"               "UV_PKGS arg"
assert-line "$boothfile" "install uv " '${UV_PKGS}'          "install uv line"
finally
