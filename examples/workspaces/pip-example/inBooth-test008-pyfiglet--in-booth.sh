#!/bin/bash
# Test: pyfiglet (ASCII art text)

echo "=== Testing pyfiglet ==="
python -c "import pyfiglet; print(pyfiglet.figlet_format('PIP'))"
