#!/bin/bash
# Test: rich (terminal formatting)

echo "=== Testing rich ==="
python -c "from rich import print; print('[bold green]Rich is working![/bold green]')"
