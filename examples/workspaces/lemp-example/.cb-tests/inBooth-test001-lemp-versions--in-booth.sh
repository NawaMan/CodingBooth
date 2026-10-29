#!/bin/bash
set -euo pipefail
# php, mysql and nginx binaries are installed and print versions
echo "=== Testing LEMP binaries ==="
php --version | head -1 | grep -q "^PHP "
mysql --version
nginx -v 2>&1 | grep -q nginx
