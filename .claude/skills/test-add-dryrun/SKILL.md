---
name: test-add-dryrun
description: Add a test under tests/dryrun/ — asserts on what the CLI would run, via --dryrun, with no container started. Use for flag handling, config precedence, env expansion, docker-arg assembly, name/port resolution. Fast and image-free, so prefer it over test-add-basic whenever the behaviour is visible in the printed command.
---

# Add a dryrun test

`$ARGUMENTS` is the behaviour to cover. Dryrun tests assert on **what the CLI would run** — the
assembled docker command and the resolved settings — without starting anything.

**Prefer this suite.** It runs in seconds and needs no image. If the behaviour shows up in the
printed command or the resolved values, it belongs here rather than in `test-add-basic`. Reach for
a real booth only when the assertion is about what happens *inside* the container.

## 1. Name and place it

`tests/dryrun/testNNN--what-it-checks.sh`, executable. Discovery is `for f in test0*.sh`, so the
`test0` prefix is required or the file is silently never run.

The runner also descends one level into subdirectories and runs `test0*.sh` there. Existing
subdirectories hold tests that need a fixture project alongside them:

```
tests/dryrun/boothfile-test/  init-go-test/  init-multi-test/  dind/
```

Add a subdirectory only when your test needs its own project fixture; otherwise put the file at the
top level.

## 2. The skeleton

```bash
#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -euo pipefail

source ../common--source.sh

VERSION="$(get_booth_version)"
```

Config-file cases write a throwaway toml next to the test and clean it up:

```bash
cat > test--thing-config.toml <<EOF
dryrun = true
verbose = true
name = "\${SOME_VAR}"
EOF
```

## 3. Assert by diffing normalized output

The house pattern is an exact `diff -u` of expectation against actual, both passed through
`normalize_output`:

```bash
ACTUAL=$(run_coding_booth --config test--thing-config.toml | grep -E '^CONTAINER_NAME:')
EXPECT="CONTAINER_NAME: dryrun"

if diff -u <(echo "$EXPECT" | normalize_output) <(echo "$ACTUAL" | normalize_output); then
  print_test_result "true"  "$0" "1" "Unset env var expands to empty (falls back to default)"
else
  print_test_result "false" "$0" "1" "Unset env var expands to empty (falls back to default)"
  echo "Expected:"; echo "$EXPECT"
  echo "Actual:";   echo "$ACTUAL"
  exit 1
fi
```

**`normalize_output` is not optional.** It rewrites the parts that legitimately differ per machine
and per platform — `HOST_UID`/`HOST_GID` to `XXXXX`, `BOOTH_HOST_IP`, the `cb.created-at` label,
Windows backslashes and `/c/` drive paths, `workspace.exe`. Comparing raw output means a test that
passes only on the machine that wrote it.

**`grep` the line you care about.** Diffing the whole dryrun dump makes the test fail on every
unrelated change to the command; narrow to the field under test.

## 4. Run it

```bash
cd tests/dryrun && ./testNNN--your-test.sh
cd tests/dryrun && ./run-dryrun-tests.sh
```

Fast enough that there is no excuse for not running the whole suite.

## Shared rules

`tests/README.md` carries the rules every suite shares — port picking, the two `set -euo pipefail`
traps that silently skip a case (a failing `$( )` assignment is easy to hit here, since `grep` exits
1 when it matches nothing), cleanup traps, and why you must not edit a test while a suite is
running.
