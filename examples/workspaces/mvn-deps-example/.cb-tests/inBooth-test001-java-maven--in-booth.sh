#!/bin/bash
set -euo pipefail
# The JDK and Maven are installed and the project has its pom.xml.
echo "=== Testing Java and Maven ==="
cd "$(dirname "$0")/.."   # the project folder: /home/coder/code in a booth
java -version 2>&1 | grep -q "21"
mvn --version | grep -q "Apache Maven"
test -f pom.xml
