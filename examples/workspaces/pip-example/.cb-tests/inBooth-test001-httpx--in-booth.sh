#!/bin/bash
# Test: httpx (HTTP client)

echo "=== Testing httpx ==="
python -c "import httpx; print(f'httpx version: {httpx.__version__}')"
