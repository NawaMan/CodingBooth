#!/bin/bash
set -euo pipefail
trap 'status=$?; echo "❌ Error on line $LINENO (exit $status)" >&2; exit "$status"' ERR

VERSION=0.4.0
VERBOSE="${VERBOSE:-true}"

# Decide what the "command" is:
if [[ $# -eq 0 ]]; then COMMAND="run" ; else COMMAND="$1" ; fi

function Main() {
    ### --- COMMAND DISPATCH --- ###
    case "${COMMAND}" in
        uninstall)      UninstallWorkspace               ; exit 0 ; ;;
        rehash)         RehashWorkspace                  ; exit 0 ; ;;
        install|update) DownloadWorkspace "${2:-latest}" ; exit 0 ; ;;
        run)            [[ "${1-}" == "run" ]] && shift  ;          ;;
        *)                                                          ;;
    esac

    ### --- RUN MODE --- ###
    tools_dir=".ws/tools"
    dest="$tools_dir/workspace"
    sha_file="$tools_dir/workspace.sha256"
    meta_file="$tools_dir/workspace.meta"

    if [[ ! -f "$dest" || ! -f "$sha_file" || ! -f "$meta_file" ]]; then
        echo "WorkSpace is not installed correctly."
        echo "Please run: $0 install"
        exit 1
    fi

    # Default integrity: local (allow local modifications by design)
    integrity_mode="local"
    if [[ -f "$meta_file" ]]; then
        integrity_mode=$(grep '^integrity=' "$meta_file" 2>/dev/null | cut -d= -f2- || echo "local")
    fi

    # Runtime override: WS_INTEGRITY=official forces official mode
    if [[ "${WS_INTEGRITY:-}" == "official" ]]; then
        integrity_mode="official"
    fi

    # Ensure workspace is newer than checksum
    if [[ "$dest" -ot "$sha_file" ]]; then
        echo "workspace appears older than its checksum file."
        echo "Run: $0 update  to restore the official release."
        exit 1
    fi

    # Verify SHA256 (suppress raw sha* warnings; we print our own)
    if ! (cd "$tools_dir" && hash_sha256 -c "workspace.sha256" >/dev/null 2>&1); then
        echo "Local workspace failed SHA256 verification."

        if [[ "$integrity_mode" == "local" ]]; then
            echo "Run:    $0 update  to restore the official release,"
            echo "or run: $0 rehash  to accept your recent modifications."
        else
            echo "Run: $0 update  to restore the official release."
        fi
        exit 1
    fi

    # Checksum passed; now it's fair to say we're running.
    if [[ "$integrity_mode" == "local" ]]; then
        echo "⚠️  Hash Check: Running locally modified WorkSpace script (integrity=local)." >&2
        echo "⚠️  Hash Check: To restore the official release, run: $0 update" >&2
    fi

    exec "$dest" "$@"
}

function PrintHelp() {
    cat <<EOF
Usage: $(basename "$0") <command> [args...]

Purpose:
  This script is the *WorkSpace Wrapper*.
  - It is stable and does not update itself.
  - It downloads, verifies, and runs the actual WorkSpace script
    (.ws/tools/workspace) from the WorkSpace project.
  - This lets workspace evolve independently while keeping a reliable entry point.

Wrapper commands:
  install [VERSION]   Download or update .ws/tools/workspace
  update  [VERSION]   Download or update .ws/tools/workspace
  uninstall           Remove workspace and metadata files
  rehash              Accept local edits and set a new trusted SHA256 baseline
  run [ARGS...]       Run workspace with ARGS (after integrity checks)
  version             Show this wrapper's version
  help                Show this help message

Notes:
  - workspace.sha256 and workspace.meta live in .ws/tools
  - Set VERBOSE=true for extra logs during update
  - Set WS_INTEGRITY=official to enforce official integrity checks at runtime
EOF
}

