# Booth Lifecycle - Phase 1 Implementation Plan

## Goal
Deliver core container lifecycle management first, with practical black-box tests and minimal behavioral change.

## Lifecycle activation rule
- Lifecycle reuse commands (`start`, `restart`, `remove` on stopped booth state, and meaningful `list` history) are primarily for booths started with `--keep-alive`.
- If a booth is run without `--keep-alive` (default), container cleanup is expected on exit, so there is no resumable lifecycle state to manage afterward.

## Included tasks
1. `Task001-run-labels-and-default-behavior.md`
2. `Task002-list-managed-booths.md`
3. `Task003-start-existing-booth.md`
4. `Task004-stop-restart-remove-lifecycle.md` (Phase 1 scope: `stop` and `remove` first; `restart` can follow immediately after)

## Out of phase (deferred)
- `Task005-commit-container-state.md`
- `Task006-image-distribution-push-backup-restore.md`
- `Task007-uid-gid-migration-marker-based.md` (deferred by decision)
- `Task008-cross-command-integration-tests-and-docs.md` (full-suite pass after Phase 1 merge)
- `Task009-prune-with-confirmation.md`

## Phase 1 delivery checkpoints
1. Containers created by `run` include lifecycle labels.
2. Lifecycle behavior is explicitly documented as `--keep-alive`-driven.
3. `list` works with running/stopped/quiet filters.
4. `start` can resume stopped keep-alive booths.
5. `stop` and `remove` have safe, clear behavior and messages.
6. Collision and no-target errors are actionable.

## Test strategy
- Prefer black-box CLI behavior checks over internal helper unit tests.
- Validate externally observable lifecycle state transitions.
- Keep white-box tests only for hard-to-reach edge handling.
