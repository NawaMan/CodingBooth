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

## The Go suite runs on every host booth runs on

`unit/` is the one suite that runs on Linux, macOS **and** Windows, because the CLI it tests is
installed on all three. Two helpers in `cli/src/internal/` are what keep it that way; read their
package comments before writing a test that reaches outside its own process.

**A fake engine is a copy of the test binary, not a shell script** —
`cli/src/internal/fakebin`. `exec.LookPath("docker")` on Windows only considers the extensions in
`PATHEXT`, so an extensionless file with `#!/bin/sh` on the first line is not an executable there
and the engine is simply never found: a test that installed one exercised the "no engine installed"
path instead of the one it named, and the cases whose expectation happened to be the fallback
passed while proving nothing. A stub installed by `fakebin` is a hard link to the running test
binary, which re-enters its own `TestMain`, where `fakebin.Serve` hands it to the package's handler:

```go
func TestMain(m *testing.M) {
    fakebin.Serve(fakeEngineMain)   // returns at once in the test process
    os.Exit(m.Run())
}
```

What the stub answers belongs to the package that installs it, driven by whatever the test put in
the environment. Nothing is interpreted by a shell on the way, so the handler sees exactly the
arguments the CLI passed — which a `cmd.exe` shim forwarding to `sh` cannot promise: it eats the
braces in `--format {{.Names}}`.

**Skip what a host does not have, by name** — `cli/src/internal/hostskip`. `hostskip.NoUnixModes`,
`NoUnixPaths` and `NoSymlinks` skip a test whose *subject* only exists on a Unix host: a permission
bit (Windows has none — `os.Chmod` toggles one read-only flag and `Stat` reports 0666 or 0777
whatever was asked), `/etc` and `/dev`, a symlink this host will not create. Where only one
assertion needs it, keep the rest of the test running:

```go
if hostskip.UnixModes() {
    // the mode assertion only
}
```

Reach for one only when the behaviour cannot exist there. A test that merely *expects* a Unix
answer — a `/`-joined path, a host-native separator — belongs on every platform, with the
expectation written so it holds on each (`filepath.Join`, `filepath.FromSlash`).

## Picking the booth to run

Never resolve the binary inline. `booth-bin--source.sh` does it, `common--source.sh` already sources
it, and an example test sources it directly:

```bash
source "$REPO_ROOT/tests/booth-bin--source.sh"
BOOTH="$(resolve_booth_bin)"                         # local build, else the booth wrapper
BOOTH_BIN="$(find_local_booth_build)" || exit 1      # the local build or nothing
```

**Why not `[ -x "$REPO_ROOT/codingbooth" ]`.** That was the old line, in 118 scripts, and on Windows
it is always false: `cli-build.sh` writes the host build to `codingbooth.exe` there, and the
extensionless `codingbooth` beside it is the Linux cross-build, which the host cannot execute. Every
one of those tests fell through to the wrapper without saying so — and the wrapper runs a *release*
binary, whose version picks the base image tag. A 0.77.0 wrapper builds
`FROM nawaman/codingbooth:base-0.77.0` against a 0.78.0 tree, so a setup added after 0.77.0 is
simply missing, and the test fails somewhere far from the cause.

Use `find_local_booth_build` when only the real CLI will do — reading `version`, or a subcommand a
given release may not have. Use `resolve_booth_bin` otherwise. The walk stops at the checkout root,
so a linked worktree never silently runs the main clone's binary.

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

## `command -v python3` is not "python3 works"

Ask `have_python3` from `common--source.sh`, never `command -v python3`:

```bash
have_python3 || { echo "SKIP: needs python3"; exit 0; }
```

A stock Windows PATH carries the App Execution Aliases in
`%LOCALAPPDATA%\Microsoft\WindowsApps` — stubs named `python3` and `python` whose only job is to
send whoever runs them to the Microsoft Store:

```
$ python3 -c 'print(1)'
Python was not found; run without arguments to install from the Microsoft Store, ...
$ echo $?
49
```

`command -v` finds that. Every caller that only asked whether python3 *exists* took the python3
branch and watched it fail: `port_is_bindable` read exit 49 as "that port is taken" — for all 100
candidates — so `pick_free_port` gave up on a host with twelve thousand free ports, and every
port-publishing test in `basic/` went down with it. `have_python3` runs `python3 -c ''` once and
caches the answer.

## What the host can and cannot do

The rest of `common--source.sh`'s host helpers, for the same reason: a test that assumes the host
is the one it was written on fails there for a reason that has nothing to do with booth. Each has
the full story in its own comment.

| Helper | Use it for | What it saves you from |
|--------|-----------|------------------------|
| `booth_script_name` | the name booth calls itself by in its output (`BOOTH_SCRIPT_NAME`, the "open a shell instead" hint) | the literal `codingbooth`, which is `codingbooth.exe` on Windows |
| `host_path <dir>` | a `-v` source a test writes into a config | `/tmp/x` and `/c/Users/x`, which Windows cannot resolve, so booth drops the mount |
| `stub_path <dir>…` | the PATH for a setup script run against stubbed tools | an MSYS tool that cannot load `msys-2.0.dll` because PATH no longer holds `/usr/bin` |
| `occupy_port <port> [s]` | holding a port open for an "already in use" case | an inline `python3` listener that never started; it returns at once, so poll until the port answers |
| `unix_modes` | a case about `0600` or the exec bit | a mode read back as `0644` on a host that has no modes |
| `have_symlinks` | a case about what a script does *at* a symlink | `ln -s` copying the file instead, which proves the opposite |
| `is_link_or_copy <path>` | asserting a script put its link there | `-L` being false for the copy `ln -s` left |
| `utf8_locale` | the one command that needs a UTF-8 locale (`grep -oP` in a product script) | a script dying on its version probe where the shell has no locale |

