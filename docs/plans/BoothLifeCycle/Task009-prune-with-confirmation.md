# Task009 - Prune stopped booths with confirmation

## Goal
Add a safe `prune` command to clean up stopped booth-managed containers.

## Scope
- Add `codingbooth prune` command.
- Only target booth-managed containers (`cb.managed=true`) in stopped state.
- Require interactive confirmation by default.
- Support `--yes/-y` to skip prompt for automation.

## Implementation steps
1. Add command and docker query for prune candidates.
2. Show clear summary of what will be removed before prompt.
3. Ask for confirmation; abort cleanly on negative answer.
4. Remove candidates and print result counts.
5. Add `--yes` non-interactive path for CI/scripts.

## Test plan (black-box leaning)
- `prune` prompts before removal.
- Negative confirmation keeps containers untouched.
- Positive confirmation removes only stopped booth containers.
- `prune --yes` removes without prompt.

## Acceptance criteria
- Cleanup is safe-by-default and predictable.
- No running booth container is removed by prune.
