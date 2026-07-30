#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

# A param value made of separators — a Go module path is all slashes — is written
# quoted, or the "/" splits the selection into one template per path segment.
# Unquoted, `go+go-pkg:github.com/pocketbase/pocketbase/examples/base@latest` died
# with `template "pocketbase" selected more than once`.

begin

boothfile="$prj/.booth/Boothfile"

# --- A quoted module path reaches the Boothfile whole -------------------------
run booth config $prj --no-tui --select 'go+go-pkg:"github.com/pocketbase/pocketbase/examples/base@latest"/claude-code'

assert-line "$boothfile" "arg GO_PKGS=" "github.com/pocketbase/pocketbase/examples/base@latest" "GO_PKGS arg"
# Whole-line prefix: the go template emits three `install go` lines and assert-line
# takes the first match.
assert-line "$boothfile" 'install go ${GO_PKGS}' ""                                              "install go line"
assert-line "$boothfile" "setup claude-code"  ""                                                 "second template still selected"

# The header keeps the DSL shell-quoted, so it is both re-runnable and readable back.
assert-line "$boothfile" '# Configured by: booth config --no-tui --overwrite --select ' \
    $'\'go+go-pkg:"github.com/pocketbase/pocketbase/examples/base@latest"/claude-code\'' \
    "header records the quoted DSL"

# --- Reconfiguring reads that header back ------------------------------------
# No --select: the selection comes from the header alone, which is the path that
# `booth config` (TUI or not) takes on an existing booth.
run booth config $prj --no-tui --overwrite

assert-line "$boothfile" "arg GO_PKGS=" "github.com/pocketbase/pocketbase/examples/base@latest" "GO_PKGS survives reconfigure"
assert-line "$boothfile" "setup claude-code"  ""                                                 "second template survives reconfigure"

# --- Several quoted packages in one list --------------------------------------
run booth config $prj --no-tui --overwrite --select 'go+go-pkg:"github.com/a/b@v1","github.com/c/d@v2"'

assert-line "$boothfile" "arg GO_PKGS=" "github.com/a/b@v1,github.com/c/d@v2" "two quoted packages"

# --- Plain values are untouched ----------------------------------------------
# Nothing that does not need quoting gains it: the header of every existing booth
# has to stay byte-for-byte what it was.
run booth config $prj --no-tui --overwrite --select 'go:1.25.7+go-pkg:gopls@latest'

assert-line "$boothfile" "arg GO_VERSION=" "1.25.7"                                    "unquoted version param"
assert-line "$boothfile" "arg GO_PKGS=" "gopls@latest"                                 "unquoted package param"
assert-line "$boothfile" '# Configured by: booth config --no-tui --overwrite --select ' \
    "go:1.25.7+go-pkg:gopls@latest" "header stays unquoted for plain values"

finally
