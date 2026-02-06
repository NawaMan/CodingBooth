# Phase 4: Template Loading

## Tasks

18. Implement TOML parser for `spec.toml` and `meta.toml`
19. Build template registry from extracted directory (categories, templates, sub-templates)
20. Validate template structure (missing fields, invalid references)
21. Tests for template loading

## Suggested Package Structure

```
internal/
└── design/
    └── template/
        ├── loader.go         # TOML parsing and registry
        └── model.go          # Template data structures (from Phase 2)
```

## Template Directory Layout

```
/templates/
├── quick-mode.toml                    # Quick mode mappings
├── languages/
│   ├── meta.toml                      # Category metadata
│   ├── python/
│   │   ├── spec.toml                  # Template spec
│   │   ├── extension/                 # Sub-template
│   │   │   └── spec.toml
│   │   └── extras--setup.sh           # Custom setup script (optional)
│   ├── go/
│   │   ├── spec.toml
│   │   ├── extension/
│   │   │   └── spec.toml
│   │   └── linter/
│   │       └── spec.toml
│   └── nodejs/
│       └── spec.toml
├── frameworks/
│   ├── meta.toml
│   ├── django/
│   │   └── spec.toml
│   └── fastapi/
│       └── spec.toml
├── tools/
│   ├── meta.toml
│   ├── claude-code/
│   │   └── spec.toml
│   └── neovim/
│       └── spec.toml
└── credentials/
    ├── meta.toml
    ├── ssh/
    │   └── spec.toml
    └── claude/
        └── spec.toml
```

## Loading Process

1. Scan top-level directories for `meta.toml` → build `Category` list
2. Within each category directory, scan subdirectories for `spec.toml` → build `Template` list
3. Within each template directory, scan subdirectories for `spec.toml` → build sub-template list
4. Detect custom setup scripts (`*--setup.sh`) in template folders
5. Validate all `requires` references point to existing templates
6. Validate no missing required fields in spec.toml

## Category meta.toml

```toml
display-name = "Languages"
order = 1
```

## Template spec.toml

See Phase 2 for the full spec.toml structure with setups, params, files, startup-scripts, and run-args.

## Setup Script Resolution

Setup scripts are resolved in this order:
1. Built-in scripts (already in the CodingBooth image at `/opt/codingbooth/setups/`)
2. Template folder (custom script bundled with the template)

If a custom script is found in the template folder, a `COPY` instruction is added to the Dockerfile.
