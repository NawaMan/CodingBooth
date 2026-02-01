# Plan: Centralized Binary Cache

## Goal

Move CodingBooth binaries from per-project `.booth/tools/` to a central user-level cache, improving storage efficiency and security.

## Current State

```
project/
└── .booth/
    └── tools/
        ├── coding-booth.lock
        ├── coding-booth.sha256
        ├── coding-booth-linux-amd64      # 5-8MB each
        ├── coding-booth-linux-arm64
        ├── coding-booth-darwin-amd64
        ├── coding-booth-darwin-arm64
        ├── coding-booth-windows-amd64.exe
        └── coding-booth-windows-arm64.exe
```

**Problems:**
- 30-48MB duplicated per project
- Binaries accessible inside container (security concern)
- Redundant downloads across projects

---

## Proposed State

### Central Cache Structure

```
<CACHE_DIR>/
└── versions/
    └── 0.13.0/
        ├── coding-booth.sha256           # checksums for all platforms
        ├── coding-booth-linux-amd64      # 744 permissions
        ├── coding-booth-linux-arm64
        ├── coding-booth-darwin-amd64
        ├── coding-booth-darwin-arm64
        ├── coding-booth-windows-amd64.exe
        └── coding-booth-windows-arm64.exe
```

**Platform-specific `<CACHE_DIR>`:**

| Platform | Location                 |
|----------|--------------------------|
| Linux    | `~/.cache/booth`         |
| macOS    | `~/Library/Caches/booth` |
| Windows  | `%LOCALAPPDATA%\booth`   |

### Project Structure (Simplified)

```
project/
└── .booth/
    └── tools/
        └── coding-booth.lock             # version reference only
```

**Lock file format (unchanged):**
```
version=0.13.0
downloaded_at=2025-01-27T12:34:56Z
```

---

## Security & Integrity

| Measure                  | Implementation                                            |
|--------------------------|-----------------------------------------------------------|
| **Permissions**          | `chmod 744` — owner rwx, others read-only                 |
| **Freshness check**      | Binary must be newer than sha256 file                     |
| **SHA256 verification**  | Verify checksum before every execution                    |
| **Touch after download** | `touch` binary after successful verification              |
| **Isolation**            | Binaries NOT in project folder, NOT mounted in container  |

---

## Wrapper Behavior Changes

### Installation (`./booth install [VERSION]`)

```
1. Determine version (from argument, or "latest")
2. Resolve "latest" → actual version number
3. Check ~/.cache/booth/versions/<version>/
4. If missing or incomplete:
   a. Create version directory
   b. Download all platform binaries to temp files
   c. Download sha256 file
   d. Verify each binary against sha256
   e. Move binaries to version directory
   f. chmod 744 each binary
   g. Touch each binary (newer than sha256)
5. Write/update .booth/tools/coding-booth.lock
```

### Run Mode (`./booth` or `./booth run`)

```
1. Read version from .booth/tools/coding-booth.lock
2. If no lock file: error "Run ./booth install first"
3. Determine platform (linux-amd64, darwin-arm64, etc.)
4. Locate binary (check LOCAL first, then CENTRAL):
   a. Check .booth/tools/coding-booth-<platform> (local)
   b. If not found, check <CACHE_DIR>/versions/<version>/coding-booth-<platform> (central)
5. Verify:
   a. Binary exists
   b. Binary newer than sha256 file
   c. SHA256 matches
6. If verification fails or binary not found:
   a. Auto-download this version to central cache
   b. Re-verify
7. exec binary with arguments
```

> **Note:** Local takes precedence. This allows projects with `--local` binaries to work
> even if central cache has the same version.

### Update (`./booth update [VERSION]`)

```
Same as install, but:
- If no version specified, use "latest"
- Always re-download (even if version exists in cache)
```

### Uninstall (`./booth uninstall`)

```
1. Remove .booth/tools/coding-booth.lock
2. Print message about `./booth tools-cache clean` for cache cleanup
```

### Tools Cache Management

#### List cached versions (`./booth tools-cache list`)

