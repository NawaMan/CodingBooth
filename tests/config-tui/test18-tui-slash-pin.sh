#!/bin/bash
# TUI: a package pinned in the Boothfile's `arg` lines whose value contains a "/"
# — every Go module path — must survive being reopened and saved in the config
# TUI. This reproduces the real regression where `booth config` on a booth with
# `arg GO_PKGS=github.com/pocketbase/pocketbase/examples/base@latest` died with
# `Error resolving selection: template "pocketbase" selected more than once`:
# the TUI wrote the pin into the select DSL unquoted, and re-parsing it split the
# module path into one template per path segment.
source "$(dirname "$0")/tui-helpers--source.sh"

begin

# Seed a normal booth. Its "Configured by" comment records `go+go-pkg` with no
# packages, and the arg defaults to empty.
run() { "$@" >> "$log" 2>&1 ; }
run "$BOOTH_BIN" config "$prj" --no-tui --select go+go-pkg --templates-path "$TEMPLATES_PATH"
if [[ ! -f "$prj/.booth/Boothfile" ]]; then
    skip "seed step did not produce a .booth/Boothfile"
fi

# Hand-pin the package directly in the arg line — the comment still says nothing.
sed-inplace 's|^arg GO_PKGS=.*|arg GO_PKGS=github.com/pocketbase/pocketbase/examples/base@latest|' \
    "$prj/.booth/Boothfile"
# Only meaningful if the pin actually landed — see test14 for what a silent seed
# failure does to the assertions below.
grep -q '^arg GO_PKGS=github\.com/pocketbase/' "$prj/.booth/Boothfile" \
    || skip "seed step did not pin GO_PKGS"

# Reopen the TUI and save without touching anything. The hand-edit makes this
# Boothfile hand-written as far as `booth config` is concerned, so the TUI opens
# with a startup warning to clear and saving needs the overwrite confirmation.
DISMISS_WARNING=true
run-tui save-confirm 'Sleep 500ms'

boothfile="$prj/.booth/Boothfile"

assert-line "$boothfile" "arg GO_PKGS=" "github.com/pocketbase/pocketbase/examples/base@latest" \
    "module-path pin survives a TUI reopen+save"

# The pin surviving is not enough on its own: before the fix the save failed and
# the file was never rewritten, which leaves the hand-edited line exactly where it
# was. The header only carries the package if the save actually ran, and only
# carries it quoted if the DSL can be read back at all.
assert-line "$boothfile" '# Configured by: booth config --no-tui --overwrite --select ' \
    $'\'go+vscode-ext+go-pkg:"github.com/pocketbase/pocketbase/examples/base@latest"\'' \
    "the save ran, and recorded the pin quoted"

finally
