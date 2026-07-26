# Browser Shared Example

Team-oriented **browser state via `.booth/shared/`** (git-friendly live bind mounts) —
not `.booth/cache/`.

Demonstrates:

| Concern | Chrome | Firefox |
|---------|--------|---------|
| Bookmarks / settings | `~/.chrome-data/Default/` | `~/.mozilla/firefox/` |
| Extensions (add-ons) | `…/Default/Extensions/` | same `firefox/` tree |
| Enforced team defaults | `setup chrome-managed-policies` | `setup firefox-managed-policies` |

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
  --select 'google-chrome+bookmarks-shared+settings-shared+extensions-shared+managed-policies/firefox+bookmarks-shared+settings-shared+extensions-shared+managed-policies'
```

## Tests

```bash
./run-automatic-on-host-test.sh
```

Checks that shared dirs exist, config declares `shared-dirs` (not cache for browsers),
and sample gitignores are present. Does **not** require a full desktop browser session.

Full guide: [BOOTH_SHARED.md](../../../docs/BOOTH_SHARED.md).
