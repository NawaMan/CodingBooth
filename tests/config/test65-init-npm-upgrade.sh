#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin
# Pin to a specific npm version so the runtime assertion is deterministic
# (Node.js 22 bundles npm 10.9.x; the extension upgrades it at build time).
run booth config $prj --no-tui --select "nodejs+npm-upgrade:11.18.0"

boothfile="$prj/.booth/Boothfile"

# --- Boothfile wiring (fast, no Docker) ---
assert-line "$boothfile" "arg NPM_VERSION="     "11.18.0"           "NPM_VERSION pinned to 11.18.0"
assert-line "$boothfile" "run npm install -g npm@" "\${NPM_VERSION}" "npm-upgrade emits build-time upgrade step"

# --- Runtime: npm is actually upgraded inside the built image ---
booth-collect "
echo -n '1: ' ; npm --version 2>&1 ;
"

assert-line "$tmpfile" "1: " "11.18.0"  "npm upgraded to 11.18.0 in the image"
finally
