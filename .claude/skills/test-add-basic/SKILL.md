---
name: test-add-basic
description: Add a test under tests/basic/ — one real booth, started and asserted on. Use when the behaviour needs an actual running container but only one, and a handful of assertions. For a multi-step lifecycle across several booths use test-add-complex; for anything that only reads command output use test-add-dryrun or test-add-boothfile, which need no image.
---

# Add a basic test

`$ARGUMENTS` is the behaviour to cover. Basic tests start **one real booth** and assert on it.

**Is this the right suite?** A basic test costs an image and ~30s. Before writing one:

- Only reads what a command *prints*? → `test-add-dryrun` (seconds, no container).
- Only about the generated Dockerfile? → `test-add-boothfile`.
- Several booths, or stop/start/restart across steps? → `test-add-complex`.
- Pure Go logic? → `test-add-unit`.

## 1. Name and place it

`tests/basic/testNNN--what-it-checks.sh`, executable. **The `test0` prefix is not decorative** —
`run-basic-tests.sh` discovers with `for f in test0*.sh`, so a file named anything else is silently
never run. Take the next free number:

```bash
ls tests/basic/test0*.sh | tail -3
```

## 2. The skeleton

```bash
#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Test: <one line on what this locks in, and why it could regress>

set -euo pipefail

source ../common--source.sh

NAME="booth-thing-$RANDOM"
PORT="$(pick_free_port)"

cleanup() {
  docker rm -f "$NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

run_coding_booth --variant base --name "$NAME" --port "$PORT" --daemon --keep-alive \
  > "$0.log" 2>&1 || true
```

`run_coding_booth` (from `common--source.sh`) is how a test invokes the CLI — never call the binary
directly, it resolves the right build and traces the call for diagnostics.

## 3. Assert

One `print_test_result` per case, numbered in the order they run:

```bash
if [[ "$ACTUAL" == "$EXPECTED" ]]; then
  print_test_result "true"  "$0" "1" "The booth published $PORT"
else
  print_test_result "false" "$0" "1" "The booth should have published $PORT, got '$ACTUAL'"
  exit 1
fi
```

The failure line is what someone reads at 2am — **put the actual value in it**. Describe the
behaviour, not the mechanism: "Session cookie opens a live ttyd pane", not "curl returned 200".

## 4. Wait for things, never sleep at them

A container takes an unpredictable moment to appear, and longer on ARM runners. Poll:

```bash
for i in {1..60}; do
  docker inspect "$NAME" >/dev/null 2>&1 && break
  sleep 1
done
```

For "is the booth actually serving", poll `/__booth/health` — not the root, which nginx answers
from disk before the service behind it is up. See `docs/BOOTH_HEALTH.md`.

## 5. Run it

```bash
cd tests/basic && ./testNNN--your-test.sh     # alone, three times — races hide
cd tests/basic && ./run-basic-tests.sh        # then the whole suite
```

Three clean solo runs before you believe it. Anything touching ports, startup, or polling is a race
until proven otherwise.

## Shared rules

`tests/README.md` carries the rules every suite shares — **how to pick a port** (`pick_free_port`,
`pick_free_port_other_than`; never write your own picker), the two `set -euo pipefail` traps that
silently skip a case, cleanup traps, and why you must not edit a test while a suite is running.
Read it before writing.
