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

- Add `BOOTH_CACHE_DIR` variable: `${XDG_CACHE_HOME:-$HOME/.cache}/booth`
- Add helper function `get_cache_version_dir()`:
  ```bash
  get_cache_version_dir() {
      local version="$1"
      echo "${BOOTH_CACHE_DIR}/versions/${version}"
  }
  ```
- Add helper function `get_binary_path()`:
  ```bash
  get_binary_path() {
      local version="$1"
      local platform="$2"
      echo "$(get_cache_version_dir "$version")/coding-booth-${platform}"
  }
  ```

### Task 2: Update installation flow

**File:** `booth` (wrapper script)

Modify `DownloadBooth()` function:
- Download to `~/.cache/booth/versions/<version>/` instead of `.booth/tools/`
- Set `chmod 744` on each binary after download
- Touch binaries after verification
- Only write lock file to `.booth/tools/`

### Task 3: Update run flow

**File:** `booth` (wrapper script)

Modify run logic:
- Read version from `.booth/tools/coding-booth.lock`
- Look up binary in central cache
- Verify from central cache
- Execute from central cache

### Task 4: Update verification logic

**File:** `booth` (wrapper script)

Modify verification:
- SHA256 file location: `~/.cache/booth/versions/<version>/coding-booth.sha256`
- Binary location: `~/.cache/booth/versions/<version>/coding-booth-<platform>`
- Same freshness + checksum checks

### Task 5: Update .gitignore handling

**File:** `booth` (wrapper script)

- Remove binary entries from `.booth/.gitignore` (no longer needed)
- Keep only:
  ```gitignore
  # Lock file is version-controlled
  # Binaries are in ~/.cache/booth/ (not here)
  ```

### Task 6: Implement `./booth tools-cache list`

**File:** `booth` (wrapper script)

- Add `tools-cache` command with `list` subcommand
- Scan `<CACHE_DIR>/versions/` directories
- Calculate and display size per version
- Show which platform binaries exist
- Display total cache size and location

### Task 7: Implement `./booth tools-cache clean`

**File:** `booth` (wrapper script)

- Add `clean` subcommand to `tools-cache`
- Support `--all` flag to remove everything
- Support specific version argument
- Interactive mode when no arguments
- Print freed disk space summary

### Task 8: Update documentation

**Files:**
- `docs/implementations/WRAPPER.md` — update architecture diagram and file structure
- `README.md` — update any references to `.booth/tools/` containing binaries

### Task 9: Migration path (optional)

For existing projects with binaries in `.booth/tools/`:
- Wrapper detects old layout
- Prints migration message
- Optionally moves binaries to central cache
- Cleans up old files

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
