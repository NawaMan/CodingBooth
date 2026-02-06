# Phase 9: Advanced Mode TUI

## Tasks

45. TUI framework setup (bubbletea)
46. Category tabs with `^1`–`^N` navigation
47. Item list with selection toggle (`[ ]`, `[#]`, `[*]`)
48. Sub-item display and toggle (`N-M` format)
49. Parameter editing (choice dropdown, text input)
50. Config screen (`^S`) — variant, port, timezone, DinD
51. Find/search screen (`^F`) with prefix matching
52. Review and generate (`^D`)

## Suggested Package Structure

```
internal/
└── design/
    └── tui/
        └── app.go            # Advanced mode TUI (using bubbletea)
```

## Invocation

```bash
./booth design --advance
```

## UI Layout

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

## Selection Display

**Multi-select (categories like Languages, Tools, Credentials):**

| Display    | Meaning                                         |
|------------|-------------------------------------------------|
| `[#]`      | Selected                                        |
| `[ ]`      | Not selected                                    |
| `[#] 2-1`  | Sub-item selected                               |
| `[ ] 2-1`  | Sub-item not selected                           |
| `[*]`      | Auto-selected (dependency of another selection) |

**Single-select (Variant in Config screen):**

| Display | Meaning      |
|---------|--------------|
| `(#)`   | Selected     |
| `( )`   | Not selected |

## Dependency Behavior

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

## Parameters

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

| Type     | Display                 | Example                            |
|----------|-------------------------|------------------------------------|
| `choice` | Dropdown `[value ▼]`    | Version: `[latest ▼]` with options |
| `text`   | Text input `[value___]` | Custom path: `[/opt/go__]`         |

**Interaction:**
- Press Enter on parameter line to edit
- For `choice`: cycle through options or show menu
- For `text`: enter edit mode, type value, press Enter to confirm

## Keyboard Shortcuts

| Key          | Action                         |
|--------------|--------------------------------|
| `^F`         | Open find                      |
| `^S`         | Open setting screen            |
| `^D`         | Done, generate files           |
| `^1` - `^N` | Switch category tabs           |
| `1-9`        | Toggle item                    |
| `N-M`        | Toggle sub-item (e.g., `2-1`) |

## Config Screen (^S)

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

## Search Screen (^F)

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
