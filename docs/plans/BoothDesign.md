# design Feature Plan

This document outlines the design and implementation plan for the `./booth design` command, which provides guided configuration setup for CodingBooth.

## Overview

`./booth design` is a wizard-style tool that helps users create `.booth/` configuration files. It runs **on the host** as part of the `coding-booth` binary, downloading templates from GitHub releases.

**Why on the host (not in container)?**
- No Docker required for design — works before Docker is installed
- Solves chicken-egg: `.booth/` config created before image pull
- Can design, then run `./booth` to pull image
- Simpler execution model

The feature has three interfaces:

| Interface    | Purpose                           | Invocation                                   |
|--------------|-----------------------------------|----------------------------------------------|
| **CLI**      | Scriptable, testing               | `./booth design --select go --non-interactive` |
| **Quick**    | Fast setup with sensible defaults | `./booth design` (default)                     |
| **Advance**  | Full control via template browser | `./booth design --advance`                     |

### Language: Go

The design logic is part of the `coding-booth` binary, so it must be implemented in Go.

### Suggested Package Structure

```
cmd/
└── coding-booth/
    └── main.go

internal/
└── design/
    ├── cache/
    │   ├── download.go       # Download templates.zip from GitHub
    │   ├── verify.go         # SHA256 verification
    │   └── extract.go        # Extract to temp dir
    ├── output/
    │   ├── model.go          # Output data structures
    │   ├── config.go         # config.toml serialization
    │   ├── dockerfile.go     # Dockerfile generation
    │   └── writer.go         # File writing orchestration
    ├── template/
    │   ├── model.go          # Template data structures
    │   ├── loader.go         # TOML parsing and registry
    │   └── resolve.go        # Template → Output conversion
    ├── cli/
    │   ├── list.go           # --list command
    │   ├── search.go         # --search command
    │   └── select.go         # --select --non-interactive command
    ├── quick/
    │   └── quick.go          # Quick mode UI
    └── tui/
        └── app.go            # Advanced mode TUI (using bubbletea)
```

---

## Implementation Phases

| Phase | Name                              | Details                                                                  |
|-------|-----------------------------------|--------------------------------------------------------------------------|
| 1     | Output Data Model & Serialization | [phase1-output-model.md](design/phase1-output-model.md)                 |
| 2     | Template Data Model               | [phase2-template-model.md](design/phase2-template-model.md)             |
| 3     | Template to Output Conversion     | [phase3-template-to-output.md](design/phase3-template-to-output.md)     |
| 4     | Template Loading                  | [phase4-template-loading.md](design/phase4-template-loading.md)         |
| 5     | CLI Commands                      | [phase5-cli-commands.md](design/phase5-cli-commands.md)                 |
| 6     | Templates & Validation            | [phase6-templates-validation.md](design/phase6-templates-validation.md) |
| 7     | Template Cache & Download         | [phase7-cache-download.md](design/phase7-cache-download.md)             |
| 8     | Quick Mode UI                     | [phase8-quick-mode.md](design/phase8-quick-mode.md)                     |
| 9     | Advanced Mode TUI                 | [phase9-advanced-tui.md](design/phase9-advanced-tui.md)                 |

---

## Open Items

1. **Rust setup script** — needs to be created (`rust--setup.sh`)
2. **AI Agent templates** — which tools to include (Claude Code confirmed, others TBD)
3. **Conflict resolution** — if multiple templates specify same run-arg, last wins? dedupe?
5. **Circular dependencies** — validate that `requires` doesn't create cycles
7. **Template versioning** — should template version match `coding-booth` binary version exactly, or allow compatibility ranges?
8. **Offline mode** — what happens if download fails and no cache exists? Clear error message needed.
9. **Hash file format** — `templates.zip.sha256` format (just hash, or `hash filename`?)

## Appendix

- We will need a program to validate the template and run with GitHub action to release. So that we avoid problem like typo and circular or missing dependency.
- As opinion present, we need to have logging printed out when --verbose.
- The run-args  `-v` and `-e` should be deduplicated.
- Tie breaker for same ordering is alphabetical order of the name.
- Expand `~` in the binding  — handle that expansion.
