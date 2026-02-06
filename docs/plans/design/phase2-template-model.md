# Phase 2: Template Data Model

## Tasks

8. Define Go structs for template models (`Category`, `Template`, `Setup`, `Param`, `RunArg`, `File`, `StartupScript`)
9. Define selection state models (`SelectionState`, `ParamValues`)
10. Tests for template data model

## Suggested Package Structure

```
internal/
└── design/
    └── template/
        └── model.go          # Template data structures
```

## Go Structs

### Category (from `meta.toml`)

```toml
display-name = "Languages"
order = 1
```

Categories are displayed in `order` sequence. Keyboard shortcuts (`^1`, `^2`, etc.) assigned by order.

### Template (from `spec.toml`)

```toml
display-name = "Go"
display-order = 30                      # Display order within category
tags = ["golang", "backend", "compiled"]

# Dependencies - auto-selected when this template is selected
requires = []                           # e.g., ["languages/java"] for Spring
```

### Setup (nested in Template)

```toml
[[setups]]
name = "go--setup.sh"                   # Looks in built-in first, then template folder
order = 60                              # RUN order in Dockerfile (maps to 50-79 ranges)
preference = "required"                 # required | recommended | optional
```

### Param (nested in Setup)

```toml
[[setups.params]]
name = "version"
display-name = "Go Version"
type = "choice"                       # choice | text
default = "latest"
choices = ["latest", "1.24", "1.23", "1.22"]
```

### RunArg

```toml
[[run-args]]
values = ["-e", "GOPROXY=https://proxy.golang.org,direct"]
preference = "optional"
```

### File

```toml
[[files]]
name = ".golangci.yml"                  # Looks in built-in first, then template folder
target = "home-seed"                    # home | home-seed
order = 50
preference = "optional"
```

### StartupScript

```toml
[[startup-scripts]]
name = "go-env-setup.sh"
order = 60
preference = "recommended"
```

## Sub-templates

Sub-templates are subfolders with their own `spec.toml`. They are:
- Standalone (no inheritance from parent)
- Displayed as sub-items (e.g., `2-1`, `2-2`) when parent is selected
- Independent selection (selecting parent doesn't auto-select children)

## Selection State

- `SelectionState` — tracks whether a template is: not selected, user-selected, or auto-selected (via dependency)
- `ParamValues` — tracks user-specified param overrides vs defaults

## Preference Behavior

| Preference    | Quick Mode    | Advanced Mode                  |
|---------------|---------------|--------------------------------|
| `required`    | Auto-included | Auto-selected, cannot deselect |
| `recommended` | Auto-included | Pre-selected, can deselect     |
| `optional`    | Excluded      | Not selected, can select       |
