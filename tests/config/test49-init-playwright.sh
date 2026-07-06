#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin

# Test 1: Playwright with default browsers (chromium)
run booth config $prj --no-tui --select "nodejs/playwright"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'arg PLAYWRIGHT_BROWSERS=' 'chromium'  "default browsers is chromium"
assert-line "$boothfile" 'setup playwright ' '${PLAYWRIGHT_BROWSERS} --version ${PLAYWRIGHT_VERSION}'  "Boothfile uses param reference"

# Test 2: Playwright with all browsers (colon param syntax)
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "nodejs/playwright:all"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'arg PLAYWRIGHT_BROWSERS=' 'all'  "all browsers param"

# Test 3: Playwright with firefox (colon param syntax)
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "nodejs/playwright:firefox"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'arg PLAYWRIGHT_BROWSERS=' 'firefox'  "firefox param"

# Test 4: Playwright requires nodejs — auto-selected when not explicit
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "playwright"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'arg NODE_VERSION=' '22'  "nodejs auto-selected as dependency"

# Test 5: Playwright+python extension requires python
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "nodejs/python/playwright+python"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'run pip install ' 'playwright'  "python extension installs playwright pip"

# Test 6: Playwright+dotnet extension requires dotnet
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "nodejs/csharp/playwright+dotnet"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'run dotnet tool install --global ' 'Microsoft.Playwright.CLI || true'  "dotnet extension installs playwright CLI"

# Test 7: VS Code extension is auto-selected
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "nodejs/playwright"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'setup playwright-code-' 'extension'  "vscode extension auto-selected"

finally
