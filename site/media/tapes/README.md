# VHS tapes for the config TUI demo

Two tapes that produce the recordings shown on the landing page and in docs:

- `config-tui-teaser.tape` — ~25 s teaser (tabs tour + search + save).
- `config-tui-full.tape` — ~55 s walkthrough (variant cycle, language + extension, database search, generated `.booth/`).

Both tapes render `.gif` and `.mp4` next to the tape file. Move or symlink the
artifacts into `site/media/` (or wherever the page expects them) after rendering.

## Prerequisites

1. `vhs` installed and on `PATH` ([install instructions](https://github.com/charmbracelet/vhs)).
2. `booth` installed and on `PATH`:
   ```sh
   ./booth install
   eval "$(./booth shell-config)"
   ```
   Verify with `booth --version`.

## Render

```sh
cd site/media/tapes
vhs config-tui-teaser.tape
vhs config-tui-full.tape
```

## Tuning notes

The TUI uses these keys (see `cli/src/pkg/boothinit/tui/model.go`):

- `Left` / `Right` — switch tabs (yes, even on the Config tab).
- `Up` / `Down` — move cursor within a tab.
- `Enter` / `Space` — toggle / activate.
- `Tab` — focus the search bar.
- `Escape` — leave search / cancel edit.
- `Ctrl+S` — save and exit.
- `Ctrl+C` / `Ctrl+E` — quit prompt.

The exact `Down N` counts in `config-tui-full.tape` assume the current ordering
of Config rows (Variant ~3rd row) and Languages templates (Go among the first
few). If the template registry changes, adjust the step counts. If a beat looks
off, bump the preceding `Sleep` so the viewer has time to read.
