#!/bin/bash
# Run Statistics calculator
cd "$(dirname "$0")"
python src/stats.py "$@"
