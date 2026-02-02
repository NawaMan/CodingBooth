# Wrapper Implementation

> [!IMPORTANT]
> **Why this matters:** The wrapper provides a stable, version-controlled entry point that can manage, verify, and run the actual CodingBooth binary without requiring users to manually download or update it.

**A single, stable script that handles everything.**
The `booth` wrapper script is a lightweight shell script that downloads, verifies, and executes the platform-specific CodingBooth binary. It allows CodingBooth to evolve independently while providing users with a reliable, self-updating entry point. The wrapper handles multi-platform support, cryptographic verification, and automatic recovery — all while remaining simple enough to audit and commit to version control.

The wrapper is **location-based**: it operates relative to its own location, not the current working directory. This means `/path/to/project/booth` works correctly from any directory.

This document explains how the CodingBooth wrapper works internally.

---

## The Problem

Distributing a CLI tool across multiple platforms presents challenges:

- **Binary management** — Users need the correct binary for their OS and architecture
- **Version control** — Project repos shouldn't contain large binaries
- **Integrity verification** — Downloaded binaries must be verified against tampering
- **Updates** — Users need a way to update without manual downloads
- **Portability** — The entry point must work across Linux, macOS, and Windows

---

## The Solution: Two-Layer Architecture

CodingBooth uses a two-layer approach with a shared cache:

```
booth (wrapper)              — Small bash script, committed to repo
    │
    ▼ downloads, verifies, executes
    │
~/.cache/codingbooth/versions/     — Shared binary cache (default)
    └── 0.13.0/
        └── codingbooth-*   — Platform-specific binaries
```

| Layer                            | Purpose                              | Version Controlled |
|----------------------------------|--------------------------------------|--------------------|
| `booth` (wrapper)                | Stable entry point, manages binaries | Yes                |
| `.booth/tools/codingbooth.lock` | Version reference                    | Yes                |
| `codingbooth-*` (binary)        | Actual launcher logic                | No (in cache)      |

### Cache Modes

The wrapper supports two cache modes:

| Mode               | Location                | Use Case                                   |
|--------------------|-------------------------|--------------------------------------------|
| `shared` (default) | `~/.cache/codingbooth/` | Normal development, shared across projects |
| `local`            | `.booth/tools/`         | CI/CD, air-gapped, portable environments   |

---

## Supported Platforms

The wrapper supports six platform combinations:

| Platform        | Binary Name                       |
|-----------------|-----------------------------------|
| `linux-amd64`   | `codingbooth-linux-amd64`        |
| `linux-arm64`   | `codingbooth-linux-arm64`        |
| `darwin-amd64`  | `codingbooth-darwin-amd64`       |
| `darwin-arm64`  | `codingbooth-darwin-arm64`       |
| `windows-amd64` | `codingbooth-windows-amd64.exe`  |
| `windows-arm64` | `codingbooth-windows-arm64.exe`  |

Platform detection uses `uname -s` (OS) and `uname -m` (architecture):

```bash
# OS detection
case "$(uname -s)" in
    Linux*)     os="linux" ;;
    Darwin*)    os="darwin" ;;
    MINGW*|MSYS*|CYGWIN*) os="windows" ;;
esac

# Architecture detection
case "$(uname -m)" in
    x86_64|amd64)   arch="amd64" ;;
    aarch64|arm64)  arch="arm64" ;;
esac
```

---

## Command Dispatch

The wrapper handles these commands:

| Command                            | Description                                      |
|------------------------------------|--------------------------------------------------|
| `install [VERSION]`                | Download binaries (skips if already up-to-date)  |
| `install --cache=shared [VERSION]` | Download to shared cache (explicit)              |
| `install --cache=local [VERSION]`  | Download to .booth/tools/                        |
| `update [VERSION]`                 | Re-download binaries (force refresh)             |
| `uninstall`                        | Remove lock file and local binaries              |
| `tools-cache list`                 | Show cached versions and sizes                   |
| `tools-cache clean`                | Interactively remove cached versions             |
| `tools-cache clean --all`          | Remove all cached versions                       |
| `tools-cache clean VERSION`        | Remove specific version                          |
| `run [ARGS...]`                    | Execute binary (after verification)              |
| `shell-config`                     | Add 'booth' command to your shell (bash/zsh)     |
| `version`                          | Show wrapper and binary versions                 |
| `help`                             | Show usage information                           |

Default command (no arguments): `run`

