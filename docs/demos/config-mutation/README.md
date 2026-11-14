# Changing a Booth One Entry at a Time

*Note to self — to grow into an article, and a reminder to use this instead of restating lists.*

Line 2 of a Boothfile records the command that made it (`# Configured by: booth config ...`). Every
later `booth config` starts from that line, so a change only has to say what changes. Restating a
list flag (`--select`, `--env`, `--expose`, `--mount`) replaces the whole list — that is how a
toolchain silently disappears. The `--add-*` / `--remove-*` / `--set` / `--unset` flags edit the
baseline in place instead.

The same flags work both ways:

| | Without the TUI | With the TUI |
| --- | --- | --- |
| Command | `booth config --no-tui --overwrite <edits>` | `booth config <edits>` |
| What happens | the edits are applied and `.booth/` is written | the TUI opens with the edits already applied; nothing is written until Ctrl+S |
| Good for | scripts, agents, a quick one-liner | checking the result, then tweaking by hand |

## Without the TUI

```bash
booth config --no-tui --overwrite --add-select docker          # add a template
booth config --no-tui --overwrite --add-select go+linter       # add an extension under go
booth config --no-tui --overwrite --remove-select python       # drop a template and its extensions
booth config --no-tui --overwrite --remove-select go+linter    # drop one extension
booth config --no-tui --overwrite --add-expose 9000:8080 --remove-env DEBUG
booth config --no-tui --overwrite --set keep-alive=true       # one config.toml key
booth config --no-tui --overwrite --unset keep-alive           # drop it again (must be recorded)
booth config --no-tui --dryrun --add-select rust               # print, write nothing
```

Points worth showing:

- **The selection is a tree, addressed by path.** `go`, `go+linter`, `go~lsp` (an exclusion),
  `~glow` (glow taken out of the image). A bare extension name is refused, and the error lists the
  paths it could mean (`vscode-ext` sits under dozens of templates).
- **Only what you write changes.** `--add-select go+lsp` leaves go's version alone.
  `--add-select go:1.25` replaces go's params; `--add-select go:` puts them back to the defaults —
  even a pin that only the Boothfile's `arg` line still holds.
- **Order matters.** Adds and removes apply left to right; the later write to a node wins.
  `--remove-select go --add-select go` brings go back fresh, at its defaults.
- **A recipe expands when used.** `--add-select @web` adds what the recipe holds *now*, and the
  header records those templates, not `@web` — editing the recipe later never changes this booth.
  `--remove-select @web` is refused.
- **A removal that matches nothing is an error, and nothing is written.** A typo never leaves the
  booth half-changed.

## With the TUI

```bash
booth config --add-select go+linter --remove-select python
```

The TUI opens on the existing booth with go+linter added and python gone, and every pin the
booth already had preserved. Look it over, change anything else by hand, then Ctrl+S. Ctrl+Q leaves
the booth untouched. `booth config --web` does the same in the browser.

This is the safe way to try an edit: see the whole result before it is written.

## Demo script (sketch)

1. `booth config --no-tui --select go:1.24.13+linter/python` — a starting booth; show line 2.
2. `--add-select go+go-pkg` — go keeps 1.24.13 and linter.
3. `--remove-select linter` — refused, error names `go+linter`.
4. `--add-select go:` — the version pin goes away, in the header and in `arg GO_VERSION`.
5. `--remove-select nope` — error, `cmp` shows the Boothfile untouched.
6. `booth config --add-select rust` — TUI opens with rust ticked; Ctrl+S.
7. `git diff .booth/` — only what was asked for changed.

## Reference

- [booth config → Adding or removing one entry](../../BOOTH_CONFIG.md#adding-or-removing-one-entry)
- [booth config → Selection paths](../../BOOTH_CONFIG.md#selection-paths)
- Tests: `tests/config/engine/test121-config-add-remove-select.sh`,
  `tests/config/engine/test158-config-select-paths-and-recipes.sh`
