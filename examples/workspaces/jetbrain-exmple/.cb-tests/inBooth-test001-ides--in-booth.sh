#!/bin/bash
set -euo pipefail
# Checks the JDK, claude CLI and the JetBrains IDE launchers are installed (launchers are not run: they need a display).
cd "$(dirname "$0")/.."   # the project folder: /home/coder/code in a booth
echo "=== Testing JetBrains booth binaries ==="
java -version 2>&1 | head -1
javac -version
command -v claude
claude --version
for ide in clion datagrip goland idea phpstorm pycharm rider rubymine webstorm; do
    command -v "$ide" >/dev/null || { echo "missing IDE launcher: $ide"; exit 1; }
    echo "found $ide"
done
command -v antigravity
echo "PASS"
