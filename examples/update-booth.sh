#!/bin/bash
# Update booth scripts in example directories
# Copies the booth wrapper from project root to each example that has one

set -euo pipefail

# Resolve script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE_BOOTH="$PROJECT_ROOT/booth"

if [[ ! -f "$SOURCE_BOOTH" ]]; then
    echo "Error: Source booth script not found at $SOURCE_BOOTH" >&2
    exit 1
fi

echo "Updating booth scripts from: $SOURCE_BOOTH"
echo ""

updated=0

# Update booth in immediate subfolders of examples/
for dir in "$SCRIPT_DIR"/*/; do
    [[ ! -d "$dir" ]] && continue
    rm -rf "$dir/.booth/tools"
    cp ../booth $dir/booth
    echo "Installed tools: $dir"
    : $((updated++))
done

# Update booth in immediate subfolders of examples/workspaces/
if [[ -d "$SCRIPT_DIR/workspaces" ]]; then
    for dir in "$SCRIPT_DIR/workspaces"/*/; do
        rm -rf "$dir/.booth/tools"
	cp ../booth $dir/booth
        echo "Installed tools: $dir"
        : $((updated++))
    done
fi

echo ""
if [[ $updated -eq 0 ]]; then
    echo "No booth scripts found to update."
else
    echo "Updated $updated booth script(s)."
fi
