# Task008 - Cross-command integration tests and docs

## Goal
Ship lifecycle feature set with reliable integration coverage and user docs.

## Scope
- Add end-to-end lifecycle test scenarios.
- Update CLI help and top-level docs for new commands.
- Document confirmed decisions and deferred items.
- Document the current cross-UID/GID restore limitation.

## Implementation steps
1. Add integration flows: run -> stop/start -> restart -> remove.
2. Add image flows: commit -> backup/restore -> run --image.
3. Add list filtering and quiet-mode coverage.
4. Update command docs and usage examples.
5. Add a short "Known limitations" section for deferred migration.

## Test plan (black-box leaning)
- Full lifecycle flow passes without manual docker intervention.
- Restored image runs with expected behavior for same UID/GID.
- Docs examples map to real command syntax.

## Acceptance criteria
- New commands are discoverable, documented, and test-backed.
- Deferred migration is clearly documented so user expectations are explicit.