```
1. Scan <CACHE_DIR>/versions/
2. For each version directory:
   a. Show version number
   b. Show disk usage
   c. Show which platforms are cached
3. Show total cache size
```

**Example output:**
```
Cached binary versions:

  0.13.0    45.2 MB   [linux-amd64, linux-arm64, darwin-amd64, darwin-arm64]
  0.12.1    44.8 MB   [linux-amd64, darwin-arm64]

Total: 90.0 MB in 2 versions

Cache location: ~/.cache/booth
```

#### Clean cache (`./booth tools-cache clean`)

```
./booth tools-cache clean              # Interactive: prompt which versions to remove
./booth tools-cache clean --all        # Remove all cached versions
./booth tools-cache clean --unused     # Remove versions not used by any project (future)
./booth tools-cache clean 0.12.0       # Remove specific version
```

**Behavior:**
```
1. Parse arguments (--all, --unused, or specific version)
2. If no arguments: interactive mode
   a. List versions with sizes
   b. Prompt user to select versions to remove
3. If --all: remove entire <CACHE_DIR>/versions/
4. If --unused: (future) scan for lock files, remove unreferenced versions
5. If specific version: remove <CACHE_DIR>/versions/<version>/
6. Print summary of freed disk space
```

---

## Implementation Tasks

### Task 1: Update wrapper — central cache path logic

**File:** `booth` (wrapper script)

Add after line 39 (`VERBOSE="${VERBOSE:-true}"`):

```bash
# --- CENTRAL CACHE SETUP ---
# Platform-specific cache directory
get_cache_dir() {
    case "$(uname -s)" in
        Linux*)
            echo "${XDG_CACHE_HOME:-$HOME/.cache}/booth"
            ;;
        Darwin*)
            echo "$HOME/Library/Caches/booth"
            ;;
        MINGW*|MSYS*|CYGWIN*)
            if [[ -n "${LOCALAPPDATA:-}" ]]; then
                echo "$LOCALAPPDATA/booth"
            else
                echo "$HOME/AppData/Local/booth"
            fi
            ;;
        *)
            echo "${XDG_CACHE_HOME:-$HOME/.cache}/booth"
            ;;
    esac
}

BOOTH_CACHE_DIR="${BOOTH_CACHE_DIR:-$(get_cache_dir)}"

get_cache_version_dir() {
    local version="$1"
    echo "${BOOTH_CACHE_DIR}/versions/${version}"
}

# Find binary directory: local first, then central cache
# Returns directory path, or empty string if not found
find_binary_dir() {
    local version="$1"
    local platform="$2"
    local binary_name
    binary_name=$(get_binary_name "$platform")

    # Check local first (for --local mode)
    if [[ -f ".booth/tools/${binary_name}" ]]; then
        echo ".booth/tools"
        return 0
    fi

    # Then check central cache
    local central_dir
    central_dir="$(get_cache_version_dir "$version")"
    if [[ -f "${central_dir}/${binary_name}" ]]; then
        echo "$central_dir"
        return 0
    fi

    # Not found
    return 1
}
```

### Task 2: Update installation flow

**File:** `booth` (wrapper script)

Modify `DownloadBooth()` function. Key changes:

```bash
function DownloadBooth() {
    local CB_VERSION=${1:-latest}
    local LOCAL_MODE=${2:-false}  # NEW: --local flag

    local tools_dir=".booth/tools"
    local lock_file="$tools_dir/coding-booth.lock"

    # ... resolve actual_version from CB_VERSION ...

    # NEW: Determine target directory
    local target_dir sha_file
    if [[ "$LOCAL_MODE" == "true" ]]; then
        target_dir="$tools_dir"
        sha_file="$tools_dir/coding-booth.sha256"
    else
        target_dir="$(get_cache_version_dir "$actual_version")"
        sha_file="$target_dir/coding-booth.sha256"
    fi

    mkdir -p "$target_dir"
    mkdir -p "$tools_dir"  # Always need tools dir for lock file

    # Download binaries to $target_dir instead of $tools_dir
    # ... existing download loop, but use $target_dir ...

    # NEW: chmod 744 instead of +x
    chmod 744 "$dest"

    # Write lock file (always in .booth/tools/)
    {
        echo "version=${actual_version}"
        echo "downloaded_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        [[ "$LOCAL_MODE" == "true" ]] && echo "local=true"
    } > "$lock_file"
}
```

