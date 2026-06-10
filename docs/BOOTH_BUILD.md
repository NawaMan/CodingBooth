# booth build

> Build and optionally publish a booth image for sharing or deployment.

`booth build` compiles the Boothfile into a Docker image and optionally pushes it to a container registry. The image tag defaults to a content hash, so identical configurations produce identical tags — enabling caching and instruction-level repeatability.

It is also how you create a **fully reproducible** environment: build the image once, store it (by tag or, better, by digest), and reuse *that image* instead of rebuilding. The stored image is the only artifact that freezes every dependency — base image, apt packages, and transitive libraries — byte-for-byte. See [Reproducibility](REPRODUCIBILITY.md) for the full picture and the three tiers of repeatability.

```bash
./booth build                                          # build locally
./booth build --push ghcr.io/myteam                    # build and push
./booth build --push ghcr.io/myteam --name my-env --tag v1.0
```

Back to [README](../README.md)

---

## Table of Contents

- [Overview](#overview)
- [Flags](#flags)
- [Image Naming](#image-naming)
- [Content-Based Tagging](#content-based-tagging)
- [Pushing to a Registry](#pushing-to-a-registry)
- [Authentication](#authentication)
- [Build Arguments](#build-arguments)
- [Examples](#examples)
- [Implementation Plan](#implementation-plan)

---

## Overview

The current `booth run` flow builds a local image before launching it, but that image is tagged for local use only (`codingbooth-local:<project>-<variant>-<version>`) and cannot be pushed to a registry.

`booth build` solves this by producing a properly named image that can be:
- Used locally with `booth run --image <image>`
- Pushed to any container registry for sharing with teammates or CI

---

## Flags

| Flag                   | Default                  | Description                                                      |
|------------------------|--------------------------|------------------------------------------------------------------|
| `--push <registry>`    | _(none)_                 | Push to the given registry after building.                       |
| `--name <name>`        | Booth name (project name)| Image name.                                                      |
| `--tag <tag>`          | Content hash (24 chars)  | Image tag.                                                       |
| `--build-arg KEY=VALUE`| _(from config)_          | Additional Docker build arguments. Repeatable.                   |
| `--code <path>`        | `.` (current directory)  | Path to the project directory.                                   |
| `--variant <variant>`  | From `.booth/config.toml`| Override the variant.                                            |
| `--version <version>`  | From `.booth/config.toml`| Override the CodingBooth version.                                |
| `--verbose`            | `false`                  | Show detailed output.                                            |
| `--dryrun`             | `false`                  | Print the docker command without executing.                      |

---

## Image Naming

The full image reference is constructed as:

```
<registry>/<name>:<tag>
```

**When `--push` is omitted (local build):**
```
<name>:<tag>
```

**Examples:**

| Flags                                  | Image                                                |
|----------------------------------------|------------------------------------------------------|
| _(none)_                               | `myproject:a3f8b2c1d4e5f6a7b8c9d0e1`                |
| `--push ghcr.io/myteam`               | `ghcr.io/myteam/myproject:a3f8b2c1d4e5f6a7b8c9d0e1` |
| `--push ghcr.io/myteam --name custom` | `ghcr.io/myteam/custom:a3f8b2c1d4e5f6a7b8c9d0e1`    |
| `--push ghcr.io/myteam --tag v1.0`    | `ghcr.io/myteam/myproject:v1.0`                      |
| `--name my-env --tag latest`           | `my-env:latest`                                      |

---

## Content-Based Tagging

When `--tag` is not specified, the tag is derived from a SHA-256 hash (truncated to 24 hex characters) of a JSON document containing:

```json
{
  "boothfile": "<Boothfile content, trimmed>",
  "build-args": ["KEY1=VALUE1", "KEY2=VALUE2"],
  "variant": "codeserver",
  "version": "0.35.0"
}
```

- `boothfile` — the raw Boothfile content with leading/trailing whitespace trimmed.
- `build-args` — sorted list of all build arguments (from config + CLI `--build-arg` flags).
- `variant` — the resolved variant name.
- `version` — the resolved CodingBooth version.

This means:
- **Same config = same tag.** Two machines with identical `.booth/` produce the same hash.
- **Skip-if-exists.** Before building, check if the image already exists (locally or in registry). If it does, skip the build and print the image name.
- **Any change = new tag.** Changing the Boothfile or build args produces a different hash, so stale images are never reused.

> **Note:** A matching tag proves the *recipe* is identical, not that the *bytes* are. A later rebuild can resolve unpinned transitive dependencies or apt packages to newer versions under the same tag. For byte-for-byte guarantees, store and reuse the built image rather than rebuilding — see [Reproducibility](REPRODUCIBILITY.md).

---

## Pushing to a Registry

Use `--push <registry>` to build and push in one step:

```bash
./booth build --push ghcr.io/myteam
```

**Build backend:**
- **Without `--push`:** Uses `docker build`. Image stays local.
- **With `--push`:** Uses `docker build` followed by `docker push`.

**Error handling:**
If the push fails (e.g. authentication missing), CodingBooth surfaces Docker's error and suggests the fix:

```
Error: push to ghcr.io/myteam/myproject:a3f8b2c1d4e5f6a7b8c9d0e1 failed.
  Ensure you are logged in: docker login ghcr.io
```

---

## Authentication

CodingBooth does **not** manage registry credentials. Authentication is handled entirely by Docker:

```bash
# Log in to your registry before pushing
docker login ghcr.io
docker login registry.example.com

# Credentials are stored in ~/.docker/config.json
# Credential helpers (gcloud, ecr, acr) work as normal
```

If authentication is missing or expired, the push fails with Docker's own error message. CodingBooth suggests the appropriate `docker login` command based on the registry.

**Common registries:**

| Registry                    | Login command                                      |
|-----------------------------|---------------------------------------------------|
| Docker Hub                  | `docker login`                                     |
| GitHub Container Registry   | `docker login ghcr.io`                             |
| Google Artifact Registry    | `gcloud auth configure-docker`                     |
| AWS ECR                     | `aws ecr get-login-password \| docker login ...`   |
| Azure ACR                   | `az acr login --name <registry>`                   |

---

## Build Arguments

Build arguments come from two sources, merged in order:

1. `.booth/config.toml` `build-args` array
2. CLI `--build-arg KEY=VALUE` flags (can override config values)

CodingBooth also injects these automatically:
- `BOOTH_VARIANT_TAG=<variant>`
- `BOOTH_VERSION_TAG=<version>`
- `BOOTH_SETUPS=<setups-dir>`

---

## Examples

### Build locally (default)

```bash
./booth build
# ✅ Built: myproject:a3f8b2c1d4e5f6a7b8c9d0e1
```

### Build and push to GitHub Container Registry

```bash
docker login ghcr.io
./booth build --push ghcr.io/myteam
# ✅ Pushed: ghcr.io/myteam/myproject:a3f8b2c1d4e5f6a7b8c9d0e1
```

### Use a custom name and tag

```bash
./booth build --push ghcr.io/myteam --name my-env --tag v1.0
# ✅ Pushed: ghcr.io/myteam/my-env:v1.0
```

### Build with extra build arguments

```bash
./booth build --build-arg PYTHON_VERSION=3.13 --build-arg NODE_VERSION=22
# ✅ Built: myproject:b7e2f1a9c3d8e4f5a6b7c8d9
```

### Run a previously built image

```bash
./booth build --push ghcr.io/myteam
# ✅ Pushed: ghcr.io/myteam/myproject:a3f8b2c1d4e5f6a7b8c9d0e1

./booth run --image ghcr.io/myteam/myproject:a3f8b2c1d4e5f6a7b8c9d0e1
```

---

## Implementation Plan

### 1. New command entry point

Add `case "build":` to `main.go` dispatcher, routing to a new `buildBooth(version)` function in `build.go`.

### 2. Argument parsing (`build.go`)

Parse build-specific flags: `--push <registry>`, `--name`, `--tag`, `--build-arg`, `--code`, `--variant`, `--version`, `--verbose`, `--dryrun`.

Reuse `boothinit.InitializeAppContext` for resolving config from `.booth/config.toml` (variant, version, build-args).

### 3. Content hash computation

New function in `pkg/booth/build_hash.go`:

```
func ComputeBuildHash(boothfileContent string, buildArgs []string, variant string, version string) string
```

- Construct JSON object with the four fields (build-args sorted).
- SHA-256 hash the JSON bytes.
- Hex-encode and truncate to 24 characters.

### 4. Image name assembly

New function in `pkg/booth/build_image.go`:

```
func AssembleImageName(registry, name, tag string) string
```

- If registry is empty: `<name>:<tag>`
- If registry is set: `<registry>/<name>:<tag>`

### 5. Boothfile compilation (reuse)

Reuse the existing `normalizeDockerFile()` + `compileBoothfile()` logic from `ensure_docker_image.go` to produce the Dockerfile from the Boothfile. May need to extract/refactor these into shared functions.

### 6. Docker build execution

- **Local (no `--push`):** Call existing `docker.DockerBuild()` with `-t <image>` and build-args.
- **Push (`--push <registry>`):** New function `docker.DockerBuildAndPush(flags, args, imageName)` that runs `docker build` followed by `docker push`. This is more reliable than `docker buildx build --push` because it avoids buildx driver networking issues (e.g., docker-container driver cannot reach localhost registries). On failure, detect the registry host from the `--push` value and suggest `docker login <host>`.

### 7. Skip-if-exists (optional, future)

Before building, check if the image exists:
- Local: `docker image inspect <image>`
- Remote: `docker manifest inspect <image>` (requires registry access)

If it exists, print the image name and skip. Add `--force` to override.

### 8. Output

Print the final image reference:
```
✅ Built: <image>          (local)
✅ Pushed: <image>         (with --push)
```

### 9. Help text

Add `booth build` to `help.go` and include it in the main help output.

### 10. Tests

- Unit test for `ComputeBuildHash` — deterministic output, sorted args, content changes produce different hashes.
- Unit test for `AssembleImageName` — all combinations of registry/name/tag.
- Dryrun test — verify the docker command that would be executed.
- Integration test — build a simple Boothfile locally (no push).
