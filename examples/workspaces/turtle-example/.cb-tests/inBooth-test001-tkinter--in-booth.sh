#!/bin/bash
# Booth Python can import tkinter (the runtime Tcl/Tk libs the example installs).
set -euo pipefail
cd "$(dirname "$0")/.."
echo "=== Testing tkinter on booth Python ==="
python -c "import turtle_tk; import tkinter; print('tkinter', tkinter.TkVersion)"
