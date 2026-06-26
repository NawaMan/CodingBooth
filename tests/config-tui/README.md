# config-tui tests

VHS-driven tests for the **interactive `booth config` TUI**.

The `tests/config/` suite covers CLI mode (`--no-tui --select ...`) thoroughly.
This suite covers the *interactive* path that CLI tests can't reach: launching the
TUI, navigating tabs, searching, selecting templates, auto-select extensions,
dependency resolution, the Config-tab fields (Variant/Port), the parameter
editor, deselection, exit-without-saving, flag pre-population, and editing an
existing booth.

Each test drives the real TUI with [VHS](https://github.com/charmbracelet/vhs)
(charmbracelet/vhs — also used for the demo GIFs under `docs/demos/` and
`site/media/tapes/`), then asserts primarily on the generated `.booth/` files
(`config.toml`, `Boothfile`) and — for TUI-only signals — on the captured final
terminal frame (selection count, `Auto:` / `Dependency:` footer notices).

## Requirements

- `vhs`, `ttyd`, and `ffmpeg` on `PATH` (VHS spawns ttyd + a headless browser).
  Install VHS with `setup vhs` in a Boothfile, or
  `go install github.com/charmbracelet/vhs@latest`.
- A built `./codingbooth` binary at the repo root (`build/cli-build.sh`).

If any of these is missing, the suite **skips** (prints `SKIP:` and exits 0) so it
never breaks CI environments without VHS.

## Running

```bash
# Whole suite (sequential; ~5 min for ~16 recordings)
cd tests/config-tui && ./run-all-tests.sh

# A single test, with the full tape + captured frame echoed
bash test02-tui-select-template.sh --verbose

# Overlap recordings (heavier load — each run starts its own ttyd + browser)
PARALLEL=2 ./run-all-tests.sh

# Via the master runner (opt-in; auto-skips without VHS)
cd tests && ./run-automate-tests.sh --only config-tui
```

On failure, inspect `log--<testname>.log` (full tape + vhs output + cleaned
frame) and `prj--<testname>/frame.clean.txt` (exactly what the TUI rendered).
`./clean-all.sh` removes all `prj--`/`log--`/`run--` artifacts.

## Writing a test

Source the helper and use `run-tui <mode> <keystrokes...>`:

- **mode `save`** — appends `Ctrl+S`; assert on the generated `.booth/` files.
- **mode `frame`** — leaves the TUI displayed (captured into the frame dump),
  then exits without saving; assert on the rendered frame.
- **mode `raw`** — appends nothing; the keystrokes are complete (e.g. the
  exit-without-saving flow).

Assertions: `assert-line` / `assert-file-contains` / `assert-file-not-contains`
on files, `assert-frame` on the captured frame, `assert-file-missing` for
negative checks. Pass extra launch flags via the `LAUNCH_ARGS` array before
calling `run-tui` (e.g. `LAUNCH_ARGS=(--select go)`).

### Tape-authoring caveats (learned the hard way)

- **Write tapes with `printf`, never a heredoc/`cat`** — the dev shell colorizes
  that output and embeds ANSI codes that corrupt the tape (`Invalid command`
  parser errors). The helper already does this.
- **VHS `Output` must be a short/relative path** — a long absolute path makes the
  VHS lexer fail. The helper runs `vhs` from inside the test's `prj` dir and uses
  `Output frame.txt`.
- **Keystrokes are timing- and cursor-sensitive.** The TUI launches on the
  **Languages** tab; the **Config** tab is one `Left` away. Select a template
  with `Tab` (focus search) → `Type "name"` → `Tab` (back to list, cursor on the
  first match) → `Space`. Config fields top-to-bottom: Booth Version, Variant,
  Port, … (so `Down×2` = Variant, `Down×3` = Port). Exit is **Ctrl+E** →
  `Enter` to confirm / `Esc` to cancel. Keep generous `Sleep`s and verify each
  tape against the live TUI — the `.txt` frame dump (no alternate screen) stacks
  every render, so `assert-frame` uses substring matches.
