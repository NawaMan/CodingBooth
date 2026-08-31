# Tests

This directory holds every automated test for CodingBooth. They are not one suite but several, each
with its own runner, its own helper library, and its own idea of what an assertion looks like — so
the first question when writing a test is which suite it belongs in.

Run everything with `./tests/run-automate-tests.sh`, or a single suite with its own runner. All
runners must be run from their own directory.

## The suites

| Suite | Runner | What a test here does | Helpers |
|-------|--------|-----------------------|---------|
| `unit/` | `run-all-go-tests.sh` | delegates to `go test ./...` in `cli/` | Go's own |
| `basic/` | `run-basic-tests.sh` | starts a real booth and asserts on the container | `common--source.sh` |
| `complex/` | `run-complex-tests.sh` | multi-step booth lifecycles, one directory per scenario | `common--source.sh` |
| `dryrun/` | `run-dryrun-tests.sh` | compares `--dryrun` output against a normalized expectation; no container | `common--source.sh` |
| `boothfile/` | `run-boothfile-tests.sh` | asserts on `emit-dockerfile` output for a temp Boothfile; no container | `common--source.sh` |
| `setups/` | `run-setups-tests.sh` | runs a setup script on the host with its tools stubbed | `common--source.sh` |
| `config/` | `run-all-tests.sh` | `booth config` / `booth init` behaviour | `config/test-helpers--source.sh` |
| `config-tui/` | `run-all-tests.sh` | drives the config TUI with scripted keystrokes (needs `vhs`, `ttyd`, `ffmpeg`) | `config-tui/tui-helpers--source.sh` |
| `wrapper/` | `run-all.sh` | the `booth` wrapper script, exercised inside a container | `wrapper/_lib.sh` |

Three different helper libraries means three different vocabularies. `common--source.sh` suites
report with `print_test_result`; `config/` and `config-tui/` open with `begin` and use
`assert-file-contains` / `skip`; `wrapper/` uses `run_in_container` with `assert_not_contains`.
Match the suite you are in rather than importing a habit from another one.

## Picking a port

Any test that publishes a port must take it from `common--source.sh`. Never write a picker inline —
every test here used to have its own, and all of them were wrong in the same two ways.

```bash
PORT="$(pick_free_port)"                             # one port
PORT="$(pick_free_port 300)"                         # PORT and PORT+300 both bindable
BASE="$(pick_free_port 1000 2000)"                   # room for a scan to advance into
OTHER="$(pick_free_port_other_than "$PORT")"         # a second, guaranteed different
```

**Why not just check whether something is listening.** The old pickers asked
`lsof -iTCP:$p -sTCP:LISTEN`, which answers "is a server accepting connections here" — not the
question docker is about to ask. Every outbound connection on the host is assigned an ephemeral
port, and one sitting in `ESTABLISHED` or `TIME_WAIT` holds that port while never being in `LISTEN`
state. `basic/test003` lost a run to exactly that:

```
failed to bind host port 127.0.0.1:39386/tcp: address already in use
```

on a port its own check had just called free. `pick_free_port` fixes both halves: candidates come
from **below** the ephemeral floor (read from `/proc/sys/net/ipv4/ip_local_port_range`, or
`net.inet.ip.portrange.first` on macOS), so the kernel will never hand one out on its own; and a
candidate is confirmed by **binding** it, which is the same question docker asks.

**Two ports are not automatically two different ports.** Picking a port does not reserve it, so two
calls to `pick_free_port` can return the same number. Say what you mean with
`pick_free_port_other_than`. What breaks otherwise depends on the test — two booths racing for one
port, one container asked to publish the same host port twice, or a case that passes while proving
nothing because the "other" port was the same one.

## `set -euo pipefail` will eat your test

Every suite runs under it, and it silently skips cases rather than failing loudly. Both of these
were found in this repo's own tests, each having hidden a case that never ran while the suite
still reported green:

**A bare test as the last line of a loop body ends the script, not the iteration.**

```bash
# Wrong — the first non-matching poll exits the whole test
[[ "$INSTANCE" =~ ^[0-9a-f]{16,}$ ]] && break

# Right
if [[ "$INSTANCE" =~ ^[0-9a-f]{16,}$ ]]; then
  break
fi
```

**A failing pipeline inside `$( )` fails the assignment, and `set -e` acts on it.** `curl` exits 56
when a port is not listening yet, `grep` exits 1 when it matches nothing — both are states a test is
often there to observe:

```bash
# Wrong — exits the test on the polling attempt that was supposed to fail
VALUE=$(curl -s ... | grep -o '...')

# Right
VALUE=$(curl -s ... | grep -o '...' || true)
```

## Writing a new test

1. **Pick the suite** from the table above. If it starts a container it is `basic/` (one booth) or
   `complex/` (a lifecycle, in its own directory); if it only reads command output, prefer
   `dryrun/` or `boothfile/`, which run in seconds and need no image.
2. **Name it** the way its neighbours are named — `basic/` and `dryrun/` use
   `testNNN--what-it-checks.sh`, `complex/` uses `test-<scenario>/test--<scenario>.sh`, `wrapper/`
   uses `NNN-what-it-checks.sh`.
3. **Source the suite's helper** and use its assertion vocabulary.
4. **Clean up in a trap**, not at the end — a test that exits early on failure still has to remove
   its containers and temp directories:
   ```bash
   cleanup() { docker rm -f "$NAME" >/dev/null 2>&1 || true; rm -rf "$WORK"; }
   trap cleanup EXIT
   ```
5. **Number the cases** in the order they run, and give each a description that names the behaviour
   rather than the mechanism — the line is what someone reads when it fails.
6. **Run it more than once** before believing it. Anything involving ports, container startup, or
   polling is a race until it has survived a few runs.

## Gating an expensive test

A test too slow to run every time is gated **opt-out, not opt-in**: it runs wherever the environment
can afford it, and the places that cannot are named. A test nobody ever turns on is a test nobody
notices rotting — and the expensive ones tend to be the ones covering claims nothing else can see.

`android_emulator_test_enabled` in `common--source.sh` is the worked example:

| `CB_ANDROID_EMULATOR_TEST` | under CI | usable `/dev/kvm` | result |
|---|---|---|---|
| `1` / `true` / `yes` / `on` | any | any | runs — an explicit yes wins over everything |
| `0` / `false` / `no` / `off` | any | any | skips — an explicit no |
| unset | yes | any | skips — CI |
| unset | no | yes | **runs** |
| unset | no | no | skips — too slow to be worth it here |

Two things to copy from it. **Check the capability, not a proxy for it** — `/dev/kvm` is
`root:kvm`, so a user outside that group sees the node and still cannot open it; the probe tests
`-r` and `-w`, not just existence. And **check `CI` in the test rather than setting a variable in a
workflow**, so a suite added to CI later is off by default instead of discovering the cost the hard
way.

Print the reason on every skip. `SKIP:` at the start of a line is what the runner counts, and a skip
without a reason is indistinguishable from a test that quietly stopped covering anything.

## Editing a test while a suite is running

Don't. Bash reads a script incrementally as it executes, so editing a file mid-run corrupts the
part it has not reached yet — it will report a failure that has nothing to do with your change. Let
the suite finish, or run the single test on its own.

## Diagnostics

The complex suite traces every booth call — command, exit code, stderr — to
`tests/logs/complex-booth-calls.log`, because the tests themselves discard stderr. Set
`CB_DIAG_LOG=<path>` to trace any suite, or `CB_DIAG_LOG=/dev/null` to opt out.
