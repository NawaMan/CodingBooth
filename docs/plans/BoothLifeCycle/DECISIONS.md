# Booth Lifecycle - Decisions (2026-02-04)

## Confirmed decisions
1. Keep auto-remove as default behavior (no default `--keep-alive`).
2. Add `prune` command later, with confirmation prompt.
3. If container name collides, error with a helpful message.
4. Do not enforce a commit image naming convention.
5. Defer UID/GID ownership migration work; keep current behavior for now.
6. Treat lifecycle reuse as `--keep-alive`-driven; without `--keep-alive`, no resumable lifecycle is expected after exit.

## Known limitation accepted for now
- Images created by one host user and restored/run by a different UID/GID may have permission issues in `/home/coder`.
- We will document this limitation in user-facing docs until migration support is implemented.