**Do not set a UTF-8 `LANG` for a whole run on Windows.** It looks like a fix — GNU grep refuses
`-P` without a unibyte or UTF-8 locale, so `tests/setups/test--pg-ext-install` needs one for the
script it runs — but MSYS grep *in* a UTF-8 locale cannot match a character outside the BMP. Set
one, and `dryrun/test031`'s `grep '📦 Running booth in daemon mode'` stops matching a line that is
right there in the output, while every ASCII pattern keeps working. `utf8_locale` exists so the one
command that needs it gets it, and nothing else does.

Two more things the shell does to a *container* path on Windows, both handled in
`common--source.sh` so no test has to think about them: `docker exec` and `docker run` go through a
wrapper that sets `MSYS_NO_PATHCONV=1` (without it, `docker exec … cat /home/coder/code/f` asks for
`C:/Program Files/Git/home/coder/code/f`), and `run_coding_booth` excludes the booth's own roots
from argument rewriting (`-- ls /usr/local/bin/x` reached the container as a Windows path). `/tmp`
is excluded from that list on purpose — it is a host path *and* a booth path — so a test that means
the booth's `/tmp` says so itself, per command: `MSYS2_ARG_CONV_EXCL='/tmp' run_booth exec … --dir /tmp`.

A missing host *tool* is different: say so and skip the case, as `tests/setups` does for `jq`,
`node` and `zip`. A skip names what is missing; a silent pass does not.

```bash
if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed on this host, and <script> parses its body with it"
  exit 0
fi
```

## Running a booth with no controlling terminal

A test that needs booth to find no terminal must take the runner from `common--source.sh`. Never
call `setsid` directly — it is util-linux, macOS does not have it, and the failure is quiet.

```bash
no_tty_supported || exit 0                   # once, near the top; prints SKIP: and skips
OUTPUT=$(no_tty_run "$BOOTH" --name x -- echo hi) || STATUS=$?
```

`no_tty_run` puts the command in a session of its own: `setsid -w` where it exists, otherwise the
same fork + `setsid(2)` + exec through `python3` or `perl`, which macOS ships. All three wait for
the child, exit with its status, and leave stdout/stderr on the caller's fds so `$( )` still
captures them. The fork matters — `setsid(2)` returns `EPERM` for a process that already leads its
group, and a freshly forked child never does.

**Why not redirect stdin.** The consent prompt is written to `/dev/tty`, not stdout, so it still
works under `booth shell --run`. `</dev/null` therefore proves nothing; the terminal itself has to
be gone, which means a new session.

**Why this is a shared helper.** `basic/test029` called `setsid` inline. On macOS every case died
with `setsid: command not found` — and the weakest of them *passed* on it, because "non-zero exit
and no container" is satisfied just as well by a missing binary as by booth refusing. A test that
asserts a refusal must assert on the refusal's own text, or a broken harness reads as green.

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

## Versions are catalog data, not test data

A test checks a version only when **pinning is the behaviour under test** — a `--select x:<ver>`
or `setup x <ver>` that must come out as asked, an `install` pin, the wrapper's version switch.
Everywhere else a version is data the next catalog bump changes, and a test that spells it out
breaks on the bump without having tested anything:

- **A default:** compare against the catalog, never a copied literal —
  `assert-line "$boothfile" "arg X_VERSION=" "$(template-default x X_VERSION)" …`
  (`tests/config/test-helpers--source.sh`).
- **"It is installed":** check that it runs (`clang version [0-9]+`, `Python 3\.`), not which
  release it is. A path with a version in it (`/opt/venvs/py3.14/`) is normalised before compare.
- **A fixture:** `setup x`, not `setup x 1.2.3`, so the test exercises what users get by default.
  A pin that has to stay — the test is about pinning, or the tool needs a particular version —
  carries a one-line Boothfile comment saying which. A pin test picks a version that is *not* the
  default, so it proves the pin was honoured.

A version bump is then the template plus the setup script, and nothing under `tests/`.

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

Each suite runner already retries a failing test once. On top of that, `run-automate-tests.sh` gives
a failed suite one more attempt — for `complex/`, only the tests that failed rather than all ~160.
The first attempt is kept, not overwritten: `tests/logs/<suite>.attempt1.log`, plus
`complex-booth-calls.attempt1.log` for its trace. The final summary lists every test that passed
only after a retry and names the log holding its failure. Read that log before calling it a flake.

At the end of a run on Docker, `run-automate-tests.sh` prunes dangling images labelled
`cb.managed=true`. These are copies that a test rebuild or variant refresh replaced. Left alone
they fill the disk, and BuildKit's GC then evicts build cache, so the next run rebuilds every
desktop image. Set `CB_NO_IMAGE_PRUNE=1` to keep them.
