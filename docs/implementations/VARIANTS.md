# Variant Selection Implementation

> [!IMPORTANT]
> **Why this matters:** This feature is the magic that makes CodingBooth feel native.
It completely eliminates “permission denied” errors and root-owned files on your host machine — one of the most painful and common problems with Docker-based development.

**Develop inside containers without ever thinking about file permissions.**
CodingBooth dynamically mirrors your host identity inside every container, ensuring that every file you create is owned by you — not root, not UID 1000, and not some anonymous user. This removes the most persistent friction in container workflows: broken permissions, unreadable files, and constant sudo usage. By rewriting the container user at startup to match your host UID and GID, CodingBooth delivers seamless file ownership, clean Git workflows, and team-safe collaboration — all while keeping processes non-root and environments fully reproducible.

This document explains how CodingBooth handles user permissions to ensure seamless file ownership between host and container.

---

## Overview

CodingBooth provides five variants, each extending the previous:

```
base
  │
  ├── notebook     (adds Jupyter)
  │
  ├── codeserver   (adds VS Code + Jupyter)
  │
  └── desktop-xfce / desktop-kde  (adds full desktop + VS Code + Jupyter)
```

---

## Available Variants

| Variant        | Description                        | Default CMD             |
|----------------|------------------------------------|-------------------------|
| `base`         | Minimal shell with essential tools | `ttyd` (web terminal)   |
| `notebook`     | Jupyter Notebook environment       | `jupyter notebook`      |
| `codeserver`   | Browser-based VS Code              | `code-server`           |
| `desktop-xfce` | Lightweight XFCE desktop           | `start-xfce`            |
| `desktop-kde`  | Feature-rich KDE Plasma desktop    | `start-kde`             |

All variants expose their UI on port 10000.

---

## Variant Aliases

For convenience, CodingBooth accepts aliases:

| Input     | Resolves To    |
|-----------|----------------|
| `default` | `base`         |
| `console` | `base`         |
| `ide`     | `codeserver`   |
| `desktop` | `desktop-xfce` |
| `xfce`    | `desktop-xfce` |
| `kde`     | `desktop-kde`  |

---

## Implementation

### Validation and Normalization

The variant is validated in `cli/src/pkg/booth/validate_variant.go`:

```go
func ValidateVariant(ctx appctx.AppContext) appctx.AppContext {
    builder := ctx.ToBuilder()
    variant := ctx.Variant()

    // Step 1: Normalize variant aliases
    switch variant {
    case "base", "notebook", "codeserver", "desktop-xfce", "desktop-kde":
        // Valid variants, no change needed
    case "default", "console":
        variant = "base"
    // ... handles other aliases ...
    default:
        // Error handling ...
        os.Exit(1)
    }

    builder.Config.Variant = variant

    // Step 2: Set capability flags (simplified)
    // e.g. builder.HasVscode = true/false based on variant

    return builder.Build()
}
```

---

## Configuration Sources

Variant can be specified through multiple sources (in order of precedence):

### 1. Command Line Flag

```bash
./booth --variant codeserver
```

### 2. Configuration File

```toml
# .booth/config.toml
variant = "desktop-xfce"
```

### 3. Environment Variable

```bash
CB_VARIANT=notebook ./booth
```

### 4. Built-in Default

If none specified, defaults to `base`.

---

## Image Tag Construction

The variant determines the Docker image tag:

```go
// In ensure_docker_image.go
if ctx.ImageMode() == "PREBUILT" {
    builder.Config.Image = fmt.Sprintf("%s:%s-%s",
        ctx.PrebuildRepo(),  // "nawaman/codingbooth"
        ctx.Variant(),       // e.g., "codeserver"
        ctx.Version())       // e.g., "latest"
}
```

Example image names:
- `nawaman/codingbooth:base-latest`
- `nawaman/codingbooth:codeserver-0.11.0`
- `nawaman/codingbooth:desktop-xfce-latest`

---

## Variant-Specific Behavior

### Base Variant

Provides a web terminal via `ttyd`:

```dockerfile
# variants/base/Dockerfile
CMD ["bash","-lc","exec ttyd -W -i 0.0.0.0 -p 10000 --writable bash -l"]
```

### Notebook Variant

Runs Jupyter Notebook:

```dockerfile
# variants/notebook/Dockerfile
CMD ["jupyter", "notebook", "--ip=0.0.0.0", "--port=10000", ...]
```

### Codeserver Variant

Runs VS Code in the browser:

```dockerfile
# variants/codeserver/Dockerfile
CMD ["code-server", "--bind-addr", "0.0.0.0:10000", ...]
```

### Desktop Variants

Start the desktop environment:

```dockerfile
# variants/desktop-xfce/Dockerfile
CMD ["start-xfce"]

# variants/desktop-kde/Dockerfile
CMD ["start-kde"]
```

---

## Variant Inheritance

Each variant Dockerfile extends from the previous:

```dockerfile
# variants/notebook/Dockerfile
FROM nawaman/codingbooth:base-${CB_VERSION_TAG}
# ... add Jupyter

# variants/codeserver/Dockerfile
FROM nawaman/codingbooth:notebook-${CB_VERSION_TAG}
# ... add code-server

# variants/desktop-xfce/Dockerfile
FROM nawaman/codingbooth:base-${CB_VERSION_TAG}
# Note: desktop starts fresh from base to keep image smaller
# but installs Python, notebooks, etc. via setup scripts
```

Desktop variants don't extend from `codeserver` to avoid unnecessary layers. Instead, they use setup scripts to install the same tools.

---

## Custom Dockerfiles

You can create a custom Dockerfile while allowing the variant to be specified at run time.
By accepting the `CB_VARIANT_TAG` and `CB_VERSION_TAG` arguments,
  you can create a custom Dockerfile that extends from the variant image.

For example:

```dockerfile
# .booth/Dockerfile
ARG CB_VARIANT_TAG=codeserver
ARG CB_VERSION_TAG=latest
FROM nawaman/codingbooth:${CB_VARIANT_TAG}-${CB_VERSION_TAG}

# Add your customizations
RUN python--setup.sh
```

The launcher passes these build args:
- `CB_VARIANT_TAG` — From `--variant` or config
- `CB_VERSION_TAG` — From `--version` or config

---

## Variant Selection Flow

```
User runs: ./booth --variant ide

  1. CLI parses --variant ide
     │
  2. ValidateVariant() normalizes:
     │  ide → codeserver
     │
  3. EnsureDockerImage() constructs image name:
     │  nawaman/codingbooth:codeserver-latest
     │
  4. Docker pulls/builds if needed
     │
  5. Container starts with variant's default CMD
     │
  ▼
VS Code running in browser at localhost:10000
```

---

## Error Handling

Invalid variants produce clear error messages:

```bash
$ ./booth --variant invalid
Error: unknown --variant 'invalid' (valid: base|notebook|codeserver|desktop-xfce|desktop-kde;
       aliases: console|ide|desktop|xfce|kde)
```

---

## Dryrun Inspection

Use `--dryrun` to see how variant affects the docker command:

```bash
$ ./booth --variant desktop-xfce --dryrun
docker run ... nawaman/codingbooth:desktop-xfce-latest start-xfce
```

---

## Related Files

- `cli/src/pkg/booth/validate_variant.go` — Variant validation and alias normalization
- `cli/src/pkg/booth/ensure_docker_image.go` — Image tag construction
- `variants/*/Dockerfile` — Variant-specific Dockerfiles
