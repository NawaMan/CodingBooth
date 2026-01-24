# Plan: Simplify Setup Script Guards

## Problem

Current Dockerfiles use verbose conditional guards:

```dockerfile
RUN if [[ "$CB_HAS_VSCODE" != false ]]; then ./some-code-extension--setup.sh ; fi
```

This is noisy and duplicates guard logic across Dockerfiles.

## Solution

Move guard logic inside setup scripts using exit code 42 ("not applicable").

### Exit Code Convention

| Exit Code | Meaning               | Docker Build Behavior |
|----------:|:----------------------|:----------------------|
|         0 | Success               | Continue              |
|        42 | Not applicable (skip) | Continue              |
|     Other | Error                 | Fail build            |

Why 42? It's in the safe range (doesn't conflict with standard Unix codes or signals),
and it's memorable. We document its meaning, making it a clear project convention.

### New Dockerfile Pattern

```dockerfile
RUN ./some--setup.sh || [[ $? -eq 42 ]]
```

## Implementation

### 1. Create Detection Scripts

Create two detection scripts in `variants/base/setups/`:

**`cb-has-vscode.sh`** - Detects VS Code or code-server:
```bash
#!/bin/bash
# Returns 0 if VS Code / code-server is available, 1 otherwise.
command -v code-server &>/dev/null && exit 0
command -v code &>/dev/null && exit 0
exit 1
```

**`cb-has-desktop.sh`** - Detects desktop environment:
```bash
#!/bin/bash
# Returns 0 if desktop environment is available, 1 otherwise.
# Update this script as display technology evolves.

# X11/VNC-based desktop
command -v Xvnc &>/dev/null && exit 0
command -v tigervncserver &>/dev/null && exit 0

# XFCE
command -v startxfce4 &>/dev/null && exit 0
command -v xfce4-session &>/dev/null && exit 0

# KDE
command -v startplasma-x11 &>/dev/null && exit 0
command -v plasmashell &>/dev/null && exit 0

# Wayland-based desktop (future)
command -v cage &>/dev/null && exit 0
command -v gamescope &>/dev/null && exit 0

exit 1
```

### 2. Update Setup Scripts

Setup scripts that need guards will:
1. Call the appropriate detection script
2. Print SKIP message to stderr (with script name) if not applicable
3. Exit 42 if not applicable
4. Proceed with setup if applicable

Example pattern:
```bash
#!/bin/bash
SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(dirname "$0")"

if ! "$SCRIPT_DIR/cb-has-vscode.sh"; then
    echo "SKIP: $SCRIPT_NAME - code-server/VSCode not installed" >&2
    exit 42
fi

# ... rest of setup
```

### 3. Scripts Requiring Guards

**VS Code guard (`cb-has-vscode.sh`):**

| Script                           | Reason                        |
|:---------------------------------|:------------------------------|
| `base-code-extension--setup.sh`  | Requires code-server          |
| `bash-code-extension--setup.sh`  | Requires code-server          |
| `python-code-extension--setup.sh`| Requires code-server          |
| `java-code-extension--setup.sh`  | Requires code-server          |
| `go-code-extension--setup.sh`    | Requires code-server          |
| `react-code-extension--setup.sh` | Requires code-server          |
| `jupyter-code-extension--setup.sh`| Requires code-server         |

**Desktop guard (`cb-has-desktop.sh`):**

| Script                    | Reason                              |
|:--------------------------|:------------------------------------|
| `antigravity--setup.sh`   | Requires desktop environment        |
| `claude-code--setup.sh`   | Requires desktop environment        |
| (future desktop setups)   | —                                   |

**No guard needed (always run):**

| Script Pattern            | Reason                              |
|:--------------------------|:------------------------------------|
| `*-nb-kernel--setup.sh`   | pjterm/Python always present        |
| All other setup scripts   | No variant-specific dependencies    |

### 4. Update Dockerfiles

Replace verbose guards with simple pattern:

Before:
```dockerfile
RUN if [[ "$CB_HAS_VSCODE" != false ]]; then ./java-code-extension--setup.sh ; fi
```

After:
```dockerfile
RUN ./java-code-extension--setup.sh || [[ $? -eq 42 ]]
```

### 5. Files to Modify

| File                                              | Change                      |
|:--------------------------------------------------|:----------------------------|
| `variants/base/setups/cb-has-vscode.sh`           | Create (new)                |
| `variants/base/setups/cb-has-desktop.sh`          | Create (new)                |
| `variants/base/setups/*-code-extension--setup.sh` | Add VS Code guard           |
| `variants/base/setups/antigravity--setup.sh`      | Add desktop guard           |
| `variants/base/setups/claude-code--setup.sh`      | Add desktop guard           |
| `examples/demo/.booth/Dockerfile`                 | Simplify RUN statements     |
| `examples/workspaces/*/.booth/Dockerfile`         | Simplify RUN statements     |

## Testing

Manual testing:

| Test Case                          | Expected Result                     |
|:-----------------------------------|:------------------------------------|
| Build with `codeserver` variant    | VS Code extensions install          |
| Build with `base` variant          | VS Code extensions skip (exit 42)   |
| Build with `desktop-xfce` variant  | Desktop setups install              |
| Build with `base` variant          | Desktop setups skip (exit 42)       |

Automated testing via existing example workspace builds.

## Future Considerations

- When adding Wayland support, update `cb-has-desktop.sh` only
- New detection scripts can be added (e.g., `cb-has-java.sh`) if needed
- Consider adding `CB_EXIT_NOT_APPLICABLE=42` constant in a shared file if more scripts need it
