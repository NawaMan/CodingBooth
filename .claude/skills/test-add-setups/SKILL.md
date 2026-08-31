---
name: test-add-setups
description: Add a test under tests/setups/ — runs a real setup or install script on the host with its tools stubbed, and asserts on the command line it emits. Use when changing variants/base/setups/* and you need to lock in what the script does, including how it fails. No container, no image.
---

# Add a setups test

`$ARGUMENTS` is the setup script behaviour to cover. These tests run the **real script** from
`variants/base/setups/` on the host, with the tools it calls replaced by stubs, and assert on the
command line it would have run.

**What this suite is good at.** Argument handling (comma-separated ids, `@version` suffixes,
defaults), and — the part worth the most — **what the script does when something goes wrong**. A
setup that logs a warning and carries on versus one that must fail the build is exactly the kind of
distinction that regresses silently.

Whether the tool actually installs belongs elsewhere: a targeted `test-add-basic` booth, or a real
image build.

## 1. Name and place it

`tests/setups/test--<script-name>.sh`, executable. Discovery is `for f in test--*.sh` — note the
**double dash and no number**, unlike `basic/` and `dryrun/`.

## 2. Stub the tools

The pattern is a temp directory of fake executables, put at the front of `PATH`:

```bash
STUB=$(mktemp -d)
trap "rm -rf $STUB" EXIT
mkdir -p "$STUB/bin" "$STUB/empty"

cat > "$STUB/bin/code" <<'EOF'
#!/bin/bash
echo "code $*" >> "$STUB_LOG"
EOF
chmod +x "$STUB/bin/code"
```

Then run the real script against it:

```bash
OUTPUT=$(PATH="$STUB/bin:$PATH" STUB_LOG="$LOG" \
  "$REPO/variants/base/setups/code-extension--install.sh" ms-python.python 2>&1) || true
```

`$STUB/empty` — a PATH of `"$STUB/empty:/usr/bin:/bin"` — is how the existing tests cover "the tool
isn't installed", which is usually a distinct branch worth its own case.

## 3. Getting past the root guard

Setup scripts open with `[[ $EUID -eq 0 ]] || exit`, because inside a booth they run as root and
hand the real work to `sudo -u coder`. A test on the host is not root and does not need to be —
nothing privileged is ever attempted, since `sudo` and the tool are both stubbed.

`common--source.sh` documents the way through: bash takes `EUID` from the environment when one is
present, so

```bash
env EUID=0 "$SCRIPT" ...
```

satisfies the guard with no privilege at all. This replaced `fakeroot`, which macOS does not have —
so every one of these tests used to skip on a Mac while the suite still reported green.

## 4. Assert on the emitted command line

The stub log *is* the assertion surface. Check the shape of what was called, not just that
something was:

```bash
if grep -q "code --install-extension ms-python.python@2024.1" "$LOG"; then
  print_test_result "true"  "$0" "2" "A trailing @version is passed through to the installer"
else
  print_test_result "false" "$0" "2" "Expected the @version to be passed through; log: $(cat "$LOG")"
  exit 1
fi
```

Cover the failure branch explicitly — assert that a bad id makes the script **exit non-zero**, not
merely that it printed something.

## 5. Run it

```bash
cd tests/setups && ./test--your-script.sh
cd tests/setups && ./run-setups-tests.sh
```

Fast — no container, no image. Run the whole suite.

## Shared rules

`tests/README.md` carries the rules every suite shares — the two `set -euo pipefail` traps that
silently skip a case (`grep` exiting 1 on no match bites constantly here), cleanup traps, and why
you must not edit a test while a suite is running. For changing the setup script itself rather than
testing it, see the `setup-work` skill.
