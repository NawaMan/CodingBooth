# Task005 - Commit container state

## Goal
Implement `commit` to snapshot booth container state into a reusable image.

## Scope
- Add `codingbooth commit` command.
- Require `--tag`; support `--name` and `--message`.

## Implementation steps
1. Add command parser with required tag validation.
2. Resolve target container (running or stopped).
3. Execute `docker commit` with optional message metadata.
4. Print resulting image reference and next suggested commands.

## Test plan (black-box leaning)
- Commit succeeds for running booth.
- Commit succeeds for stopped booth.
- Missing `--tag` returns validation error.
- Output includes produced image tag.

## Acceptance criteria
- Users can produce a restorable image from booth state in one command.
