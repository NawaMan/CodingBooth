# Wrapper Implementation

> [!IMPORTANT]
> **Why this matters:** The wrapper provides a stable, version-controlled entry point that can manage, verify, and run the actual CodingBooth binary without requiring users to manually download or update it.

**A single, stable script that handles everything.**
The `booth` wrapper script is a lightweight shell script that downloads, verifies, and executes the platform-specific CodingBooth binary. It allows CodingBooth to evolve independently while providing users with a reliable, self-updating entry point. The wrapper handles multi-platform support, cryptographic verification, and automatic recovery — all while remaining simple enough to audit and commit to version control.

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

CodingBooth uses a two-layer approach:

```
booth (wrapper)              — Small bash script, committed to repo
    │
    ▼ downloads, verifies, executes
    │
.booth/tools/coding-booth-*  — Platform-specific binary, gitignored
```

| Layer                      | Purpose                              | Version Controlled |
|----------------------------|--------------------------------------|--------------------|
| `booth` (wrapper)          | Stable entry point, manages binaries | Yes                |
| `coding-booth-*` (binary)  | Actual launcher logic                | No (gitignored)    |

---

## Supported Platforms

The wrapper supports six platform combinations:

| Platform        | Binary Name                       |
|-----------------|-----------------------------------|
| `linux-amd64`   | `coding-booth-linux-amd64`        |
| `linux-arm64`   | `coding-booth-linux-arm64`        |
| `darwin-amd64`  | `coding-booth-darwin-amd64`       |
| `darwin-arm64`  | `coding-booth-darwin-arm64`       |
| `windows-amd64` | `coding-booth-windows-amd64.exe`  |
| `windows-arm64` | `coding-booth-windows-arm64.exe`  |

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

| Command             | Description                        |
|---------------------|------------------------------------|
| `install [VERSION]` | Download and verify binaries       |
| `update [VERSION]`  | Same as install                    |
| `uninstall`         | Remove binaries and metadata       |
| `run [ARGS...]`     | Execute binary (after verification)|
| `version`           | Show wrapper and binary versions   |
| `help`              | Show usage information             |

Default command (no arguments): `run`

```bash
# These are equivalent:
./booth
./booth run

# Pass arguments to the binary:
./booth --variant codeserver
./booth run --variant codeserver
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

## File Structure

After installation, the `.booth/tools/` directory contains:

```
.booth/
├── .gitignore              # Excludes binaries from git
└── tools/
    ├── coding-booth.lock   # Version metadata
    ├── coding-booth.sha256 # SHA256 checksums for all platforms
    ├── coding-booth-linux-amd64
    ├── coding-booth-linux-arm64
    ├── coding-booth-darwin-amd64
    ├── coding-booth-darwin-arm64
    └── coding-booth-windows-amd64.exe
```

### Lock File Format

```
version=0.11.0
downloaded_at=2025-01-27T12:34:56Z
```

### SHA256 File Format

Standard sha256sum format with all platform binaries:

```
abc123...  coding-booth-linux-amd64
def456...  coding-booth-linux-arm64
...
```

### .gitignore

Binaries are excluded from version control:

```gitignore
# Binaries are excluded - they can be re-downloaded from coding-booth.lock version
tools/coding-booth-*
tools/*.sha256
```

---

## Download and Verification Flow

### Installation (`./booth install`)

```
User runs: ./booth install [VERSION]
    │
    ▼ VERSION defaults to "latest"
    │
    ├─► Fetch version.txt to get actual version number
    │
    ├─► For each platform:
    │     ├─► Download binary to temp file
    │     ├─► Download .sha256 file
    │     ├─► Verify SHA256 matches
    │     ├─► Move to .booth/tools/
    │     └─► Append to combined sha256 file
    │
    ├─► Write lock file with version + timestamp
    │
    └─► Touch all binaries (newer than sha256 file)
```

### Run Mode (`./booth` or `./booth run`)

```
User runs: ./booth [args...]
    │
    ▼ Detect platform (linux-amd64, darwin-arm64, etc.)
    │
    ├─► Check if binary exists
    │   │
    │   └─► If missing but lock file exists:
    │         Auto-download from locked version
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
if [[ -f "$lock_file" && ( ! -f "$dest" || ! -f "$sha_file" ) ]]; then
    lock_version=$(grep '^version=' "$lock_file" | cut -d= -f2-)
    if [[ -n "$lock_version" ]]; then
        echo "Binary missing, downloading version $lock_version from lock file..."
        DownloadBooth "$lock_version"
    fi
fi
```

This enables:
- Cloning a repo and running `./booth` immediately (downloads correct version)
- Team members with different platforms sharing the same lock file
- Recovery from accidental binary deletion

---

## Design Decisions

### Why Download All Platforms?

The wrapper downloads binaries for all six platforms, not just the current one:

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
- `.booth/tools/coding-booth-*` — Platform-specific binaries
- `.booth/tools/coding-booth.lock` — Version metadata
- `.booth/tools/coding-booth.sha256` — Combined checksums
- `cli/` — Source code for the Go binary
