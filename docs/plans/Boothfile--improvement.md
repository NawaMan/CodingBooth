# Boothfile Improvements

> **Status:** Core improvements complete. Future items deferred.
>
> For current implementation details, see [docs/implementations/BOOTHFILE.md](../implementations/BOOTHFILE.md).

---

## Completed

### 1. Setup Script Validation ✅

Implemented in compiler.go. The compiler validates script names against:
- Built-in scripts (discovered at runtime from `variants/base/setups/`)
- Custom scripts from `.booth/setups/`

Unknown scripts emit warnings with fuzzy-match suggestions. Set `CODINGBOOTH_SETUPS_DIR` to override the built-in scripts location.

### 2. Functional `--strict` Mode ✅

Implemented in emit.go and ensure_docker_image.go. With `--strict`, warnings become errors and compilation fails.

---

## Deferred

The following items are nice-to-have and deferred indefinitely. They don't impact core functionality.

### 3. BuildKit Frontend Image

Publish `codingbooth/boothfile:1` to Docker Hub so `docker build -f Boothfile .` works without booth CLI.

### 4. Editor Tooling

VS Code extension / TextMate grammar for syntax highlighting.

### 5. Alternative Compilation Targets

Podman Containerfile, Buildah scripts support.
