# Phase 8: Quick Mode UI

## Tasks

40. Implement project type menu (Python, Node.js, Go, Java, Rust, Empty, AI Agent, Advanced, Feeling lucky)
41. Implement variant selection menu
42. Implement confirmation prompt with summary
43. Implement quick-mode mapping (`quick-mode.toml` or hardcoded)
44. Tests for quick mode

## Suggested Package Structure

```
internal/
└── design/
    └── quick/
        └── quick.go          # Quick mode UI
```

## Flow

```
Page 1: Project Type  →  Page 2: Variant  →  Final: Generate
```

## Page 1: Project Type

```
Select project type:
  1) Python
  2) Node.js
  3) Go
  4) Java
  5) Rust
  6) Empty
  7) AI Agent
  8) Advanced mode
  9) Feeling lucky (Random)
Enter choice [1-9]:
```

## Page 2: Variant

```
Select environment:
  1) VS Code in browser (codeserver)
  2) Jupyter Notebook
  3) Full desktop (XFCE)
  4) Full desktop (KDE)
  5) Terminal only (base)
Enter choice [1-5]:
```

## Final: Generate

```
Configuring your booth...

Project:  Go
Variant:  codeserver
Port:     NEXT

Will create:
  .booth/config.toml
  .booth/Dockerfile

Dockerfile will install:
  ✓ Go (latest)
  ✓ VS Code Go extension

Proceed? [Y/n]
```

## Quick Mode Mapping

Quick mode selections map to hardcoded template combinations. Each includes `required` and `recommended` items from templates. **Parameters use their default values in Quick mode.**

```toml
# Suggested location: /templates/quick-mode.toml

[python]
templates = ["python", "python-code-extension"]
variant = "codeserver"

[nodejs]
templates = ["nodejs", "nodejs-code-extension"]
variant = "codeserver"

[go]
templates = ["go", "go-code-extension"]
variant = "codeserver"

[java]
templates = ["java", "java-code-extension"]
variant = "codeserver"

[rust]
templates = ["rust", "rust-code-extension"]
variant = "codeserver"

[empty]
templates = []
variant = "base"

[ai-agent]
templates = ["claude-code", "claude-credentials"]
variant = "base"
```

Selecting "Advanced mode" (option 8) transitions to the Advanced Mode TUI (Phase 9).
Selecting "Feeling lucky" (option 9) picks a random project type.
