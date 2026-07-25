#!/bin/bash
# Phase 3 binary companions: puppeteer, cypress, selenium templates.
source "$(dirname "$0")/test-helpers--source.sh"

begin

# --- puppeteer ---
run booth config $prj --no-tui --select "puppeteer"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" "arg PUPPETEER_VERSION=" 'latest'  "puppeteer default version"
assert-line "$boothfile" "setup puppeteer --version " '${PUPPETEER_VERSION}'  "puppeteer setup line"
# requires nodejs
if ! grep -qE '^setup nodejs' "$boothfile"; then
  assert-line "$boothfile" "setup nodejs" 'MISSING'  "nodejs auto-selected for puppeteer"
else
  TEST_COUNT=$((TEST_COUNT + 1)); PASS_COUNT=$((PASS_COUNT + 1))
  echo -n "Test ${TEST_COUNT}: nodejs auto-selected for puppeteer ................. "
  echo -e "\033[32mPASSED\033[0m"
fi

# --- puppeteer version pin ---
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "puppeteer:24.0.0"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" "arg PUPPETEER_VERSION=" '24.0.0'  "puppeteer version pin"

# --- cypress ---
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "cypress"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" "arg CYPRESS_VERSION=" 'latest'  "cypress default version"
assert-line "$boothfile" "setup cypress --version " '${CYPRESS_VERSION}'  "cypress setup line"

# --- selenium defaults ---
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "selenium"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" "arg SELENIUM_BROWSERS=" 'chromium'  "selenium default browser"
assert-line "$boothfile" "arg SELENIUM_CHROME_VERSION=" 'Stable'  "selenium default chrome channel"
assert-line "$boothfile" "setup selenium " '${SELENIUM_BROWSERS} --chrome-version ${SELENIUM_CHROME_VERSION}'  "selenium setup line"

# --- selenium browsers param ---
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "selenium:all"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" "arg SELENIUM_BROWSERS=" 'all'  "selenium browsers=all"

finally