function PrintVersion() {
    cat <<'EOF'
__      __       _    ___                    __      __                           
\ \    / /__ _ _| |__/ __|_ __  __ _ __ ___  \ \    / / _ __ _ _ __ _ __  ___ _ _ 
 \ \/\/ / _ \ '_| / /\__ \ '_ \/ _` / _/ -_)  \ \/\/ / '_/ _` | '_ \ '_ \/ -_) '_|
  \_/\_/\___/_| |_\_\|___/ .__/\__,_\__\___|   \_/\_/|_| \__,_| .__/ .__/\___|_|  
                         |_|                                  |_|  |_|            
EOF
    echo "WorkSpace Wrapper: $VERSION"

    TOOL=".ws/tools/workspace"
    META=".ws/tools/workspace.meta"

    if [[ ! -f "$TOOL" ]]; then echo "WorkSpace: uninstalled" ; exit 0 ; fi

    [[ ! -x "$TOOL" ]] && chmod +x "$TOOL" 2>/dev/null || true

    TOOL_VERSION=$("$TOOL" ws-version 2>/dev/null || echo "unknown")

    local_integrity="local"
    if [[ -f "$META" ]]; then
        local_integrity=$(grep '^integrity=' "$META" 2>/dev/null | cut -d= -f2- || echo "local")
    fi

    echo ""
    echo "$TOOL_VERSION"
    if [[ "$local_integrity" == "local" ]]; then echo "With local changes." ; fi
}

# Portable SHA256 helper
function hash_sha256() {
    if   command -v sha256sum >/dev/null 2>&1; then sha256sum        "$@"
    elif command -v shasum    >/dev/null 2>&1; then shasum    -a 256 "$@"
    else echo "Error: No SHA256 tool found (sha256sum or shasum)." >&2 ; return 1
    fi
}

# Detect platform (OS-ARCH format)
function detect_platform() {
    local os arch
    
    # Detect OS
    case "$(uname -s)" in
        Linux*)     os="linux" ;;
        Darwin*)    os="darwin" ;;
        MINGW*|MSYS*|CYGWIN*) os="windows" ;;
        *)          echo "Error: Unsupported OS: $(uname -s)" >&2; return 1 ;;
    esac
    
    # Detect architecture
    case "$(uname -m)" in
        x86_64|amd64)   arch="amd64" ;;
        aarch64|arm64)  arch="arm64" ;;
        *)              echo "Error: Unsupported architecture: $(uname -m)" >&2; return 1 ;;
    esac
    
    echo "${os}-${arch}"
}

# Get binary name for platform (adds .exe for Windows)
function get_binary_name() {
    local platform="$1"
    if [[ "$platform" == windows-* ]]; then
        echo "workspace-${platform}.exe"
    else
        echo "workspace-${platform}"
    fi
}

function UninstallWorkspace() {
    local tools_dir=".ws/tools"
    local dest="$tools_dir/workspace"
    local sha_file="$tools_dir/workspace.sha256"
    local meta_file="$tools_dir/workspace.meta"

    rm -f "$dest" "$sha_file" "$meta_file"

    rmdir "$tools_dir" 2>/dev/null || true
    rmdir ".ws" 2>/dev/null || true

    echo "WorkSpace has been uninstalled."
}