### Task 3: Update run flow

**File:** `booth` (wrapper script)

Modify `Main()` function's RUN MODE section:

```bash
### --- RUN MODE --- ###
local tools_dir=".booth/tools"
local lock_file="$tools_dir/coding-booth.lock"

# Read version and local mode from lock file
if [[ ! -f "$lock_file" ]]; then
    echo "CodingBooth is not installed."
    echo "Please run: $0 install"
    exit 1
fi

local lock_version lock_local
lock_version=$(grep '^version=' "$lock_file" 2>/dev/null | cut -d= -f2-)
lock_local=$(grep '^local=' "$lock_file" 2>/dev/null | cut -d= -f2- || echo "false")

if [[ -z "$lock_version" ]]; then
    echo "Invalid lock file: missing version"
    exit 1
fi

# Detect platform
local platform binary_name
platform=$(detect_platform) || exit 1
binary_name=$(get_binary_name "$platform")

# Find binary directory (local first, then central)
local binary_dir sha_file dest
if ! binary_dir=$(find_binary_dir "$lock_version" "$platform"); then
    # Binary not found, auto-download
    echo "Binary missing, downloading version $lock_version..."
    DownloadBooth "$lock_version" "$lock_local"
    binary_dir=$(find_binary_dir "$lock_version" "$platform") || {
        echo "Failed to download binary"
        exit 1
    }
fi

sha_file="$binary_dir/coding-booth.sha256"
dest="$binary_dir/$binary_name"

# ... existing verification logic using $sha_file and $dest ...

exec "$dest" "$@"
```

### Task 4: Update verification logic

Verification logic remains the same, but now uses paths from `find_binary_dir()`:

```bash
# Ensure binary is newer than checksum
if [[ "$dest" -ot "$sha_file" ]]; then
    echo "Binary appears older than its checksum file."
    echo "Run: $0 update  to restore the official release."
    exit 1
fi

# Verify SHA256
local expected_sha256 actual_sha256
expected_sha256=$(grep "  $binary_name\$" "$sha_file" 2>/dev/null | awk '{print $1}')
if [[ -z "$expected_sha256" ]]; then
    echo "No SHA256 entry found for $binary_name"
    exit 1
fi

actual_sha256=$(hash_sha256 "$dest" | awk '{print $1}')
if [[ "$expected_sha256" != "$actual_sha256" ]]; then
    echo "Binary failed SHA256 verification."
    exit 1
fi
```

### Task 5: Update .gitignore handling

In `DownloadBooth()`, simplify .gitignore (only needed for local mode):

```bash
# Only create .gitignore for local mode
if [[ "$LOCAL_MODE" == "true" ]]; then
    cat > ".booth/.gitignore" <<'GITIGNORE'
# Binaries excluded - re-download from lock version
tools/coding-booth-*
tools/*.sha256
GITIGNORE
else
    # Central cache mode - no binaries in project
    cat > ".booth/.gitignore" <<'GITIGNORE'
# Lock file is version-controlled
# Binaries are in ~/.cache/booth/ (not here)
GITIGNORE
fi
```

### Task 6: Implement `./booth tools-cache list`

Add new function and command dispatch:

