# Boothfile Improvements (Planned)

> **Status:** Planned improvements for Boothfile
>
> For current implementation details, see [docs/implementations/BOOTHFILE.md](../implementations/BOOTHFILE.md).
>
> For original design rationale, see git history of this file.

---

## 1. Setup Script Validation

### Current State

The parser detects **command typos** (e.g., `setpu` → "Did you mean 'setup'?"), but does **not** validate whether a setup script actually exists.

### Planned Behavior

When the compiler encounters `setup <name>` or `install <name> <packages>`, it should:

1. Check if `<name>--setup.sh` or `<name>--install.sh` exists in:
   - `.booth/setups/` (custom scripts)
   - Known built-in scripts list

2. If not found, emit a **warning** (not an error):
   ```
   Warning: Unknown setup script 'pytohn'. Did you mean 'python'?
   ```

3. Compilation continues — the warning allows users to proceed if they know the script will exist at build time.

### Implementation Notes

- Maintain a list of known built-in setup scripts (can be generated from `variants/base/setups/`)
- Use fuzzy matching for suggestions (Levenshtein distance or similar)
- Warnings should include line numbers: `Boothfile:7: Warning: ...`

---

## 2. Functional `--strict` Mode

### Current State

The `--strict` flag exists in the CLI but has no effect — no warnings are ever generated.

### Planned Behavior

With `--strict`:
- All warnings become errors
- Compilation fails if any warnings exist

```bash
# Normal: warnings printed but compilation succeeds
codingbooth emit-dockerfile
# Warning: Unknown setup script 'pytohn'. Did you mean 'python'?
# (outputs Dockerfile)

# Strict: warnings become errors
codingbooth emit-dockerfile --strict
# Error: Unknown setup script 'pytohn'. Did you mean 'python'?
# (exits with error, no output)
```

### Implementation Notes

- Requires Section 1 (setup script validation) to be implemented first
- The `ParseResult.Warnings` and `CompileResult.Warnings` fields exist but are never populated
- Add warning collection during compilation, then check warnings + strict flag before returning

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

| Improvement | Priority | Dependency |
|-------------|----------|------------|
| Setup script validation | High | None |
| Functional `--strict` mode | High | Setup script validation |
| BuildKit frontend image | Medium | None |
| Editor tooling | Low | None |
| Alternative targets | Low | None |

The high-priority items (validation + strict mode) improve developer experience. The future items are nice-to-have and can be deferred indefinitely without impacting core functionality.
