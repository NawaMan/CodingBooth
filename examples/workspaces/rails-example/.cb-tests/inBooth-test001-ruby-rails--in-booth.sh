#!/bin/bash
set -euo pipefail
# Checks Ruby 3.3, rails gem, and the PostgreSQL client/server binaries (does not start postgres).
cd "$(dirname "$0")/.."   # the project folder: /home/coder/code in a booth
echo "=== Testing Ruby on Rails stack ==="
ruby --version | grep -qE '^ruby 3\.3'
gem --version
rails --version | grep -qE '^Rails '
command -v psql
psql --version
echo "PASS"
