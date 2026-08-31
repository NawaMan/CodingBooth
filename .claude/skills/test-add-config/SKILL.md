---
name: test-add-config
description: Add a test under tests/config/ — covers booth config and booth init non-interactively (template selection, recipes, generated .booth/ contents). Uses its own helper library with begin/assert-line/finally, not common--source.sh. For the interactive TUI use test-add-config-tui.
---

# Add a config test

`$ARGUMENTS` is the behaviour to cover. This suite exercises `booth config` and `booth init`
**non-interactively** — template selection, recipes, flags, and what lands in the generated
`.booth/`.

**Different vocabulary from the rest of the repo.** This suite does *not* source
`common--source.sh` and does *not* use `print_test_result`. It has its own helpers, and mixing the
two produces a test that reports nothing the runner can see.

For the interactive terminal UI, use `test-add-config-tui`.

## 1. Name and place it

`tests/config/testNN-what-it-checks.sh`, executable. Discovery is `"$SCRIPT_DIR"/test*.sh`, with
`test-helpers--source.sh` excluded — a broad glob, so a stray `test`-prefixed file in this
directory gets run.

## 2. The skeleton

```bash
#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin
```

`begin` does the setup: names the test from the filename, opens `$log`, removes a leftover
`prj--${testname}` container from a previous run, and creates a clean project directory at `$prj`.
So `$prj`, `$log`, `$testname` and `$tmpfile` are all available afterwards — use them rather than
rolling your own.

## 3. The helpers

| Helper | What it does |
|--------|--------------|
| `begin` | opens the test: clean `$prj`, fresh `$log`, container from a previous run removed |
| `booth …` | runs the CLI under test |
| `run …` | runs any command with output going to `$log` |
| `booth-collect` | runs a booth and collects its output (`booth-collect-dind` for the DinD variant) |
| `assert-line FILE PREFIX EXPECTED MESSAGE` | asserts one line of a generated file |
| `assert-last EXPECTED MESSAGE` | asserts on the last collected output |
| `skip REASON` | ends the test as SKIPPED (exit 2) — a missing prerequisite, not a failure |
| `finally` | prints the pass/fail summary and sets the exit code — **required at the end** |

`finally` is not optional: it is what reports the result and exits non-zero on failure. A test
without it passes silently no matter what happened.

## 4. Prefer skip over a false failure

If a prerequisite is missing — a tool, a network fixture that did not come up — call `skip` with the
reason. A red suite that means "the fixture didn't start" trains people to ignore red.

```bash
if [[ ! -f "$prj/.booth/Boothfile" ]]; then
    skip "seed step did not produce a .booth/Boothfile"
fi
```

## 5. Fixtures that serve over HTTP

Recipe-from-URL cases start a throwaway Python HTTP server on an ephemeral port and write the
chosen port to a file for the test to read. Follow the existing pattern in the recipe tests, and
kill the server in the test's cleanup — a leaked server holds a port for the rest of the run.

## 6. Run it

```bash
cd tests/config && ./testNN-your-test.sh
cd tests/config && ./run-all-tests.sh              # 120+ tests, parallel
cd tests/config && ./run-all-tests.sh --verbose    # shows the image builds
```

The runner takes `--jobs N` (default 4) and `--heartbeat` to report what is still in flight. Run
your test alone first; the full suite is long.

## Shared rules

`tests/README.md` carries the rules every suite shares — port picking, the two `set -euo pipefail`
traps that silently skip a case, cleanup, and why you must not edit a test while a suite is running.
