#!/bin/bash
set -euo pipefail
# PostgreSQL client, Python data libraries and Node.js are installed.
echo "=== Testing data tools ==="
psql --version
python3 --version
python3 -c "import matplotlib, psycopg2; print('matplotlib', matplotlib.__version__, 'psycopg2', psycopg2.__version__)"
node --version
