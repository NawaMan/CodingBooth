# Phase 7: Template Cache & Download

## Tasks

35. Implement template zip download from GitHub releases with progress indicator
36. Implement SHA256 hash verification
37. Implement cache management (`~/.cache/codingbooth/<version>/templates.zip`, permissions `400`)
38. Implement extraction to temp directory (`/tmp/cb-design-<random>/`) with cleanup
39. Handle offline/failure case with clear error message

## Suggested Package Structure

```
internal/
└── design/
    └── cache/
        ├── download.go       # Download templates.zip from GitHub
        ├── verify.go         # SHA256 verification
        └── extract.go        # Extract to temp dir
```

## Execution Model

```
./booth design --select go
    │
    └─► coding-booth design --select go
            │
            ├─► Check ~/.cache/codingbooth/<version>/templates.zip
            │       │
            │       ├─► If missing: download from GitHub releases
            │       │   https://github.com/NawaMan/CodingBooth/releases/download/<version>/templates.zip
            │       │   Verify hash, save with chmod 400
            │       │
            │       └─► If exists: verify hash
            │
            ├─► Extract to /tmp/cb-design-<random>/
            │   (fresh extraction every time for security)
            │
            ├─► Read templates, process selection
            │
            ├─► Generate .booth/ files
            │
            └─► Clean up /tmp/cb-design-<random>/
```

## Download URL

```
https://github.com/NawaMan/CodingBooth/releases/download/<version>/templates.zip
```

## Cache Location

```
~/.cache/codingbooth/
└── <version>/
    ├── templates.zip      # chmod 400
    └── templates.zip.sha256
```

## Cache Behavior

1. Check if `~/.cache/codingbooth/<version>/templates.zip` exists
2. If exists, verify SHA256 hash
3. If missing or hash mismatch, download fresh
4. Set permissions to `400` (read-only, owner only)

## Extraction

```
/tmp/cb-design-<random-uuid>/
├── languages/
├── frameworks/
├── tools/
├── credentials/
└── quick-mode.toml
```

Extracted directory is deleted after design completes (or on error).

**Why extract every time?**
Templates end up in `.booth/` (e.g., Dockerfile, startup scripts). A compromised cached extraction could be exploited for credential theft or code injection. Fresh extraction from the verified zip ensures integrity.

## Development Override

Use `--templates-path <path>` to load templates from a local directory (skips download/extraction).

## File Locations

| File            | Location                                       |
|-----------------|------------------------------------------------|
| Design logic    | `coding-booth` binary (on host)                |
| Template cache  | `~/.cache/codingbooth/<version>/templates.zip` |
| Temp extraction | `/tmp/cb-design-<random>/`                     |
| Output          | `./.booth/`                                    |

## Benefits

- **No Docker needed for design** — works before Docker is installed
- **Solves chicken-egg** — `.booth/` config created before image pull
- **Secure** — fresh extraction prevents tampering
- **Offline capable** — works if templates already cached
- **Version aligned** — template version matches `coding-booth` binary version

## Open Items

- **Offline mode** — what happens if download fails and no cache exists? Clear error message needed.
- **Hash file format** — `templates.zip.sha256` format (just hash, or `hash filename`?)
