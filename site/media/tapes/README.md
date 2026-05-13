# VHS tapes for the config TUI demo

- `config-tui.tape` — ~18 s walkthrough: open the TUI, pick a language with an
  extension, search for a database, save, then `ls .booth/` + `cat Boothfile`
  to show the generated recipe.
- `config-tui-deep.tape` — ~20 s "go deeper": cycle the **Variant** cycle-field
  on the Config tab, then `Space`-select a template and `Enter` to open its
  parameter editor (right pane). Generous `Sleep`s are left in so keypress
  overlays can be added in post.

Rendering produces `.gif` and `.mp4` siblings next to each tape. Both are
gitignored — move or symlink them into `site/media/` (or wherever the page
expects them) after rendering.

## Prerequisites

1. `vhs` installed and on `PATH` ([install instructions](https://github.com/charmbracelet/vhs)).
2. A self-contained `booth` install inside this directory at `.sandbox/`:
   ```sh
   mkdir -p .sandbox
   cp ../../../booth .sandbox/booth
   (cd .sandbox && ./booth install --cache=local)
   ```
   The tape adds `.sandbox/` to `PATH` in its hidden setup block, so no
   system-wide install is required. `.sandbox/` is gitignored.

## Render

```sh
cd site/media/tapes
vhs config-tui.tape
vhs config-tui-deep.tape
```

## Tuning notes

The TUI keys (see `cli/src/pkg/boothinit/tui/model.go`):

- `Left` / `Right` — switch tabs.
- `Up` / `Down` — move cursor within a tab.
- `Enter` / `Space` — toggle / activate.
- `Tab` — focus the search bar.
- `Escape` — leave search / cancel edit.
- `Ctrl+S` — save and exit.
- `Ctrl+C` / `Ctrl+E` — quit prompt.

Important quirks:

- The TUI opens on the **Languages** tab (index 1), not Config — so `Left` from
  the default lands on Config, and `Right` lands on Databases.
- On the Config tab the cursor starts at the **Booth** group header (rendered
  invisibly); `Down 1` → Booth Version, `Down 2` → Variant.
- Template lists are alphabetical; `Down N` counts depend on registry order.
  At the time of writing, position 0 on Languages is `bun`. If the registry
  changes, either re-tune the `Down` count or switch to the search route
  (`Tab` → `Type "..."`).
- The param editor (right pane) opens with `Enter` **only after the template
  is `Space`-selected** — `Enter` on an unselected template is a no-op.
- If a beat looks rushed in the recording, bump the preceding `Sleep`.
