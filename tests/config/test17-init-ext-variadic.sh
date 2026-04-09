#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin

# Test variadic extension params: multiple packages joined with comma
run booth config $prj --no-tui --select "deno+pkg:npm:cowsay,npm:figlet"

boothfile="$prj/.booth/Boothfile"

# Check that the generated Boothfile contains the variadic param
assert-line "$boothfile" "arg DENO_PKGS=" "npm:cowsay,npm:figlet"  "DENO_PKGS arg has both packages"

# Check that the install line references the param
assert-line "$boothfile" "install deno-pkg " "\${DENO_PKGS}"       "install deno-pkg uses DENO_PKGS"

# Test with a single package (no comma)
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "deno+pkg:npm:cowsay"

boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" "arg DENO_PKGS=" "npm:cowsay"             "DENO_PKGS arg has single package"

finally