```bash
function ToolsCacheList() {
    local versions_dir="${BOOTH_CACHE_DIR}/versions"

    if [[ ! -d "$versions_dir" ]]; then
        echo "No cached versions found."
        echo "Cache location: $BOOTH_CACHE_DIR"
        return 0
    fi

    echo "Cached binary versions:"
    echo ""

    local total_size=0
    local version_count=0

    for version_dir in "$versions_dir"/*/; do
        [[ ! -d "$version_dir" ]] && continue

        local version
        version=$(basename "$version_dir")

        # Calculate size
        local size_bytes size_human
        size_bytes=$(du -sb "$version_dir" 2>/dev/null | cut -f1 || echo 0)
        size_human=$(numfmt --to=iec-i --suffix=B "$size_bytes" 2>/dev/null || echo "${size_bytes}B")

        # List platforms
        local platforms=()
        for bin in "$version_dir"/coding-booth-*; do
            [[ -f "$bin" ]] || continue
            local name
            name=$(basename "$bin")
            name=${name#coding-booth-}
            name=${name%.exe}
            platforms+=("$name")
        done

        printf "  %-12s %10s   [%s]\n" "$version" "$size_human" "${platforms[*]}"

        total_size=$((total_size + size_bytes))
        : $((version_count++))
    done

    echo ""
    local total_human
    total_human=$(numfmt --to=iec-i --suffix=B "$total_size" 2>/dev/null || echo "${total_size}B")
    echo "Total: $total_human in $version_count version(s)"
    echo ""
    echo "Cache location: $BOOTH_CACHE_DIR"
}
```

Add to command dispatch:

```bash
case "${COMMAND}" in
    tools-cache)
        shift
        case "${1:-list}" in
            list)  ToolsCacheList ;;
            clean) shift; ToolsCacheClean "$@" ;;
            *)     echo "Unknown tools-cache command: $1"; exit 1 ;;
        esac
        exit 0
        ;;
    # ... existing cases ...
esac
```

### Task 7: Implement `./booth tools-cache clean`

```bash
function ToolsCacheClean() {
    local versions_dir="${BOOTH_CACHE_DIR}/versions"

    if [[ ! -d "$versions_dir" ]]; then
        echo "No cached versions to clean."
        return 0
    fi

    # Parse arguments
    local clean_all=false
    local target_version=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --all) clean_all=true; shift ;;
            --unused) echo "Warning: --unused not yet implemented"; shift ;;
            -*) echo "Unknown option: $1"; exit 1 ;;
            *) target_version="$1"; shift ;;
        esac
    done

    if [[ "$clean_all" == "true" ]]; then
        local size_before
        size_before=$(du -sb "$versions_dir" 2>/dev/null | cut -f1 || echo 0)

        rm -rf "$versions_dir"

        local size_human
        size_human=$(numfmt --to=iec-i --suffix=B "$size_before" 2>/dev/null || echo "${size_before}B")
        echo "Removed all cached versions. Freed $size_human"
        return 0
    fi

    if [[ -n "$target_version" ]]; then
        local target_dir="$versions_dir/$target_version"
        if [[ ! -d "$target_dir" ]]; then
            echo "Version $target_version not found in cache."
            return 1
        fi

        local size_before
        size_before=$(du -sb "$target_dir" 2>/dev/null | cut -f1 || echo 0)

        rm -rf "$target_dir"

        local size_human
        size_human=$(numfmt --to=iec-i --suffix=B "$size_before" 2>/dev/null || echo "${size_before}B")
        echo "Removed version $target_version. Freed $size_human"
        return 0
    fi

    # Interactive mode: list and prompt
    ToolsCacheList
    echo ""
    read -rp "Enter version to remove (or 'all'): " choice

    if [[ "$choice" == "all" ]]; then
        ToolsCacheClean --all
    elif [[ -n "$choice" ]]; then
        ToolsCacheClean "$choice"
    else
        echo "No version selected."
    fi
}
```

### Task 8: Update help message and documentation

**Update `PrintHelp()` in `booth`:**

```bash
function PrintHelp() {
    cat <<EOF
Usage: ./$(basename "$0") <command> [args...]

Purpose:
  This script is the *CodingBooth Wrapper*.
  - It downloads, verifies, and runs the CodingBooth binary.
  - Binaries are cached in ~/.cache/booth/ (shared across projects).

Wrapper commands:
  install [VERSION]       Download binaries to central cache
  install --local [VER]   Download binaries to .booth/tools/ (project-local)
  update  [VERSION]       Re-download binaries (force refresh)
  uninstall               Remove project lock file

  tools-cache list        Show cached binary versions and sizes
  tools-cache clean       Interactively remove cached versions
  tools-cache clean --all Remove all cached versions
  tools-cache clean VER   Remove specific version

  run [ARGS...]           Run booth with ARGS (after integrity checks)
  version                 Show version information
  help                    Show this help message

Cache locations:
  Linux:   ~/.cache/booth/
  macOS:   ~/Library/Caches/booth/
  Windows: %LOCALAPPDATA%\\booth\\

Notes:
  - Lock file (.booth/tools/coding-booth.lock) is version-controlled
  - Binaries are auto-downloaded when lock file exists but binary missing
  - Use --local to store binaries in project (for CI/CD or portable use)
EOF
}
```

