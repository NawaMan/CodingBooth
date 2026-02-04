# Task006 - Image distribution (push, backup, restore)

## Goal
Support sharing committed images via registry and files.

## Scope
- Add `push`, `backup`, and `restore` commands.
- `push` optional registry targeting.
- `backup` output path + optional compression.
- `restore` from tar/tar.gz and show loaded image info.

## Implementation steps
1. Wire command routing and validation for each command.
2. `push`: optional re-tag flow then `docker push`.
3. `backup`: `docker save` to output; gzip path when `--compress`.
4. `restore`: `docker load` from file and parse loaded tag(s).
5. Add clear guidance after restore (`run --image ...`).

## Test plan (black-box leaning)
- `backup` creates file at requested path.
- `restore` loads image that can be run afterward.
- `push` builds correct target image ref with registry option.
- Validation errors for missing input/output args are clear.

## Acceptance criteria
- Users can export/import booth images offline and via registry paths.
