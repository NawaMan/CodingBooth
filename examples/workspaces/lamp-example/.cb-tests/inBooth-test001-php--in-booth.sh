#!/bin/bash
set -euo pipefail
# Checks PHP, Apache, MySQL client/server binaries are installed (does not start services).
cd "$(dirname "$0")/.."   # the project folder: /home/coder/code in a booth
echo "=== Testing LAMP binaries ==="
php --version | grep -qE '^PHP '
php -r 'echo "php ok\n";'
php -m | grep -qi mysql
command -v apache2 >/dev/null || command -v apache2ctl >/dev/null || command -v httpd
command -v mysql
mysql --version
test -f demo.sh
echo "PASS"
