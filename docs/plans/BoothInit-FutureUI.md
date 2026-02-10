# BoothInit — Future UI Plans (Quick Mode & Advanced Mode)

This document describes the future interactive UI plans for `./booth init`. These are not currently being implemented but serve as a design reference for later phases.

See the main plan: [BoothInit.md](BoothInit.md)

---

## Quick Mode

### Flow

```
Page 1: Project Type  →  Page 2: Variant  →  Final: Generate
```

### Page 1: Project Type

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

### Page 2: Variant

```
Select environment:
  1) VS Code in browser (codeserver)
  2) Jupyter Notebook
  3) Full desktop (XFCE)
  4) Full desktop (KDE)
  5) Terminal only (base)
Enter choice [1-5]:
```

### Final: Generate

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

### Quick Mode Mapping

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

---

## Advanced Mode

### UI Layout

```
═══════════════════════════════════════════════════════════════════
 Advanced Booth Configuration
═══════════════════════════════════════════════════════════════════
 [Find ^F]  [Setting ^S]  [Done ^D]

 [Languages ^1]  [Frameworks ^2]  [Tools ^3]  [Credentials ^4]
───────────────────────────────────────────────────────────────────

 Languages
 [ ] 1  Python
 [#] 2  Go
        [#] 2-1  VS Code extension
        [ ] 2-2  linter
 [#] 3  Node.js
 [ ] 4  Java
 [ ] 5  Rust

───────────────────────────────────────────────────────────────────
 Toggle [1-5, 2-1, 2-2]
```

### Selection Display

**Multi-select (categories like Languages, Tools, Credentials):**

| Display | Meaning |
|---------|---------|
| `[#]` | Selected |
| `[ ]` | Not selected |
| `[#] 2-1` | Sub-item selected |
| `[ ] 2-1` | Sub-item not selected |
| `[*]` | Auto-selected (dependency of another selection) |

**Single-select (Variant in Config screen):**

| Display | Meaning |
|---------|---------|
| `(#)` | Selected |
| `( )` | Not selected |

### Dependency Behavior

When a template with `requires` is selected, dependencies are auto-selected:

```
 Frameworks
 [#] 1  Spring Boot              ← user selected

 Languages
 [*] 4  Java                     ← auto-selected (required by Spring Boot)
```

- `[*]` indicates auto-selected via dependency
- User cannot deselect `[*]` while the dependent template is selected
- Deselecting Spring Boot releases Java (becomes `[ ]` unless selected directly)

### Parameters

When a template's setup has `params`, they appear below the template (before sub-templates):

```
 Languages
 [ ] 1  Python
 [#] 2  Go
        Version: [latest    ▼]        ← param from go--setup.sh
        [#] 2-1  VS Code extension    ← sub-template (subfolder)
        [ ] 2-2  linter               ← sub-template (subfolder)
 [ ] 3  Node.js
 [#] 4  Java
        JDK Version: [21      ▼]      ← params from jdk--setup.sh
        Vendor:      [temurin ▼]
        [#] 4-1  VS Code extension
        [ ] 4-2  Maven
               Version: [3.9.6   ▼]   ← param from mvn--setup.sh (in sub-template)
```

**Parameter types:**

| Type | Display | Example |
|------|---------|---------|
| `choice` | Dropdown `[value ▼]` | Version: `[latest ▼]` with options |
| `text` | Text input `[value___]` | Custom path: `[/opt/go__]` |

**Interaction:**
- Press Enter on parameter line to edit
- For `choice`: cycle through options or show menu
- For `text`: enter edit mode, type value, press Enter to confirm

### Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `^F` | Open find |
| `^S` | Open setting screen |
| `^D` | Done, generate files |
| `^1` - `^N` | Switch category tabs |
| `1-9` | Toggle item |
| `N-M` | Toggle sub-item (e.g., `2-1`) |

### Config Screen (^C)

```
═══════════════════════════════════════════════════════════════════
 Container Configuration
═══════════════════════════════════════════════════════════════════
 [Back ^B]  [Done ^D]

───────────────────────────────────────────────────────────────────

 Variant
 ( ) 1  VS Code in browser (codeserver)
 (#) 2  Jupyter Notebook
 ( ) 3  Full desktop (XFCE)
 ( ) 4  Full desktop (KDE)
 ( ) 5  Terminal only (base)

 Port:      [NEXT___________]
 Timezone:  [America/Toronto]
 DinD:      [ ] Enable Docker-in-Docker

───────────────────────────────────────────────────────────────────
```

### Search Screen (^S)

```
═══════════════════════════════════════════════════════════════════
 Search
═══════════════════════════════════════════════════════════════════
 [Back ^B]

───────────────────────────────────────────────────────────────────

 Languages
 [#] L2    Go
     [#] L2-1  VS Code extension
     [ ] L2-2  linter

 Frameworks
 [ ] F3    golang-migrate

───────────────────────────────────────────────────────────────────
 > go█
```

**Match behavior:** Prefix match on any word in name, display-name, or tags.

Examples:
- `go` matches "go", "golang-migrate"
- `code` matches "claude-code", "codeserver"
- `py` matches "python", "pycharm"
