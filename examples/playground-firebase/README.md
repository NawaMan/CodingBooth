# playground-firebase

Personal/playground booth to **test Firebase CLI host-credential seeding**, especially the case where firebase-tools leaves an empty or `{}` `firebase-tools.json` that would block a normal no-clobber home-seed.

Not the polished product example (`examples/workspaces/firebase-example`). This tree is intentionally small: base variant, Firebase only, one credential mount.

## Prerequisites

On the **host**:

```bash
firebase login
# → ~/.config/configstore/firebase-tools.json
```

## What's here

| Piece | Role |
| --- | --- |
| `.booth/Boothfile` | `setup firebase` |
| `.booth/config.toml` | `variant = "base"` + host credential bind to `/etc/cb-home-seed/...` |
| `.booth/setups/firebase--setup.sh` | Runs product installer, then installs the **placeholder-aware** startup (empty / `{}` → copy host seed) |
| `check-connection.sh` | `firebase login:list` smoke |
| `test-placeholder-seed.sh` | Plants `{}`, re-runs startup, asserts login works |

Once a published base image ships the same startup, you can delete `.booth/setups/` and keep using `setup firebase` alone.

## Try it

From this directory (repo root `codingbooth` or a local pin):

```bash
cd examples/playground-firebase

# Build + run check (first build installs firebase-tools — can take a few minutes)
/path/to/codingbooth -- ./check-connection.sh

# Explicit placeholder regression
/path/to/codingbooth -- ./test-placeholder-seed.sh

# Interactive
/path/to/codingbooth
# inside:
firebase login:list
firebase projects:list
```

## Expected result

With a real host login:

```text
Logged in as you@example.com
✅ Firebase connection OK
```

`test-placeholder-seed.sh` should print `✅ placeholder seed test OK` after replacing a planted `{}`.

## Security

- Credentials stay on the host; mount is `:ro`.
- Nothing under this playground commits tokens.
- Container gets a writable copy under `~/.config/configstore/`.
