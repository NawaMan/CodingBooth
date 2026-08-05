#!/bin/bash
# TUI: a version pinned in the Boothfile's `arg` lines but NOT present in the
# stored "Configured by" selection (e.g. a hand-edited pin, or one predating the
# template param) must survive being reopened and saved in the config TUI. This
# reproduces the real regression where opening the config UI on such a booth and
# saving reset PLAYWRIGHT_VERSION to the template default.
source "$(dirname "$0")/tui-helpers--source.sh"

begin

# Seed a normal booth. Its "Configured by" comment records `nodejs/playwright`
# with no version pin, and the arg defaults to latest.
run() { "$@" >> "$log" 2>&1 ; }
run "$BOOTH_BIN" config "$prj" --no-tui --select nodejs/playwright --templates-path "$TEMPLATES_PATH"
if [[ ! -f "$prj/.booth/Boothfile" ]]; then
    skip "seed step did not produce a .booth/Boothfile"
fi

# Hand-pin the version directly in the arg line — the comment still says latest.
sed-inplace 's/^arg PLAYWRIGHT_VERSION=.*/arg PLAYWRIGHT_VERSION=1.58.2/' "$prj/.booth/Boothfile"
# The assertion below is only meaningful if the pin actually landed. A seed step
# that fails silently turns this into a test that always passes, or — as it did
# on macOS — always fails for a reason that has nothing to do with the product.
grep -q '^arg PLAYWRIGHT_VERSION=1\.58\.2$' "$prj/.booth/Boothfile" \
    || skip "seed step did not pin PLAYWRIGHT_VERSION"

# Reopen the TUI and save without touching the version. The hand-edit above makes
# this Boothfile hand-written as far as `booth config` is concerned, so the TUI now
# opens with a startup warning to clear, and saving requires typing the overwrite
# confirmation — otherwise nothing is written and the assertion below would pass
# merely because the file was never touched.
DISMISS_WARNING=true
run-tui save-confirm 'Sleep 500ms'

boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" "arg PLAYWRIGHT_VERSION=" "1.58.2" "hand-pinned version survives a TUI reopen+save"

finally
