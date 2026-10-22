#!/bin/bash
source "$(dirname "$0")/../test-helpers--source.sh"

# goose-lang is the Goose programming language (aardappel/goose). Its command is
# goose-lang because the Goose AI agent template owns `goose`, so selecting both
# must give both setup lines. The version pin must land on the arg.

begin

boothfile="$prj/.booth/Boothfile"

# --- bare goose-lang: the catalog's default version ------------------------
run booth config $prj --no-tui --select 'goose-lang'
assert-line "$boothfile" "setup goose-lang" " --version \${GOOSE_LANG_VERSION}" "goose-lang adds setup goose-lang --version"
assert-line "$boothfile" "arg GOOSE_LANG_VERSION=" "$(template-default goose-lang GOOSE_LANG_VERSION)" \
    "GOOSE_LANG_VERSION defaults to the catalog's"

# --- pinned ----------------------------------------------------------------
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select 'goose-lang:2026.2'
assert-line "$boothfile" "arg GOOSE_LANG_VERSION=" "2026.2" "goose-lang:2026.2 pins GOOSE_LANG_VERSION"

# --- beside the Goose AI agent ---------------------------------------------
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select 'goose' --select 'goose-lang'
assert-line "$boothfile" "setup goose-lang" " --version \${GOOSE_LANG_VERSION}" "goose-lang is kept beside the goose agent"
assert-line "$boothfile" "setup goose " "--version \${GOOSE_VERSION}"           "the goose agent is kept beside goose-lang"

finally