**Files to update:**
- `docs/implementations/WRAPPER.md` — update architecture diagram and file structure
- `README.md` — update any references to `.booth/tools/` containing binaries

Key updates:
- Document new cache location structure
- Document `tools-cache list` and `tools-cache clean` commands
- Document `--local` flag for install/update
- Update file structure diagrams

### Task 9: Migration path (optional)

Add detection in `Main()`:

```bash
# Migration: detect old layout (binaries in .booth/tools/)
local old_binary="$tools_dir/coding-booth-$(detect_platform)"
if [[ -f "$old_binary" && ! -f "$lock_file" ]]; then
    echo "⚠️  Detected old CodingBooth layout."
    echo "   Binaries in .booth/tools/ are deprecated."
    echo "   Run: $0 install  to migrate to central cache."
fi
```

---

## Directory Choice: `~/.cache/booth`

Using `~/.cache/booth` follows XDG Base Directory spec:
- `XDG_CACHE_HOME` defaults to `~/.cache`
- Cache is for "non-essential data that can be regenerated"
- Binaries can be re-downloaded, so this fits

**Alternative considered:** `~/.booth`
- Simpler path
- But mixes with potential future config in `~/.config/booth`

**Platform-specific paths:**

```bash
get_cache_dir() {
    case "$(uname -s)" in
        Linux*)
            echo "${XDG_CACHE_HOME:-$HOME/.cache}/booth"
            ;;
        Darwin*)
            echo "$HOME/Library/Caches/booth"
            ;;
        MINGW*|MSYS*|CYGWIN*)
            # Windows via Git Bash/MSYS2/Cygwin
            if [[ -n "$LOCALAPPDATA" ]]; then
                echo "$LOCALAPPDATA/booth"
            else
                # Fallback if LOCALAPPDATA not set
                echo "$HOME/AppData/Local/booth"
            fi
            ;;
        *)
            # Unknown platform, use XDG-style fallback
            echo "${XDG_CACHE_HOME:-$HOME/.cache}/booth"
            ;;
    esac
}

BOOTH_CACHE_DIR="${BOOTH_CACHE_DIR:-$(get_cache_dir)}"
```

| Platform | Cache Location                                                      |
|----------|---------------------------------------------------------------------|
| Linux    | `~/.cache/booth` (or `$XDG_CACHE_HOME/booth`)                       |
| macOS    | `~/Library/Caches/booth`                                            |
| Windows  | `%LOCALAPPDATA%\booth` (e.g., `C:\Users\<user>\AppData\Local\booth`) |

**Override:** Users can set `BOOTH_CACHE_DIR` environment variable to customize

---

## Permissions Detail

```bash
chmod 744 coding-booth-*
```

| Permission       | Meaning                  |
|------------------|--------------------------|
| Owner: `rwx` (7) | Can read, write, execute |
| Group: `r--` (4) | Can read only            |
| Other: `r--` (4) | Can read only            |

This prevents other users/processes from modifying the binaries while allowing execution by owner.

---

## Rollback Plan

If issues arise:
1. Delete `~/.cache/booth/`
2. Revert wrapper to previous version
3. Run `./booth install` to restore per-project binaries

---

## Testing Checklist

