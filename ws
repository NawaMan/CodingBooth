#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.


# WorkSpace Wrapper (ws)
# Downloads, verifies, and runs the platform-specific WorkSpace binary.
# Install: curl -fsSL https://github.com/NawaMan/WorkSpace/releases/download/latest/ws | bash

set -euo pipefail
trap 'status=$?; echo "❌ Error on line $LINENO (exit $status)" >&2; exit "$status"' ERR

# --- PIPE INSTALL DETECTION ---
# Detect if running via pipe (curl ... | bash)
# When piped, $0 is the shell name, not a script path
if [[ "$0" == "bash" || "$0" == "-bash" || "$0" == "/bin/bash" || \
      "$0" == "sh"   || "$0" == "-sh"   || "$0" == "/bin/sh"   || \
      "$0" == "zsh"  || "$0" == "-zsh"  || "$0" == "/bin/zsh" ]]; then
    echo "Installing WorkSpace wrapper..."
    curl -fsSL -o ws https://github.com/NawaMan/WorkSpace/releases/download/latest/ws
    chmod +x ws
    ./ws install
    ./ws help
    exit 0
fi

VERSION=0.5.0
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
    sha_file="$tools_dir/workspace.sha256"
    meta_file="$tools_dir/workspace.meta"

    # Detect current platform and get the correct binary
    local platform binary_name dest
    if ! platform=$(detect_platform); then
        echo "Error: Failed to detect platform" >&2
        exit 1
    fi
    binary_name=$(get_binary_name "$platform")
    dest="$tools_dir/$binary_name"

    if [[ ! -f "$dest" || ! -f "$sha_file" || ! -f "$meta_file" ]]; then
        echo "WorkSpace is not installed correctly for platform: $platform"
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

    # Ensure workspace binary is newer than checksum
    if [[ "$dest" -ot "$sha_file" ]]; then
        echo "workspace binary appears older than its checksum file."
        echo "Run: $0 update  to restore the official release."
        exit 1
    fi

    # Verify SHA256 for this platform's binary
    local expected_sha256 actual_sha256
    expected_sha256=$(grep "  $binary_name\$" "$sha_file" 2>/dev/null | awk '{print $1}')
    if [[ -z "$expected_sha256" ]]; then
        echo "No SHA256 entry found for $binary_name"
        echo "Run: $0 update  to restore the official release."
        exit 1
    fi

    actual_sha256=$(hash_sha256 "$dest" | awk '{print $1}')
    if [[ "$expected_sha256" != "$actual_sha256" ]]; then
        echo "Local workspace ($binary_name) failed SHA256 verification."

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

    local tools_dir=".ws/tools"
    local META="$tools_dir/workspace.meta"

    # Detect current platform and get the correct binary
    local platform binary_name TOOL
    platform=$(detect_platform 2>/dev/null || echo "unknown")
    binary_name=$(get_binary_name "$platform")
    TOOL="$tools_dir/$binary_name"

    if [[ ! -f "$TOOL" ]]; then
        echo "WorkSpace: uninstalled (no binary for $platform)"
        exit 0
    fi

    [[ ! -x "$TOOL" ]] && chmod +x "$TOOL" 2>/dev/null || true

    TOOL_VERSION=$("$TOOL" ws-version 2>/dev/null || echo "unknown")

    local_integrity="local"
    if [[ -f "$META" ]]; then
        local_integrity=$(grep '^integrity=' "$META" 2>/dev/null | cut -d= -f2- || echo "local")
    fi

    echo ""
    echo "$TOOL_VERSION"
    echo "Platform: $platform"
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

# All supported platforms (5 total)
ALL_PLATFORMS=(
    "linux-amd64"
    "linux-arm64"
    "darwin-amd64"
    "darwin-arm64"
    "windows-amd64"
)

function UninstallWorkspace() {
    local tools_dir=".ws/tools"
    local sha_file="$tools_dir/workspace.sha256"
    local meta_file="$tools_dir/workspace.meta"

    # Remove all platform binaries
    for platform in "${ALL_PLATFORMS[@]}"; do
        local binary_name
        binary_name=$(get_binary_name "$platform")
        rm -f "$tools_dir/$binary_name"
    done

    rm -f "$sha_file" "$meta_file"

    rmdir "$tools_dir" 2>/dev/null || true
    rmdir ".ws" 2>/dev/null || true

    echo "WorkSpace has been uninstalled."
}

