---
name: test-add-boothfile
description: Add a test under tests/boothfile/ — asserts on the Dockerfile that a Boothfile emits, via booth emit-dockerfile, with no image built. Use for Boothfile syntax, setup resolution, directive ordering, warnings and errors. For behaviour of the built image use test-add-basic or test-add-setups.
---

# Add a boothfile test

`$ARGUMENTS` is the behaviour to cover. These tests write a `.booth/Boothfile`, run
`booth emit-dockerfile`, and assert on what comes out — **no image is built**.

**Scope.** This suite is about the *translation*: does a directive produce the right Dockerfile
lines, in the right order, and does a bad one produce a useful message. Whether the resulting image
actually works is a different question — that is `test-add-basic` (does the booth run) or
`test-add-setups` (does the setup script do the right thing).

## 1. Name and place it

`tests/boothfile/testNNN--what-it-checks.sh`, executable. Discovery is `for f in test0*.sh` — the
`test0` prefix is required or the file is silently never run.

## 2. The skeleton

```bash
#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Test: <what the Boothfile says, and what the Dockerfile must therefore say>

set -euo pipefail

source ../common--source.sh

TEST_DIR=$(mktemp -d)
trap "rm -rf $TEST_DIR" EXIT

mkdir -p "$TEST_DIR/.booth"
cat > "$TEST_DIR/.booth/Boothfile" << 'EOF'
# syntax=codingbooth/boothfile:1
setup python
EOF

OUTPUT=$(run_coding_booth emit-dockerfile --code "$TEST_DIR" 2>&1) || true
```

Two details that matter:

- **`# syntax=codingbooth/boothfile:1` on the first line.** A Boothfile without it is not parsed as
  one, and the test ends up asserting on the wrong failure.
- **`2>&1` and `|| true`.** Warning and error cases are the interesting half of this suite, and a
  non-zero exit under `set -e` would end the test before it could assert on the message.

## 3. Assert on the emitted text

Accumulate rather than exiting at the first failure — one run of `emit-dockerfile` can answer
several questions, and seeing all of them at once is worth more than the first:

```bash
ALL_PASSED=true

if echo "$OUTPUT" | grep -q "python--setup.sh"; then
  print_test_result "true"  "$0" "1" "A 'setup python' directive emits the python setup"
else
  print_test_result "false" "$0" "1" "A 'setup python' directive should emit python--setup.sh"
  ALL_PASSED=false
fi

[[ "$ALL_PASSED" == true ]] || exit 1
```

For a misspelled setup, assert on **both** halves of the message — that it warns, and that it
suggests the right name. A warning that names nothing is not the behaviour worth locking in.

## 4. Run it

```bash
cd tests/boothfile && ./testNNN--your-test.sh
cd tests/boothfile && ./run-boothfile-tests.sh
```

No containers, no images — run the whole suite.

## Shared rules

`tests/README.md` carries the rules every suite shares — the two `set -euo pipefail` traps that
silently skip a case (very easy to hit here: `grep` exits 1 when it matches nothing, and a bare test
as the last line of a loop body ends the script), cleanup traps, and why you must not edit a test
while a suite is running.