function DownloadWorkspace() {
    WS_VERSION=${1:-latest}
    local tmpfile tmpsha256 expected_sha256 actual_sha256
    local tools_dir=".ws/tools"
    local dest="$tools_dir/workspace"
    local sha_file="$tools_dir/workspace.sha256"
    local meta_file="$tools_dir/workspace.meta"

    # Detect platform
    local platform binary_name
    if ! platform=$(detect_platform); then
        echo "Error: Failed to detect platform" >&2
        return 1
    fi
    binary_name=$(get_binary_name "$platform")

    tmpfile=$(mktemp "/tmp/workspace.XXXXXX")
    tmpsha256=$(mktemp "/tmp/workspace.sha256.XXXXXX")

    REPO_URL="https://github.com/NawaMan/WorkSpace"
    DWLD_URL="${REPO_URL}/releases/download"
    TOOL_URL="${DWLD_URL}/${WS_VERSION}/${binary_name}"
    SHA256_URL="${DWLD_URL}/${WS_VERSION}/${binary_name}.sha256"

    if [[ "$VERBOSE" == "true" ]]; then
        echo "Downloading workspace for platform: $platform"
        echo "Binary: $binary_name"
        echo "URL: $TOOL_URL"
    fi

    if ! curl -fsSLo "$tmpfile" "$TOOL_URL"; then
        echo "Error: Failed to download workspace from ${TOOL_URL}" >&2
        rm -f "$tmpfile" "$tmpsha256"
        return 1
    fi

    if ! curl -fsSLo "$tmpsha256" "$SHA256_URL"; then
        echo "Error: Failed to download workspace.sha256 from ${SHA256_URL}" >&2
        rm -f "$tmpfile" "$tmpsha256"
        return 1
    fi

    expected_sha256=$(awk '{print $1}' "$tmpsha256")
    if ! [[ "$expected_sha256" =~ ^[0-9a-fA-F]{64}$ ]]; then
        echo "Malformed SHA256 file: $expected_sha256" >&2
        rm -f "$tmpfile" "$tmpsha256"
        return 1
    fi

    actual_sha256=$(hash_sha256 "$tmpfile" | awk '{print $1}')

    if [[ "$expected_sha256" != "$actual_sha256" ]]; then
        echo "SHA256 mismatch for downloaded workspace" >&2
        rm -f "$tmpfile" "$tmpsha256"
        return 1
    fi

    chmod +x "$tmpfile"
    actual_version=$("$tmpfile" ws-version 2>/dev/null || echo "")

    mkdir -p "$tools_dir"

    # Install the verified tool
    mv    -f "$tmpfile" "$dest"
    chmod +x "$dest"

    # Write the checksum file for this exact file
    printf '%s  %s\n' "$actual_sha256" "workspace" > "$sha_file"

    {
        echo "version=${actual_version}"
        echo "platform=${platform}"
        echo "binary=${binary_name}"
        echo "url=${TOOL_URL}"
        echo "sha256=${actual_sha256}"
        echo "integrity=official"
        echo "downloaded_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    } > "$meta_file"

    rm -f "$tmpsha256"

    # IMPORTANT: enforce your integrity model
    # Tool *must* be newer than its checksum in trusted states.
    touch "$dest"

    if [[ "$VERBOSE" == "true" ]]; then
        echo "workspace downloaded, verified, and installed."
        echo "Workspace: $dest"
        echo "Metadata : $meta_file"
    fi
}

function RehashWorkspace() {
    local tools_dir=".ws/tools"
    local dest="$tools_dir/workspace"
    local sha_file="$tools_dir/workspace.sha256"
    local meta_file="$tools_dir/workspace.meta"

    if [[ ! -f "$dest" ]]; then
        echo "Error: workspace not found. Please run: $0 install" >&2
        return 1
    fi

    mkdir -p "$tools_dir"

    local actual_sha256
    actual_sha256=$(hash_sha256 "$dest" | awk '{print $1}')

    printf '%s  %s\n' "$actual_sha256" "workspace" > "$sha_file"

    {
        echo "version=local"
        echo "url=local"
        echo "sha256=${actual_sha256}"
        echo "integrity=local"
        echo "rehash_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    } > "$meta_file"

    touch "$dest"

    echo "workspace has been rehashed."
    echo "⚠️ This WorkSpace installation is now marked as locally modified (integrity=local)."
}

# Early handling of version/help so they don't require curl
case "${COMMAND}" in
    version) PrintVersion ; exit 0 ; ;;
    help)    PrintHelp    ; exit 0 ; ;;
esac

# Need curl for install/run/update/rehash/uninstall
if ! command -v curl >/dev/null 2>&1; then
    echo "Error: curl is required but was not found." >&2
    exit 1
fi

Main "$@"
