#!/bin/bash
set -euo pipefail
# Checks every language toolchain (node, python, go, java, mvn, dotnet) and the Playwright bindings/browser are installed.
cd "$(dirname "$0")/.."   # the project folder: /home/coder/code in a booth
echo "=== Testing polyglot toolchains ==="
node --version | grep -qE '^v22\.'
python --version | grep -qE 'Python 3\.13'
go version | grep -q 'go1\.25'
java -version 2>&1 | head -1
javac -version
mvn --version | head -1
dotnet --version | grep -qE '^9\.'
python -c 'import playwright; print("python playwright ok")'
test -d "${PLAYWRIGHT_BROWSERS_PATH:-/opt/ms-playwright}"
ls "${PLAYWRIGHT_BROWSERS_PATH:-/opt/ms-playwright}" | grep -qi chromium
echo "PASS"
