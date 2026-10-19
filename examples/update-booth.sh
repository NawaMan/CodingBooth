#!/bin/bash
# Update booth scripts in example directories
# Copies the booth wrapper from project root to each example and
# creates a version lock file so ./booth auto-downloads the correct binary.
#
# A version with a suffix (x.y.z--rc1, x.y.z--<worktree>) is never published,
# so there is nothing to download: the shared cache is seeded with this
# checkout's build (bin/) and templates instead, and ./booth runs that.
#
#   update-booth.sh               wrappers + locks, then seed (suffixed versions)
#   update-booth.sh --seed-only   seed only; cli-build.sh runs this after a build

set -euo pipefail

# Resolve script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE_BOOTH="$PROJECT_ROOT/booth"
VERSION_FILE="$PROJECT_ROOT/version.txt"
BIN_DIR="$PROJECT_ROOT/bin"

SEED_ONLY=false
case "${1:-}" in
    "")          ;;
    --seed-only) SEED_ONLY=true ;;
    *) echo "Usage: $0 [--seed-only]" >&2; exit 1 ;;
esac

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

# Same locations the wrapper (booth: get_cache_dir) and the CLI
# (cache.getCacheDir, for templates.zip) read.
wrapper_cache_dir() {
    if [[ -n "${BOOTH_CACHE_DIR:-}" ]]; then
        echo "$BOOTH_CACHE_DIR"
    elif [[ "$(uname -s)" == Darwin* ]]; then
        echo "$HOME/Library/Caches/codingbooth"
    else
        echo "${XDG_CACHE_HOME:-$HOME/.cache}/codingbooth"
    fi
}
cli_cache_dir() {
    echo "${XDG_CACHE_HOME:-$HOME/.cache}/codingbooth"
}

hash_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$@"
    else
        shasum -a 256 "$@"
    fi
}

# Copy into place by rename, so a booth already running the old binary keeps it.
place() {
    local src="$1" dest="$2"
    cp "$src" "$dest.tmp.$$"
    mv -f "$dest.tmp.$$" "$dest"
}

# Seed the shared cache for $VERSION with this checkout's build and templates.
seed_cache() {
    if [[ "$VERSION" != *--* ]]; then
        echo "Version $VERSION is a release: ./booth downloads it, no cache seeded."
        return 0
    fi

    local -a binaries=()
    local f
    for f in "$BIN_DIR"/codingbooth-*; do
        [[ -f "$f" ]] && binaries+=("$f")
    done
    if [[ ${#binaries[@]} -eq 0 ]]; then
        echo "Error: no build in $BIN_DIR. Run ./build/cli-build.sh first." >&2
        exit 1
    fi
    # A binary older than the CLI source is not what this checkout would build.
    local stale
    stale=$(find "$PROJECT_ROOT/cli" \( -name '*.go' -o -name 'go.mod' -o -name 'go.sum' \) \
                -newer "${binaries[0]}" -print -quit)
    if [[ -n "$stale" || "$VERSION_FILE" -nt "${binaries[0]}" ]]; then
        echo "Error: $BIN_DIR is older than the source (${stale:-version.txt})." >&2
        echo "Run ./build/cli-build.sh, which seeds the cache itself." >&2
        exit 1
    fi

    local dest
    dest="$(wrapper_cache_dir)/versions/$VERSION"
    mkdir -p "$dest"
    for f in "${binaries[@]}"; do
        place "$f" "$dest/${f##*/}"
    done
    (cd "$BIN_DIR" && hash_sha256 "${binaries[@]##*/}") > "$dest/codingbooth.sha256.tmp.$$"
    mv -f "$dest/codingbooth.sha256.tmp.$$" "$dest/codingbooth.sha256"

    # templates.zip, packaged as the release workflow does it.
    local zip_tmp="$dest/templates.zip.tmp.$$.zip"
    (cd "$PROJECT_ROOT" && zip -qr "$zip_tmp" templates/)
    mv -f "$zip_tmp" "$dest/templates.zip"
    local cli_dest
    cli_dest="$(cli_cache_dir)/versions/$VERSION"
    if [[ "$cli_dest" != "$dest" ]]; then
        mkdir -p "$cli_dest"
        place "$dest/templates.zip" "$cli_dest/templates.zip"
    fi

    echo "Seeded shared cache for $VERSION: $dest"
}

if $SEED_ONLY; then
    seed_cache
    exit 0
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

echo ""
seed_cache
