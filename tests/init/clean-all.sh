#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rm -rf "$SCRIPT_DIR"/prj--* "$SCRIPT_DIR"/log--*
echo "Cleaned."
