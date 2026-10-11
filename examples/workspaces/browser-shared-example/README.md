# Browser Shared Example

Team-oriented **browser state via `.booth/shared/`** (git-friendly live bind mounts) —
not `.booth/cache/`.

Demonstrates:

| Concern | Chrome | Firefox |
|---------|--------|---------|
| Bookmarks / settings | `~/.chrome-data/Default/` | `~/.mozilla/firefox/` |
| Extensions (add-ons) | `…/Default/Extensions/` | same `firefox/` tree |
| Enforced team defaults | `setup chrome-managed-policies` | — (see below) |
| Starting bookmarks | `+bookmarks-seed` → `…/Default/Bookmarks` | `+bookmarks-seed` → `firefox/booth.default/bookmarks.html` |

## Starting bookmarks

`.booth/shared-seed/` holds the bookmarks a fresh booth starts with — a bookmark bar with
CodingBooth's site and repo in both browsers. Edit them there and commit:

| Browser | Seed file |
|---------|-----------|
| Chrome | `.booth/shared-seed/home/coder/.chrome-data/Default/Bookmarks` (Chrome's JSON) |
| Firefox | `.booth/shared-seed/home/coder/.mozilla/firefox/booth.default/bookmarks.html` |

They are copied into `.booth/shared/` only while the browser has no bookmarks there yet, and never
over bookmarks you have since changed. Firefox imports its file on its first start. To start over,
delete `.booth/shared/home/coder/.chrome-data/Default/Bookmarks` or the whole
`.booth/shared/home/coder/.mozilla/firefox/` tree (keep its `.gitignore` and `.mount-this`).

Firefox runs without `+managed-policies` here. That policy set includes `DisableTelemetry`, which
on current Firefox stops the first start from creating its bookmarks toolbar, so the seed has
nowhere to go.

Sample `.gitignore` files under `.booth/shared/…` limit what you should commit
(see also `docs/samples/browser-shared-*.gitignore`).

## Run

```bash
./booth
# desktop XFCE → open Chrome / Firefox → change bookmarks, prefs, install an add-on
```

On the host, paths under `.booth/shared/home/coder/` should update. Restart the
booth; state should still be there.

## Templates (equivalent)

```bash
booth config --no-tui . --variant xfce \
  --select 'google-chrome+bookmarks-shared+settings-shared+extensions-shared+managed-policies+bookmarks-seed/firefox+bookmarks-shared+settings-shared+extensions-shared+bookmarks-seed'
```

## Tests

```bash
./run-automatic-on-host-test.sh
```

Checks that shared dirs exist, config declares `shared-dirs` (not cache for browsers),
the bookmark seeds are in place, and sample gitignores are present. Does **not** require a full desktop browser session.

Full guide: [BOOTH_SHARED.md](../../../docs/BOOTH_SHARED.md).
