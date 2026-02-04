# Task003 - Start existing booth

## Goal
Implement `start` for resuming a stopped booth by name or code path.

## Scope
- `codingbooth start` with discovery from current project.
- `--name`, positional name shorthand, `--code`, and `--daemon/-d`.

## Implementation steps
1. Add `start` command parsing and target resolution precedence.
2. Resolve container candidates by labels/name; require stopped state.
3. Execute `docker start` (attached by default, detached with `-d`).
4. Add clear errors for missing target, ambiguous target, or already running target.

## Test plan (black-box leaning)
- Start by default from matching project folder.
- Start by explicit name and by `--code` path.
- `--daemon` starts without attach behavior.
- Friendly failure when no stopped booth exists.

## Acceptance criteria
- Users can reliably resume prior `--keep-alive` booths.
- Error messages include next-step hints (`list --stopped`).
