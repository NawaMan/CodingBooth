# Phase 3: Template to Output Conversion

## Tasks

11. Implement merge logic — collect setups from selected templates, sort by `order`, expand params
12. Implement `run-args` aggregation with deduplication of `-v` and `-e` entries
13. Implement dependency resolution (`requires`) with circular dependency detection
14. Implement preference filtering (`required`/`recommended`/`optional`)
15. Implement tie-breaking for same `order` (alphabetical by name)
16. Implement `~` expansion in volume bindings
17. Tests for template-to-output conversion

## Suggested Package Structure

```
internal/
└── design/
    └── template/
        └── resolve.go        # Template → Output conversion
```

## Merge Logic

1. Collect all setups from selected templates
2. Sort by `order` field
3. Tie-breaker for same `order`: alphabetical order of the setup `name`
4. Expand params into setup args (in definition order)
5. Aggregate run-args from all selected templates
6. Collect files and startup scripts

## Run-Args Deduplication

The `-v` and `-e` run-args should be deduplicated across templates. If multiple templates specify the same `-v` or `-e` entry, only include it once.

## Dependency Resolution

When a template has `requires`, those dependencies are auto-selected:
- Auto-select all templates listed in `requires`
- Recursively resolve (dependencies of dependencies)
- Detect circular dependencies and report an error

Example: Spring Boot `requires = ["languages/java"]` → Java is auto-selected.

## Preference Filtering

| Preference    | Quick Mode          | Advanced Mode                  |
|---------------|---------------------|--------------------------------|
| `required`    | Always included     | Auto-selected, cannot deselect |
| `recommended` | Included by default | Pre-selected, can deselect     |
| `optional`    | Excluded            | Not selected, can select       |

## Tilde Expansion

Expand `~` in volume binding paths (e.g., `~/.ssh:/etc/cb-home-seed/.ssh:ro`) to the user's home directory.