```bash
# These are equivalent:
./booth
./booth run

# Pass arguments to the binary:
./booth --variant codeserver
./booth run --variant codeserver

# Install specific version (downloads only if needed):
./booth install 0.13.0
./booth install                   # Uses "latest"

# Cache management:
./booth tools-cache list           # Show cached versions
./booth tools-cache clean --all    # Remove all cached versions
./booth tools-cache clean 0.12.0   # Remove specific version
```

---

## Pipe Installation Detection

The wrapper detects when run via pipe (curl | bash) and auto-installs:

```bash
# When piped, $0 is the shell name, not a script path
if [[ "$0" == "bash" || "$0" == "-bash" || "$0" == "/bin/bash" || ... ]]; then
    echo "Installing CodingBooth wrapper..."
    curl -fsSL -o booth https://github.com/.../booth
    chmod +x booth
    ./booth install
    exit 0
fi
```

This enables the one-liner installation:

```bash
curl -fsSL https://github.com/NawaMan/WorkSpace/releases/download/latest/booth | bash
```

---

## Script Location Resolution

The wrapper is **location-based**, meaning it operates relative to its own location rather than the current working directory. This is implemented using `BASH_SOURCE[0]` with symlink resolution:

```bash
get_script_dir() {
    local source="${BASH_SOURCE[0]}"
    while [[ -L "$source" ]]; do
        local dir
        dir="$(cd -P "$(dirname "$source")" && pwd)"
        source="$(readlink "$source")"
        [[ "$source" != /* ]] && source="$dir/$source"
    done
    cd -P "$(dirname "$source")" && pwd
}
SCRIPT_DIR="$(get_script_dir)"
```

### Why Location-Based?

| Approach          | Behavior                                                                   |
|-------------------|----------------------------------------------------------------------------|
| Current directory | `cd /tmp && /path/to/project/booth` looks for `/tmp/.booth/`               |
| Script location   | `cd /tmp && /path/to/project/booth` looks for `/path/to/project/.booth/`   |

The location-based approach is more suitable for CodingBooth because:

- **Per-project design**: The `booth` script is installed per-project alongside `.booth/`
- **Intuitive behavior**: Running a project's booth script always operates on that project
- **Symlink support**: Symlinks are followed to find the original project location
- **Subdirectory support**: Running `../booth` from a subdirectory works correctly
- **Safety**: Prevents accidental operation on the wrong directory

### Examples

```bash
# All of these work correctly:
./booth                              # From project root
../booth                             # From a subdirectory
/home/user/myproject/booth           # Absolute path from anywhere
cd /tmp && /home/user/myproject/booth  # From unrelated directory
```

---

## File Structure

### Shared Cache Mode (Default)

With `--cache=shared` (the default), binaries are stored in a user-level cache:

**Project directory:**
```
.booth/
├── .gitignore              # Notes about cache location
└── tools/
    └── codingbooth.lock   # Version reference only
```

**User cache (platform-specific):**

| Platform | Cache Location                                              |
|----------|-------------------------------------------------------------|
| Linux    | `~/.cache/codingbooth/` (or `$XDG_CACHE_HOME/codingbooth/`) |
| macOS    | `~/Library/Caches/codingbooth/`                             |
| Windows  | `%LOCALAPPDATA%\codingbooth\`                               |

```
~/.cache/codingbooth/
└── versions/
    └── 0.13.0/
        ├── codingbooth.sha256      # SHA256 checksums for all platforms
        ├── codingbooth-linux-amd64
        ├── codingbooth-linux-arm64
        ├── codingbooth-darwin-amd64
        ├── codingbooth-darwin-arm64
        └── codingbooth-windows-amd64.exe
```

### Local Cache Mode

With `--cache=local`, binaries are stored in the project:

```
.booth/
├── .gitignore              # Excludes binaries from git
└── tools/
    ├── codingbooth.lock   # Version metadata with cache=local
    ├── codingbooth.sha256 # SHA256 checksums for all platforms
    ├── codingbooth-linux-amd64
    ├── codingbooth-linux-arm64
    ├── codingbooth-darwin-amd64
    ├── codingbooth-darwin-arm64
    └── codingbooth-windows-amd64.exe
