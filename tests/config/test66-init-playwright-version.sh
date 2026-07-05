#!/bin/bash
# Guards the Playwright version pin: the pre-baked browsers are installed at
# build time by `setup playwright --version X`, and must match the Playwright
# that runtime `npm ci` installs from package.json. If PLAYWRIGHT_VERSION stops
# flowing into the setup call (or the positional param order changes so a
# version lands in PLAYWRIGHT_BROWSERS), the browser/runtime versions silently
# diverge and headless launches fail. This keeps that coupling honest.
source "$(dirname "$0")/test-helpers--source.sh"

begin
# Pin browsers (first positional) + version (second positional).
run booth config $prj --no-tui --select "playwright:chromium,1.58.2"

boothfile="$prj/.booth/Boothfile"

assert-line "$boothfile" "arg PLAYWRIGHT_BROWSERS=" "chromium"  "PLAYWRIGHT_BROWSERS stays first positional (chromium)"
assert-line "$boothfile" "arg PLAYWRIGHT_VERSION="  "1.58.2"    "PLAYWRIGHT_VERSION pinned to 1.58.2"
assert-line "$boothfile" "setup playwright " "\${PLAYWRIGHT_BROWSERS} --version \${PLAYWRIGHT_VERSION}" "setup playwright pins the version"

# Default (unpinned) preserves the pre-existing behavior: latest.
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "playwright"

assert-line "$boothfile" "arg PLAYWRIGHT_VERSION=" "latest"  "PLAYWRIGHT_VERSION defaults to latest"
finally
