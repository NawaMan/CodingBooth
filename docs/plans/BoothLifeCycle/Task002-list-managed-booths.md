# Task002 - List managed booths

## Goal
Implement `list` to show booth-managed containers with useful lifecycle metadata.

## Scope
- Add `codingbooth list` command.
- Filter by `cb.managed=true`.
- Support `--running`, `--stopped`, and `--quiet/-q`.

## Implementation steps
1. Add command wiring and help text.
2. Query docker with label filter and status filter mapping.
3. Parse container metadata (name, status, variant, port, code path, created).
4. Render table output; `-q` returns names only.
5. Return actionable error/help when no matching containers exist.

## Test plan (black-box leaning)
- `list` returns only booth-managed containers.
- `list --running` excludes stopped containers.
- `list --stopped` excludes running containers.
- `list -q` prints one name per line, no table formatting.

## Acceptance criteria
- `list` output is stable and human-readable.
- Filtering behavior matches command flags exactly.
