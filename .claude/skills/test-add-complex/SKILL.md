---
name: test-add-complex
description: Add a test under tests/complex/ — a multi-step booth lifecycle in its own directory. Use when the behaviour spans several steps or booths (stop/start, restart, connect, expose, persistence) rather than one container and a couple of assertions. For a single booth use test-add-basic; for output-only checks use test-add-dryrun.
---

# Add a complex test

`$ARGUMENTS` is the behaviour to cover. Complex tests exercise a **lifecycle** — several steps, and
often several booths, where the interesting part is what survives between them.

**Is this the right suite?** Complex tests are the slowest thing in the repo. Use it only when the
behaviour genuinely spans steps: stop/start preserving state, restart, `exec` against an existing
booth, expose, persistence, port scanning. One booth and three assertions belongs in
`test-add-basic`.

## 1. Name and place it

Complex tests get **their own directory** — the runner discovers with `for test_dir in test-*/`:

```
tests/complex/test-<scenario>/test--<scenario>.sh
```

The directory is also where fixtures live (a `.booth/`, a Boothfile, seed files). A directory that
does not match `test-*/` is never run.

## 2. The skeleton

```bash
#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# <what lifecycle this walks, and what each step proves>

set -euo pipefail

source ../../common--source.sh      # note: two levels up

NAME="lifecycle-thing-$RANDOM"
PORT_A="$(pick_free_port)"
PORT_B="$(pick_free_port_other_than "$PORT_A")"

cleanup() {
  docker rm -f "$NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT
```

Small `docker inspect` wrappers at the top keep the steps readable — the existing tests define
things like:

```bash
host_port() { docker inspect -f '{{(index (index .HostConfig.PortBindings "'"$2"'/tcp") 0).HostPort}}' "$1" 2>/dev/null || true; }
state_of()  { docker inspect -f '{{.State.Status}}' "$1" 2>/dev/null || true; }
```

## 3. Structure the steps

Number the cases in lifecycle order and say what each step *establishes*, because a later step
depends on it:

```bash
# 1) Create keep-alive container with explicit name/port.
# 2) stop/start preserves the UI port.
# 3) start rejects --port override (documented behaviour).
# 4) recreate allows the override.
```

A step that fails should `exit 1` rather than let later steps assert against a booth that never
reached the expected state.

## 4. Two ports are not two different ports

Lifecycle tests almost always need a second port — the "some other port" an override is tested
with, or a second published mapping on the same container. Ask for it explicitly with
`pick_free_port_other_than`; two `pick_free_port` calls can return the same number, and the failure
is confusing (docker binding one host port twice, or a case that passes having proven nothing).

## 5. Run it

```bash
cd tests/complex/test-<scenario> && ./test--<scenario>.sh    # alone, a few times
cd tests/complex && ./run-complex-tests.sh                   # the suite (long)
```

The suite supports sharding for CI — shards are round-robin over the sorted test list, so a new
directory changes shard membership. That is expected; don't pin to a shard.

**When a booth call returns nothing**, the tests discard stderr but the suite traces every call —
command, exit code, stderr — to `tests/logs/complex-booth-calls.log`. Start there.

## Shared rules

`tests/README.md` carries the rules every suite shares — **how to pick a port**, the two
`set -euo pipefail` traps that silently skip a case, cleanup traps, and why you must not edit a test
while a suite is running. Read it before writing.
