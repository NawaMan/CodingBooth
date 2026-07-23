#!/bin/bash
# Build (incrementally) and run the link checker.
#   ./run.sh [url-file] [db-file]     defaults: urls.txt, linkcheck.db
set -euo pipefail
cd "$(dirname "$0")"

./build.sh
./build/linkcheck "${1:-urls.txt}" "${2:-linkcheck.db}"
