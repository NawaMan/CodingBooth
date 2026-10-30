#!/bin/bash
source "$(dirname "$0")/../test-helpers--source.sh"

begin

boothfile="$prj/.booth/Boothfile"

# --- 1. GCC front ends follow the gcc template's version -------------------
# Fortran, COBOL and ALGOL 68 are extensions of gcc, so they share GCC_VERSION
# and must run after `setup gcc` (order 55), which owns /opt/gcc-stable.
run booth config $prj --no-tui --select "gcc+fortran+cobol+algol68"

assert-line "$boothfile" "arg GCC_VERSION=" "$(template-default gcc GCC_VERSION)" "GCC_VERSION arg"
assert-line "$boothfile" 'setup gcc-frontend --lang fortran --version ${GCC_VERSION}' "" "gfortran setup line"
assert-line "$boothfile" 'setup gcc-frontend --lang cobol --version ${GCC_VERSION}'   "" "gcobol setup line"
assert-line "$boothfile" 'setup gcc-frontend --lang algol68 --version ${GCC_VERSION}' "" "ga68 setup line"
assert-line "$boothfile" 'setup fortran-code-extension' "" "Fortran VS Code extension"
assert-line "$boothfile" 'setup cobol-code-extension'   "" "COBOL VS Code extension"

line_gcc=$(grep -n '^setup gcc --version'      "$boothfile" | cut -d: -f1)
line_fe=$(grep -n '^setup gcc-frontend '       "$boothfile" | head -1 | cut -d: -f1)
if [[ -z "$line_gcc" || -z "$line_fe" ]] || (( line_fe <= line_gcc )); then
    echo "  ❌ gcc-frontend (line $line_fe) must come after setup gcc ($line_gcc)"
    exit 1
fi

run booth config $prj --no-tui --overwrite --select "gcc:16+cobol"
assert-line "$boothfile" "arg GCC_VERSION=" "16" "GCC_VERSION pin reaches the COBOL front end"

# --- 2. Prolog -------------------------------------------------------------
run booth config $prj --no-tui --overwrite --select "prolog"
assert-line "$boothfile" "arg PROLOG_IMPL=" "$(template-default prolog PROLOG_IMPL)" "PROLOG_IMPL arg"
assert-line "$boothfile" 'setup prolog --impl ${PROLOG_IMPL}' "" "prolog setup line"

run booth config $prj --no-tui --overwrite --select "prolog:gnu"
assert-line "$boothfile" "arg PROLOG_IMPL=" "gnu" "PROLOG_IMPL pin"

# --- 3. Smalltalk (Pharo) --------------------------------------------------
run booth config $prj --no-tui --overwrite --select "smalltalk"
assert-line "$boothfile" "arg PHARO_VERSION=" "$(template-default smalltalk PHARO_VERSION)" "PHARO_VERSION arg"
assert-line "$boothfile" 'setup pharo --version ${PHARO_VERSION}' "" "pharo setup line"

run booth config $prj --no-tui --overwrite --select "smalltalk:13"
assert-line "$boothfile" "arg PHARO_VERSION=" "13" "PHARO_VERSION pin"

finally
