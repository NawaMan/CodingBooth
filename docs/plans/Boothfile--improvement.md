# Boothfile Improvements (Planned)

> **Status:** Planned improvements for Boothfile
>
> For current implementation details, see [docs/implementations/BOOTHFILE.md](../implementations/BOOTHFILE.md).
>
> For original design rationale, see git history of this file.

---

## ~~1. Setup Script Validation~~ ✅ COMPLETED

Implemented in compiler.go. The compiler validates script names against:
- Built-in scripts (defined in `known_scripts.go`)
- Custom scripts from `.booth/setups/`

Unknown scripts emit warnings with fuzzy-match suggestions.

---

## ~~2. Functional `--strict` Mode~~ ✅ COMPLETED

Implemented in emit.go and ensure_docker_image.go. With `--strict`, warnings become errors and compilation fails.

---

## 3. Future: BuildKit Frontend Image

### Goal

Publish a `codingbooth/boothfile:1` image to Docker Hub that acts as a BuildKit frontend, allowing:

```bash
docker build -f Boothfile .
```

Docker would see `# syntax=codingbooth/boothfile:1`, pull the frontend image, and compile the Boothfile without needing the `booth` CLI.

### Why This Matters

- Zero CLI installation required
- Native Docker workflow
- CI/CD pipelines can use Boothfiles directly

### Implementation Notes

- BuildKit frontend protocol: the image receives the build context and outputs LLB (BuildKit's intermediate representation)
- Can be implemented as a Go binary that wraps the existing parser/compiler
- See Docker's [custom frontend documentation](https://docs.docker.com/build/dockerfile/frontend/)

---

## 4. Future: Editor Tooling

### Goal

Syntax highlighting and language support for Boothfiles in common editors.

### Deliverables

- VS Code extension with syntax highlighting
- TextMate grammar (reusable by many editors)
- Language server for autocomplete (optional, lower priority)

### Implementation Notes

- Boothfile syntax is simple enough that a TextMate grammar would cover most needs
- Keywords: `run`, `setup`, `install`, `copy`, `env`, `arg`, `workdir`, `expose`, `label`, `DOCKER`
- Heredoc highlighting: `<<END`, `&&<<END`, `;<<END`

---

## 5. Future: Alternative Compilation Targets

### Goal

Support compilation to formats other than Dockerfile:
- Podman Containerfile (mostly identical to Dockerfile)
- Buildah scripts
- OCI image spec

### Why This Matters

Decouples user intent from container runtime. If CodingBooth migrates to Podman or other OCI-compatible tooling, Boothfiles remain unchanged.

### Implementation Notes

- Current compiler architecture already separates parsing from code generation
- Add `CompilerOptions.Target` field to select output format
- Podman support would be trivial (Containerfile is Dockerfile-compatible)
- Buildah would require generating shell script with `buildah` commands

---

## Summary

| Improvement | Priority | Status |
|-------------|----------|--------|
| Setup script validation | High | ✅ Completed |
| Functional `--strict` mode | High | ✅ Completed |
| BuildKit frontend image | Medium | Planned |
| Editor tooling | Low | Planned |
| Alternative targets | Low | Planned |

The high-priority items (validation + strict mode) are now complete. The future items are nice-to-have and can be deferred indefinitely without impacting core functionality.
