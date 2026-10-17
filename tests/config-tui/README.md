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
Both live under `$TMPDIR/codingbooth-config-tui-tests/`, not in this directory.

`run-all-tests.sh` retries a failing test once, and a retry re-runs the same
script — which truncates that log and wipes that prj. So for a test that passed
only on its second attempt, the two paths above hold the attempt that *passed*;
the failure is kept beside them as `log--<testname>.attempt1.log` and
`prj--<testname>--attempt1/frame.clean.txt`, and that is the pair to read. A
first attempt with `vhs exited with code N` and `no frame.txt captured` failed
to record at all, which is a different problem from a frame that came out wrong.

`./clean-all.sh` removes all `prj--`/`log--`/`run--` artifacts, in both places.

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
  first match) → `Space`. A template with unselected `requires` (kotlin → java,
  kind → dind) does **not** select on Space: it asks `… requires … — add it
  too? [y/n]`. Answer with `Enter`/`y` before `Ctrl+S` — the prompt swallows
  every other key, so a save while it is up writes nothing. Config fields
  top-to-bottom: Booth Version, Variant, Port, … (so `Down×2` = Variant,
  `Down×3` = Port). Exit is **Ctrl+E** → `Enter` to confirm / `Esc` to cancel.
  Keep generous `Sleep`s and verify each tape against the live TUI — the `.txt`
  frame dump (no alternate screen) stacks every render, so `assert-frame` uses
  substring matches.

### When a run wedges, and the ttyd backlog

A tape that does not land where it expects can leave `vhs` wedged. `run-tui`
caps it with `run-with-timeout 120`, and that cap has to be able to kill a **Go**
process: an earlier version used `perl -e 'alarm …; exec …'`, and Go ignores
SIGALRM, so a wedged vhs ran for 56 minutes under a 120-second limit. A wedged
vhs also ignores SIGTERM — only SIGKILL ends it — so the guard forks a watchdog
that escalates. `tests/setups/test--tui-run-with-timeout.sh` locks both in.

The reason this matters beyond one slow run: vhs starts its own `ttyd` and only
reaps it on the way out, so a vhs that never returns leaks one. The leak then
*causes* the next wedge — a machine was found with 115 stray `ttyd`, the oldest
16 days, and clearing them made the wedging test pass on the retry. If the suite
hangs on a TUI test, check for the backlog before suspecting the test:

```bash
pgrep -f 'ttyd --port=' | wc -l     # should be 0 between runs
pkill -f 'ttyd --port='             # safe: booth containers' ttyd are not these
./tests/config-tui/clean-all.sh     # scratch dirs (files only, no processes)
```
