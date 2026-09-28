#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin

# Test 1: default scheme is recommended, passed to the setup by flag
run booth config $prj --no-tui --select "latex"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'arg LATEX_SCHEME=' 'recommended'              "default scheme is recommended"
assert-line "$boothfile" 'setup latex ' '--scheme ${LATEX_SCHEME}'       "setup passes the scheme by flag"
assert-line "$boothfile" 'setup latex-code-extension' ''                "vscode-ext is auto-selected"

# Test 2: a pinned scheme lands in the arg
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "latex:extra"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'arg LATEX_SCHEME=' 'extra'                    "pinned scheme is extra"

# Test 3: the VS Code extension can be dropped
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "latex~vscode-ext"
boothfile="$prj/.booth/Boothfile"
grep -c '^setup latex-code-extension' "$boothfile" > "$tmpfile" || true
assert-line "$tmpfile" '' '0'                                           "latex~vscode-ext drops the VS Code extension"

# Test 4: TeXstudio is opt-in -- absent by default, emitted after the TeX install when selected
grep -c '^setup texstudio' "$boothfile" > "$tmpfile" || true
assert-line "$tmpfile" '' '0'                                           "texstudio is not selected by default"
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "latex+texstudio"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'setup texstudio' ''                           "latex+texstudio emits setup texstudio"
grep -E '^setup (latex|texstudio)( |$)' "$boothfile" | awk '{print $2}' | paste -sd' ' > "$tmpfile"
assert-line "$tmpfile" '' 'latex texstudio'                             "texstudio is set up after the TeX install"

finally
