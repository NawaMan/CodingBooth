# Task004 - Stop, restart, and remove lifecycle commands

## Goal
Implement safe lifecycle controls for active and stopped booth containers.

## Scope
- Add `stop`, `restart`, and `remove` commands.
- Respect keep-alive semantics (`cb.keep-alive`).
- Support force/time options where applicable.

## Implementation steps
1. Add command handlers and shared target lookup utility.
2. `stop`: stop running target; auto-remove only when `cb.keep-alive=false`.
3. `restart`: restart running target with optional timeout.
4. `remove`: remove stopped target(s), optional force for running.
5. Normalize status validation and user-facing errors across all 3 commands.

## Test plan (black-box leaning)
- `stop` on keep-alive booth preserves container.
- `stop` on non-keep-alive booth removes container.
- `restart` keeps same container identity and returns to running.
- `remove` works for one and multiple names; `--force` handles running targets.

## Acceptance criteria
- Lifecycle behavior aligns with documented state model.
- No accidental removal of keep-alive booths.