```

### Lock File Format

```
version=0.13.0
downloaded_at=2025-01-27T12:34:56Z
cache=shared
```

The `cache=` line indicates where binaries are stored:
- `cache=shared` — binaries in user cache (default)
- `cache=local` — binaries in `.booth/tools/`

### SHA256 File Format

Standard sha256sum format with all platform binaries:

```
abc123...  codingbooth-linux-amd64
def456...  codingbooth-linux-arm64
...
```

### .gitignore

For shared cache mode:
```gitignore
# Lock file is version-controlled
# Binaries are in ~/.cache/codingbooth/ (not here)
```

For local cache mode:
```gitignore
# Binaries excluded - re-download from lock version
tools/codingbooth-*
tools/*.sha256
```

---

## Download and Verification Flow

### Installation (`./booth install`)

```
User runs: ./booth install [VERSION]
    │
    ▼ Resolve script location (SCRIPT_DIR)
    │
    ├─► Validate VERSION (reject if starts with "--")
    │
    ├─► VERSION defaults to "latest"
    │
    ├─► Fetch version.txt to get actual version number
    │
    ├─► For each platform:
    │     ├─► Download .sha256 file
    │     ├─► If binary exists with matching checksum:
    │     │     └─► Skip download (already up-to-date)
    │     ├─► Otherwise:
    │     │     ├─► Download binary to temp file
    │     │     ├─► Verify SHA256 matches
    │     │     ├─► Move to target directory
    │     │     └─► Set permissions to 755
    │     └─► Append to combined sha256 file
    │
    ├─► Write lock file with version + timestamp
    │
    └─► Touch all binaries (newer than sha256 file)
```

> **Note:** VERSION is a positional argument, not a flag. Use `./booth install 0.13.0`, not `./booth install --version 0.13.0`.

### Run Mode (`./booth` or `./booth run`)

```
User runs: ./booth [args...]
    │
    ▼ Resolve script location (SCRIPT_DIR)
    │
    ├─► Read lock file for version and cache mode
    │     (from $SCRIPT_DIR/.booth/tools/codingbooth.lock)
    │
    ├─► Detect platform (linux-amd64, darwin-arm64, etc.)
    │
    ├─► Find binary directory:
    │     1. Check $SCRIPT_DIR/.booth/tools/ first (local mode)
    │     2. Check ~/.cache/codingbooth/versions/<version>/ (shared mode)
    │   │
    │   └─► If not found but lock file exists:
    │         Auto-download using cache mode from lock file
    │
    ├─► Verify binary is newer than sha256 file
    │
    ├─► Extract expected SHA256 for this platform
    │
    ├─► Compute actual SHA256 of binary
    │
    ├─► Compare checksums
    │   │
    │   └─► If mismatch: Exit with error
    │
    └─► exec binary with arguments
```

---

## SHA256 Verification

The wrapper uses a portable SHA256 helper that works across platforms:

```bash
function hash_sha256() {
    if   command -v sha256sum >/dev/null 2>&1; then sha256sum        "$@"
    elif command -v shasum    >/dev/null 2>&1; then shasum    -a 256 "$@"
    else echo "Error: No SHA256 tool found" >&2 ; return 1
    fi
}
```

- Linux typically has `sha256sum`
- macOS typically has `shasum`

---

## Integrity Checks

Multiple checks ensure binary integrity:

### 1. Binary Freshness Check

```bash
# Binary must be newer than checksum file
if [[ "$dest" -ot "$sha_file" ]]; then
    echo "booth binary appears older than its checksum file."
    exit 1
fi
```

This detects if someone replaced the binary after installation.

### 2. SHA256 Verification

```bash
expected_sha256=$(grep "  $binary_name\$" "$sha_file" | awk '{print $1}')
actual_sha256=$(hash_sha256 "$dest" | awk '{print $1}')

if [[ "$expected_sha256" != "$actual_sha256" ]]; then
    echo "Local booth ($binary_name) failed SHA256 verification."
    exit 1
fi
```

### 3. Download-Time Verification

During installation, each binary is verified against the release's `.sha256` file before being moved into place.

---

## Auto-Recovery

If the binary is missing but the lock file exists, the wrapper auto-downloads:

```bash
# Find binary in local or shared cache
if ! binary_dir=$(find_binary_dir "$lock_version" "$platform"); then
    echo "Binary missing, downloading version $lock_version..."
    DownloadBooth "$lock_version" "$lock_cache"
    binary_dir=$(find_binary_dir "$lock_version" "$platform")
fi
```

The `find_binary_dir()` function checks:
1. `.booth/tools/` first (for local mode compatibility)
2. `~/.cache/codingbooth/versions/<version>/` (shared cache)

This enables:
- Cloning a repo and running `./booth` immediately (downloads correct version)
- Team members with different platforms sharing the same lock file
- Recovery from accidental binary deletion
- Sharing binaries across multiple projects (with shared cache)

---

## Design Decisions

### Why Location-Based Instead of Current Directory?

The wrapper resolves paths relative to its own location (`$SCRIPT_DIR/.booth/`) rather than the current working directory (`.booth/`):

**Pros:**
- Intuitive for per-project scripts (running a project's booth works on that project)
- Safe from accidental wrong-directory execution
- Works when running from subdirectories (`../booth`)
- Supports symlinks (follows to original project)

**Cons:**
- Cannot use a single booth script for multiple projects (not the intended use case)

The per-project design of CodingBooth (where each project has its own `booth` and `.booth/`) makes location-based resolution the natural choice.

### Why Shared Cache by Default?

The wrapper uses a user-level cache (`~/.cache/codingbooth/`) by default:

**Pros:**
- Saves 30-50MB per project (binaries not duplicated)
- Faster installs (reuses existing binaries)
- Binaries not mounted in container (security)
- Cleaner project directory

**Cons:**
- Requires cache cleanup for old versions
- Less portable (cache not part of project)

Use `--cache=local` when you need:
- CI/CD pipelines (no shared state between jobs)
- Air-gapped environments
- Portable projects (USB drive, shared folder)

### Why Download All Platforms?

The wrapper downloads binaries for all platforms, not just the current one:

**Pros:**
- Lock file + sha256 work across all team members
- Clone-and-run works regardless of platform
- Consistent verification (same sha256 file everywhere)

**Cons:**
- ~50-100MB total download (vs ~10-20MB for single platform)
- Slightly longer install time

The trade-off favors team consistency over bandwidth.

### Why Not Use Package Managers?

Package managers (brew, apt, etc.) have drawbacks for this use case:

| Approach   | Problem                               |
|------------|---------------------------------------|
| Homebrew   | macOS only; requires formula maintenance |
| apt/yum    | Linux only; distro fragmentation      |
| npm/pip    | Wrong ecosystem for Docker tooling    |
| Go install | Requires Go toolchain                 |

A self-contained wrapper works everywhere with just `bash` and `curl`.

### Why Bash Instead of Go/Rust?

The wrapper is intentionally simple bash:

- **Auditability** — Users can read and verify the entire script
- **No compilation** — Works immediately on any Unix-like system
- **Stability** — Bash syntax rarely changes; script will work for years
- **Small** — ~400 lines vs megabytes for compiled alternatives

The heavy lifting is in the Go binary; the wrapper just orchestrates.

### Why Touch Binaries After Download?

```bash
# Touch all binaries to be newer than checksum
for platform in "${ALL_PLATFORMS[@]}"; do
    [[ -f "$dest" ]] && touch "$dest"
done
```

Binary that is newer than the checksum file but its checksum matches is considered untampered as the checksum is committed to the repository so it is trusted.

---

## Error Handling

The wrapper uses strict error handling:

```bash
set -euo pipefail
trap 'status=$?; echo "❌ Error on line $LINENO (exit $status)" >&2; exit "$status"' ERR
```

| Flag          | Effect                          |
|---------------|---------------------------------|
| `-e`          | Exit on any error               |
| `-u`          | Error on undefined variables    |
| `-o pipefail` | Pipe fails if any command fails |

The trap provides line numbers for debugging.

---

## Troubleshooting

### "CodingBooth is not installed correctly"

```bash
./booth install
# or
./booth update
```

### "SHA256 verification failed"

The binary was modified or corrupted:

```bash
./booth update  # Re-download from official release
```

### "Binary older than checksum"

Someone replaced the binary manually:

```bash
./booth update  # Restore official release
```

### "No SHA256 tool found"

Install sha256sum or shasum:

```bash
# Ubuntu/Debian
sudo apt-get install coreutils

# macOS (usually pre-installed)
# shasum is part of perl, which comes with macOS
```

---

## Related Files

- `booth` — The wrapper script (this document)
- `.booth/tools/codingbooth.lock` — Version and cache mode metadata
- `~/.cache/codingbooth/versions/<version>/` — Shared binary cache (Linux)
- `~/Library/Caches/codingbooth/versions/<version>/` — Shared binary cache (macOS)
- `%LOCALAPPDATA%\codingbooth\versions\<version>\` — Shared binary cache (Windows)
- `.booth/tools/codingbooth-*` — Local binaries (when using `--cache=local`)
- `cli/` — Source code for the Go binary
