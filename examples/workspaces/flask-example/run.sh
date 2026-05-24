#!/bin/bash
# Install dependencies and start the Flask app.
# Intended to be run from inside the booth.
set -euo pipefail
cd "$(dirname "$0")"

pip install -r requirements.txt
python app.py
