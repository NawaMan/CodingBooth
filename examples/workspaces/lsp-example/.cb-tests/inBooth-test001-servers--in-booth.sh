#!/bin/bash
echo "=== Every installed server answers LSP initialize ==="
cd "$(dirname "$0")/.." && just check
