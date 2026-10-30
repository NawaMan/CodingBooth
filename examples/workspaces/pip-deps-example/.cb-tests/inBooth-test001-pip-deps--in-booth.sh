#!/bin/bash
set -euo pipefail
# python is installed, and the packages from .booth/requirements.txt import
echo "=== Testing pip-deps ==="
python3 -c "import requests; print(requests.__version__)"
python3 -c "import flask; print(flask.__version__)"
