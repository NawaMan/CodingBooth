#!/bin/bash
# Reconfiguring a booth (e.g. to add/remove an extension) must NOT silently reset
# unrelated param pins to their template defaults. This reproduces the real bug:
# a Playwright version pin was lost when reconfiguring to add npm-upgrade, because
# `booth config` rebuilds from the selection DSL and the pin lived only in the
# Boothfile's `arg` lines. The resolver now reads those back as overrides.
source "$(dirname "$0")/test-helpers--source.sh"

begin
boothfile="$prj/.booth/Boothfile"

# 1) Pin Playwright to 1.58.2.
run booth config $prj --no-tui --select "nodejs/playwright:chromium,1.58.2"
assert-line "$boothfile" "arg PLAYWRIGHT_VERSION=" "1.58.2"  "initial pin is 1.58.2"

# 2) Reconfigure to add npm-upgrade WITHOUT repeating the pin — it must survive.
run booth config $prj --no-tui --overwrite --select "nodejs+npm-upgrade/playwright"
assert-line "$boothfile" "arg PLAYWRIGHT_VERSION=" "1.58.2"  "pin preserved across reconfigure"
assert-line "$boothfile" "arg NPM_VERSION="        "latest"  "npm-upgrade extension was added"

# 3) An explicit value in the new selection still wins over the preserved pin.
run booth config $prj --no-tui --overwrite --select "nodejs+npm-upgrade/playwright:chromium,1.59.0"
assert-line "$boothfile" "arg PLAYWRIGHT_VERSION=" "1.59.0"  "explicit value overrides preserved pin"
finally
