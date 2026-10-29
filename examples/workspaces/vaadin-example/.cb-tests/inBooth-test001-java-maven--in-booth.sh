#!/bin/bash
set -euo pipefail
# JDK 21 and Maven are installed
echo "=== Testing java and maven ==="
cd "$(dirname "$0")/.."   # the project folder: /home/coder/code in a booth
java -version 2>&1 | grep -qE '(openjdk|java)( version)? "?21'
javac -version 2>&1 | grep -q '21'
mvn --version | grep -q 'Apache Maven 3.9'
node --version | grep -qE '^v22\.'
test -f pom.xml
