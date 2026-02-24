#!/bin/bash
# Update booth scripts in example directories
# Copies the booth wrapper from project root to each example and
# creates a version lock file so ./booth auto-downloads the correct binary.

set -euo pipefail

# Resolve script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE_BOOTH="$PROJECT_ROOT/booth"
VERSION_FILE="$PROJECT_ROOT/version.txt"

if [[ ! -f "$SOURCE_BOOTH" ]]; then
    echo "Error: Source booth script not found at $SOURCE_BOOTH" >&2
    exit 1
fi

if [[ ! -f "$VERSION_FILE" ]]; then
    echo "Error: version.txt not found at $VERSION_FILE" >&2
    exit 1
fi

VERSION=$(tr -d ' \t\r\n' < "$VERSION_FILE")
if [[ -z "$VERSION" ]]; then
    echo "Error: version.txt is empty" >&2
    exit 1
fi

echo "Updating booth scripts from: $SOURCE_BOOTH"
echo "Version: $VERSION"
echo ""

# Install booth wrapper and lock file into a directory
install_booth() {
    local dir="$1"
    rm -rf "$dir/.booth/tools"
    cp "$SOURCE_BOOTH" "$dir/booth"
    mkdir -p "$dir/.booth/tools"
    cat > "$dir/.booth/tools/codingbooth.lock" <<EOF
version=${VERSION}
cache=shared
EOF
    echo "Installed: $dir"
}

updated=0

# Update booth in immediate subfolders of examples/
for dir in "$SCRIPT_DIR"/*/; do
    [[ ! -d "$dir" ]] && continue
    install_booth "$dir"
    : $((updated++))
done

# Update booth in immediate subfolders of examples/workspaces/
if [[ -d "$SCRIPT_DIR/workspaces" ]]; then
    for dir in "$SCRIPT_DIR/workspaces"/*/; do
        install_booth "$dir"
        : $((updated++))
    done
fi

echo ""
if [[ $updated -eq 0 ]]; then
    echo "No examples found to update."
else
    echo "Updated $updated example(s)."
fi