function DownloadWorkspace() {
    WS_VERSION=${1:-latest}
    local tools_dir=".ws/tools"
    local sha_file="$tools_dir/workspace.sha256"
    local meta_file="$tools_dir/workspace.meta"

    REPO_URL="https://github.com/NawaMan/WorkSpace"
    DWLD_URL="${REPO_URL}/releases/download"

    mkdir -p "$tools_dir"

    # Clear previous SHA256 file (will rebuild with all binaries)
    > "$sha_file"

    local actual_version=""
    local current_platform
    current_platform=$(detect_platform 2>/dev/null || echo "unknown")
    local download_count=0
    local fail_count=0

    echo "Downloading WorkSpace binaries for all platforms..."

    for platform in "${ALL_PLATFORMS[@]}"; do
        local binary_name
        binary_name=$(get_binary_name "$platform")
        local dest="$tools_dir/$binary_name"
        local TOOL_URL="${DWLD_URL}/${WS_VERSION}/${binary_name}"
        local SHA256_URL="${DWLD_URL}/${WS_VERSION}/${binary_name}.sha256"

        if [[ "$VERBOSE" == "true" ]]; then
            echo "  Downloading: $binary_name"
        else
            echo -n "  $platform ... "
        fi

        local tmpfile tmpsha256
        tmpfile=$(mktemp "/tmp/workspace.XXXXXX")
        tmpsha256=$(mktemp "/tmp/workspace.sha256.XXXXXX")

        # Download binary
        if ! curl -fsSLo "$tmpfile" "$TOOL_URL"; then
            echo "FAILED (download)"
            rm -f "$tmpfile" "$tmpsha256"
            : $((fail_count++))
            continue
        fi

        # Download SHA256
        if ! curl -fsSLo "$tmpsha256" "$SHA256_URL"; then
            echo "FAILED (sha256)"
            rm -f "$tmpfile" "$tmpsha256"
            : $((fail_count++))
            continue
        fi

        # Verify SHA256
        local expected_sha256 actual_sha256
        expected_sha256=$(awk '{print $1}' "$tmpsha256")
        if ! [[ "$expected_sha256" =~ ^[0-9a-fA-F]{64}$ ]]; then
            echo "FAILED (malformed sha256)"
            rm -f "$tmpfile" "$tmpsha256"
            : $((fail_count++))
            continue
        fi

        actual_sha256=$(hash_sha256 "$tmpfile" | awk '{print $1}')
        if [[ "$expected_sha256" != "$actual_sha256" ]]; then
            echo "FAILED (sha256 mismatch)"
            rm -f "$tmpfile" "$tmpsha256"
            : $((fail_count++))
            continue
        fi

        # Install verified binary
        chmod +x "$tmpfile"
        mv -f "$tmpfile" "$dest"
        chmod +x "$dest"

        # Append to combined SHA256 file
        printf '%s  %s\n' "$actual_sha256" "$binary_name" >> "$sha_file"

        # Get version from current platform binary
        if [[ "$platform" == "$current_platform" && -z "$actual_version" ]]; then
            actual_version=$("$dest" ws-version 2>/dev/null || echo "")
        fi

        rm -f "$tmpsha256"
        : $((download_count++))

        if [[ "$VERBOSE" != "true" ]]; then
            echo "OK"
        fi
    done

    if [[ $fail_count -gt 0 ]]; then
        echo "Warning: $fail_count platform(s) failed to download" >&2
    fi

    if [[ $download_count -eq 0 ]]; then
        echo "Error: No binaries were downloaded successfully" >&2
        return 1
    fi

    # Write metadata
    {
        echo "version=${actual_version}"
        echo "platforms=${ALL_PLATFORMS[*]}"
        echo "download_count=${download_count}"
        echo "integrity=official"
        echo "downloaded_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    } > "$meta_file"

    # Touch all binaries to be newer than checksum
    for platform in "${ALL_PLATFORMS[@]}"; do
        local binary_name
        binary_name=$(get_binary_name "$platform")
        local dest="$tools_dir/$binary_name"
        [[ -f "$dest" ]] && touch "$dest"
    done

    echo "WorkSpace installed: $download_count binaries downloaded, verified, and installed."
    if [[ "$VERBOSE" == "true" ]]; then
        echo "Metadata: $meta_file"
    fi
}

function RehashWorkspace() {
    local tools_dir=".ws/tools"
    local sha_file="$tools_dir/workspace.sha256"
    local meta_file="$tools_dir/workspace.meta"

    # Check if at least one platform binary exists
    local found_any=false
    for platform in "${ALL_PLATFORMS[@]}"; do
        local binary_name
        binary_name=$(get_binary_name "$platform")
        if [[ -f "$tools_dir/$binary_name" ]]; then
            found_any=true
            break
        fi
    done

    if [[ "$found_any" != "true" ]]; then
        echo "Error: No workspace binaries found. Please run: $0 install" >&2
        return 1
    fi

    mkdir -p "$tools_dir"

    # Clear and rebuild SHA256 file for all existing binaries
    > "$sha_file"
    local rehash_count=0

    for platform in "${ALL_PLATFORMS[@]}"; do
        local binary_name
        binary_name=$(get_binary_name "$platform")
        local dest="$tools_dir/$binary_name"

        if [[ -f "$dest" ]]; then
            local actual_sha256
            actual_sha256=$(hash_sha256 "$dest" | awk '{print $1}')
            printf '%s  %s\n' "$actual_sha256" "$binary_name" >> "$sha_file"
            touch "$dest"
            : $((rehash_count++))
        fi
    done

    {
        echo "version=local"
        echo "platforms=${ALL_PLATFORMS[*]}"
        echo "rehash_count=${rehash_count}"
        echo "integrity=local"
        echo "rehash_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    } > "$meta_file"

    echo "WorkSpace has been rehashed ($rehash_count binaries)."
    echo "This installation is now marked as locally modified (integrity=local)."
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