- [ ] Fresh install on empty cache
- [ ] Install specific version
- [ ] Install "latest"
- [ ] Run with cached binary
- [ ] Run triggers auto-download when cache missing
- [ ] Multiple projects sharing same version
- [ ] Multiple projects with different versions
- [ ] SHA256 verification failure handling
- [ ] Binary tampering detection (modify binary, expect failure)
- [ ] Permissions are 744 after install
- [ ] Binary is newer than sha256 after install
- [ ] `tools-cache list` shows correct versions and sizes
- [ ] `tools-cache clean` removes specific version
- [ ] `tools-cache clean --all` removes entire cache
- [ ] Works on Linux
- [ ] Works on macOS
- [ ] Works on Windows (Git Bash/MSYS2)

---

## Local Mode Flag

### Option: `--local` flag

Allow users to opt into per-project binary storage (the old behavior):

```bash
./booth install --local          # Store binaries in .booth/tools/
./booth install                  # Store binaries in ~/.cache/booth/ (default)
```

### Use Cases for Local Mode

| Use Case                  | Why Local                                          |
|---------------------------|----------------------------------------------------|
| CI/CD pipelines           | Self-contained, no shared cache between jobs       |
| Air-gapped environments   | Project folder is the only writable location       |
| Portable projects         | USB drive, shared folder — everything in one place |
| Testing specific versions | Isolate from other projects                        |

### Implementation

**Lock file extended format:**
```
version=0.13.0
downloaded_at=2025-01-27T12:34:56Z
local=true
```

The `local=true` line indicates binaries are in `.booth/tools/` instead of central cache.

**Wrapper logic:**

```bash
# During install
if [[ "$LOCAL_MODE" == "true" ]]; then
    BINARY_DIR=".booth/tools"
else
    BINARY_DIR="$(get_cache_dir)/versions/${VERSION}"
fi

# During run — check local first, then central
find_binary() {
    local version="$1"
    local platform="$2"
    local binary_name="coding-booth-${platform}"

    # Check local first
    if [[ -f ".booth/tools/${binary_name}" ]]; then
        echo ".booth/tools"
        return 0
    fi

    # Then check central cache
    local central_dir="$(get_cache_dir)/versions/${version}"
    if [[ -f "${central_dir}/${binary_name}" ]]; then
        echo "$central_dir"
        return 0
    fi

    # Not found — will need to download
    return 1
}
```

**Config file support:**

```toml
# .booth/config.toml
local-binaries = true    # Always use local mode for this project
```

### Directory Structure Comparison

**Default (centralized):**
```
~/.cache/booth/versions/0.13.0/
├── coding-booth.sha256
└── coding-booth-*

project/.booth/tools/
└── coding-booth.lock        # local=false or absent
```

**Local mode:**
```
project/.booth/tools/
├── coding-booth.lock        # local=true
├── coding-booth.sha256
└── coding-booth-*           # 744 permissions
```

### Security in Local Mode

When `local=true`:
- Binaries ARE mounted in container (same as current behavior)
- Still verify SHA256 before execution
- Still use 744 permissions
- User accepts the trade-off for portability

---

## Updated Implementation Tasks (with Local Mode)

### Task 1: Update wrapper — central cache path logic

(unchanged, but add local mode detection)

### Task 1b: Add `--local` flag parsing

**File:** `booth` (wrapper script)

- Parse `--local` flag in install/update commands
- Check `local-binaries` in config.toml
- Set `LOCAL_MODE=true/false`

### Task 2: Update installation flow

**File:** `booth` (wrapper script)

- If `LOCAL_MODE=true`: download to `.booth/tools/`
- If `LOCAL_MODE=false`: download to `~/.cache/booth/versions/<version>/`
- Write `local=true` or omit line in lock file

### Task 3: Update run flow

**File:** `booth` (wrapper script)

- Read `local=` from lock file
- Look up binary in correct location
- Verify and execute

(Tasks 4-9 unchanged)

---

## Questions for Review

1. **Cache cleanup policy?** — Should we auto-prune old versions, or leave that to users? → Manual via `./booth tools-cache clean`
2. **Concurrent access?** — Multiple terminals installing same version simultaneously — use lock file?
3. **Offline mode?** — If cache has version but can't verify (no network), should we trust it?
4. ~~**Flag name?** — `--local` vs `--project` vs `--portable`?~~ → Decided: `--local`
