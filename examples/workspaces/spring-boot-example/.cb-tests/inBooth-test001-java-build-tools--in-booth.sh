#!/bin/bash
set -euo pipefail
# JDK 21, Maven and Gradle are installed.
echo "=== Testing Java build tools ==="
cd "$(dirname "$0")/.."   # the project folder: /home/coder/code in a booth
java -version 2>&1 | grep -q "21"
mvn --version | grep -q "Apache Maven"
gradle --version | grep -q "Gradle"
test -f pom.xml
