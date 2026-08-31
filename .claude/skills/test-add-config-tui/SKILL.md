---
name: test-add-config-tui
description: Add a test under tests/config-tui/ — drives the interactive booth config TUI with scripted keystrokes via VHS and asserts on the resulting files or rendered frames. Needs vhs, ttyd and ffmpeg installed. For non-interactive booth config behaviour use test-add-config instead.
---

# Add a config-TUI test

`$ARGUMENTS` is the TUI behaviour to cover. These tests **drive the real terminal UI** with scripted
keystrokes and assert on what it produced.

**Only for genuinely interactive behaviour** — navigation, what a keypress selects, what the screen
shows, what a save writes. If the same outcome is reachable with `--no-tui` flags, write it in
`test-add-config` instead: those run in a fraction of the time and don't need a video toolchain.

**Prerequisites.** `vhs`, `ttyd` and `ffmpeg`. The runner checks for them and the helpers expose
`require-tui-tools` — a missing tool must `skip`, never fail.

## 1. Name and place it

`tests/config-tui/testNN-what-it-checks.sh`, executable. Discovery is `"$SCRIPT_DIR"/test*.sh`.
`tests/config-tui/README.md` covers the harness itself — read it once before your first test here.

## 2. The skeleton

```bash
#!/bin/bash
# TUI: <what interaction this walks, and what it must leave behind>
source "$(dirname "$0")/tui-helpers--source.sh"

begin
```

`begin` gives you a clean `$prj` and a `$log`; `$BOOTH_BIN` and `$TEMPLATES_PATH` are the binary and
template path to drive.

## 3. Seed non-interactively, then drive the TUI

The strongest pattern in this suite: set the starting state with `--no-tui` (fast and reliable),
then open the TUI and assert it *loaded* that state and added to it. That isolates the interaction
from the setup.

```bash
run() { "$@" >> "$log" 2>&1 ; }

run "$BOOTH_BIN" config "$prj" --no-tui --select go --templates-path "$TEMPLATES_PATH"
if [[ ! -f "$prj/.booth/Boothfile" ]]; then
    skip "seed step did not produce a .booth/Boothfile"
fi

run-tui save \
    'Tab' 'Type "python"' 'Sleep 600ms' \
    'Tab' 'Sleep 300ms' 'Space' 'Sleep 500ms'
```

`run-tui`'s arguments are VHS commands. **The `Sleep`s are load-bearing** — the TUI redraws
asynchronously, and a keystroke sent before the redraw lands goes to the previous screen. When a
test is flaky here, an absent or too-short `Sleep` is the first suspect.

## 4. Assert on files first, frames second

| Helper | Use |
|--------|-----|
| `assert-file-contains FILE TEXT MESSAGE` | the durable outcome — prefer this |
| `assert-file-not-contains` / `assert-file-missing` | what a save must *not* have written |
| `assert-line` | one line of a generated file |
| `assert-frame` | what the screen rendered — only when the visible output *is* the behaviour |
| `skip REASON` | missing tool or failed seed |
| `finally` | prints the summary and sets the exit code — **required** |

Prefer file assertions. A frame assertion is a screenshot comparison: it breaks on cosmetic changes
and tells you little when it does. Reach for `assert-frame` only when what the user sees is the
thing under test.

Assert both directions on a save — that the new selection is there **and** the pre-existing one
survived. "Adding python kept go" is the regression worth catching.

## 5. Run it

```bash
cd tests/config-tui && ./testNN-your-test.sh
cd tests/config-tui && ./run-all-tests.sh
```

Run it several times. TUI timing tests are the flakiest in the repo — three clean runs before you
believe it.

## Shared rules

`tests/README.md` carries the rules every suite shares — port picking, the two `set -euo pipefail`
traps that silently skip a case, cleanup, and why you must not edit a test while a suite is running.
