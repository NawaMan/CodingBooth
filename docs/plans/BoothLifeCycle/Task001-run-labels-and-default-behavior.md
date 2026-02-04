# Task001 - Run labels and default behavior parity

## Goal
Add lifecycle metadata labels at container creation while preserving current default `run` behavior (implicit and explicit).

## Scope
- Add `cb.managed=true`, `cb.project`, `cb.variant`, `cb.code-path`, `cb.created-at`, `cb.version`, `cb.keep-alive` labels.
- Keep `./codingbooth` (no subcommand) behavior equivalent to `./codingbooth run`.
- On container name conflict, fail with a helpful remediation message.
- No behavioral regression in existing `run` flags.

## Implementation steps
1. Extend run/common arg builder to emit the full label set.
2. Normalize label values (absolute code path, stable timestamp format, resolved variant).
3. Ensure both implicit default invocation and explicit `run` path share the same execution path.
4. Add structured errors if label generation inputs are missing/invalid.
5. Improve name-collision error text with suggested next actions (for example: choose `--name`, stop/remove existing booth, or use `list`).

## Test plan (black-box leaning)
- `run` creates container with all required `cb.*` labels.
- Bare `./codingbooth` and `./codingbooth run` produce equivalent docker invocation.
- `--keep-alive` toggles `cb.keep-alive=true|false` as expected.
- Running twice with same resolved name fails with a clear actionable message.
- Existing run scenarios (variant, name, port) still work.

## Acceptance criteria
- Labels are visible via `docker inspect` for newly created containers.
- No regressions in existing run workflows.
