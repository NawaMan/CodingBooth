---
name: test-add-wrapper
description: Add a test under tests/wrapper/ — exercises the ./booth wrapper script inside a container, asserting on what it dispatches, intercepts, or passes through to the binary. Uses its own _lib.sh with run_in_container and assert_contains. For CLI behaviour rather than wrapper behaviour, use test-add-dryrun or test-add-basic.
---

# Add a wrapper test

`$ARGUMENTS` is the wrapper behaviour to cover. These tests run the `booth` wrapper script **inside
a container** and assert on what it did with a command.

**What this suite is for.** The wrapper sits in front of the binary and handles a few commands
itself, passing everything else through. The tests that earn their place are the ones guarding that
boundary: a regression guard for anyone adding a command to the wrapper's dispatch that should have
gone to the binary. If your question is what the *CLI* does with a flag, that is `test-add-dryrun`.

## 1. Name and place it

`tests/wrapper/NNN-what-it-checks.sh`, executable. Discovery is `[0-9][0-9][0-9]-*.sh` — a
**three-digit prefix, run in order**, unlike every other suite. Take the next number:

```bash
ls tests/wrapper/[0-9][0-9][0-9]-*.sh | tail -3
```

## 2. The skeleton

```bash
#!/usr/bin/env bash
# NNN — <what must hold, and what regression it guards against>
source "$(dirname "$0")/_lib.sh"

LAST_OUTPUT=$(run_in_container <<'BASH'
set -e
cp /booth/booth ./booth
./booth install >/dev/null
echo "=== SECTION ==="
./booth tools-cache list 2>&1 || true
BASH
)
```

`run_in_container` takes the script on stdin as a heredoc and runs it in the wrapper test image
(`ensure_image` builds it if missing). Quote the heredoc marker — `<<'BASH'` — so the script reaches
the container as written rather than being expanded on the host.

**Print section markers** and slice on them. It keeps an assertion aimed at the command under test
instead of at everything the container printed:

```bash
section="${LAST_OUTPUT##*=== SECTION ===}"
```

## 3. Assert

| Helper | Use |
|--------|-----|
| `assert_contains HAYSTACK NEEDLE` | the output says what it should |
| `assert_not_contains HAYSTACK NEEDLE` | the output does *not* say what it must not |
| `assert_eq ACTUAL EXPECTED` | exact match |
| `pass MESSAGE` / `fail MESSAGE` | report the case |
| `public_preflight` | for cases needing the public-facing setup |

`assert_not_contains` carries most of the weight here, and it is the right tool for a passthrough
test: you cannot easily assert the binary handled a command, but you *can* assert the wrapper's
fingerprints are absent — no `Wrapper commands:` help text, no `Unknown <cmd> command:` error.

## 4. Know when red is not your fault

These tests build and run against a container image, and some cases depend on things outside this
checkout. The runner is deliberate about this — asking for a test by number counts as opting in to
running it anyway. Before chasing a failure, check whether the same test fails on a clean tree.

## 5. Run it

```bash
cd tests/wrapper && ./run-all.sh NNN     # just yours, by number
cd tests/wrapper && ./run-all.sh         # all, in order
```

## Shared rules

`tests/README.md` carries the rules every suite shares — port picking, the two `set -euo pipefail`
traps that silently skip a case, cleanup, and why you must not edit a test while a suite is running.
