# booth record

Keep a record of what is done in a booth: the commands typed, what the terminal showed, how
the files changed, which ports were opened. Made for the case where someone else works in
the booth and you want to see how they went about it afterwards — an interview, a class, a
pairing session, a support call.

```bash
./booth --record                 # start a recorded booth
./booth logs activity            # read the session, during or after
```

> **Experimental.** The file layout and event names below may still change.

---

## Table of Contents

- [Turning It On](#turning-it-on)
- [What Is Kept](#what-is-kept)
  - [The activity log](#the-activity-log)
  - [File snapshots](#file-snapshots)
  - [Terminal recordings](#terminal-recordings)
- [Reading a Session](#reading-a-session)
- [Inside the Booth](#inside-the-booth)
- [What It Does Not See](#what-it-does-not-see)
- [It Is Not Tamper-Proof](#it-is-not-tamper-proof)
- [Tell the Person](#tell-the-person)
- [Settings](#settings)
- [Decisions](#decisions)
- [Not Done Yet](#not-done-yet)

---

## Turning It On

Any one of:

```bash
./booth --record
CB_RECORD=true ./booth
```

```toml
# .booth/config.toml
record = true
```

It works with every variant and run mode. The code folder needs a `.booth/` folder (the
session is kept inside it); without one the CLI warns and records nothing.

Recording is decided when the container is created. A kept booth that was created without
`--record` is not recorded by starting it again with the flag: remove it and run it again.

## What Is Kept

Everything is in `.booth/.tmp/record/` in the code folder, **on the host**, so it is still
there after the booth is stopped or removed:

```
.booth/.tmp/record/
├── activity.log        one line per event
├── snapshots.git/      a git repository of the code folder, over time
└── terminal/
    └── s1-w0p0-20261116-101502.cast     one asciicast per terminal pane
```

`.booth/.tmp/` is already gitignored. Unlike the rest of it, `record/` is **not** emptied
when a booth starts or exits. A second recorded session in the same folder adds to the same
files; to start clean, move or delete the folder first.

### The activity log

One line per event, in the [lifecycle log](BOOTH_LIFECYCLE.md#the-lifecycle-log)'s format:
time, booth name, event, details.

```
2026-11-16T10:15:01+0000 interview started version=0.83.0 variant=base mode=DAEMON port=10000
2026-11-16T10:15:01+0000 interview record-started parts=commands,ports,snapshots,terminal snapshot-every=30s
2026-11-16T10:15:01+0000 interview ports-baseline listening=10000(nginx),10001(ttyd),10002(ttyd)
2026-11-16T10:15:02+0000 interview snapshot commit=1f0c2aa baseline files=12
2026-11-16T10:15:03+0000 interview terminal-recording pane=s1:0.0 file=terminal/s1-w0p0-20261116-101503.cast
2026-11-16T10:16:40+0000 interview cmd shell=bash pid=412 cwd=/home/coder/code -- npm test
2026-11-16T10:16:52+0000 interview cmd-done pid=412 exit=1 secs=12
2026-11-16T10:17:31+0000 interview snapshot commit=8be41d0 changed: 1 file changed, 4 insertions(+), 1 deletion(-) files=src/cart.js
2026-11-16T10:18:05+0000 interview cmd shell=bash pid=412 cwd=/home/coder/code -- node server.js &
2026-11-16T10:18:07+0000 interview port-listen port=3000 bind=any pid=655 proc=node cmd=node server.js
2026-11-16T10:18:20+0000 interview expose-opened container=3000 host=13000
2026-11-16T10:41:10+0000 interview port-closed port=3000 proc=node
2026-11-16T10:45:00+0000 interview stop-requested by=host-cli force=false
```

| Event | Written when |
| --- | --- |
| `record-started`, `record-stopped` | the recorder starts (every boot of the booth) or is told to stop |
| `cmd` | a command is entered at a bash or zsh prompt, **before** it runs: the shell, its pid, the folder, then the command line after `--` |
| `cmd-done` | that command returns: its exit status and how long it took. Match it to its `cmd` by `pid` |
| `ports-baseline` | once at start: the ports already listening (the booth's own UI and services) |
| `port-listen` | a TCP port starts listening: the port, whether it is bound to every interface (`any`) or loopback (`local`), and the process behind it. This is how a server started by hand, by a script, or by an autostart service shows up |
| `port-closed` | that port stops listening: the server stopped or crashed. When the booth itself stops, its own services close too, and say so here |
| `expose-opened`, `expose-closed` | [`booth--expose`](BOOTH_EXPOSE.md) opens or closes a tunnel to the host |
| `snapshot` | files changed since the last look and were committed to `snapshots.git`: the commit, the size of the change, the first five file names |
| `snapshot-skipped` | a new file was left out of the snapshots for being too large |
| `terminal-recording` | a terminal pane started being recorded, and to which file |
| everything in the [lifecycle log](BOOTH_LIFECYCLE.md#the-lifecycle-log) | `started`, `shutdown`, `stop-requested`, `idle-*`, `exited`, … are copied here, so this one file tells the whole session |

### File snapshots

`snapshots.git` is a git repository whose working tree is the code folder. Every 30 seconds,
if anything changed, the recorder commits the whole folder to it. The result is the history
of the solution as it was written, including the false starts that never reach the person's
own commits.

It is separate from the project's own repository: it has its own git directory, so the
project's `.git`, index, branches and history are never touched, and the person's `git
status` shows nothing of it. The project's `.gitignore` still applies, so `node_modules/`
and build output stay out. Also left out: `.booth/.tmp/`, `.booth/cache/`, `.booth/tools/`,
and any new file over 2 MB.

### Terminal recordings

Every pane of the [Console UI](BOOTH_CONSOLE.md) (and any other tmux pane) is recorded to an
[asciicast v2](https://docs.asciinema.org/manual/asciicast/v2/) file: what was printed, with
timing, colours and cursor movement, so it replays exactly as it looked — including what was
typed into an editor or a REPL, which the command log cannot see.

Only **output** is recorded, never keystrokes. A password typed at a prompt that does not
echo is not in the file.

## Reading a Session

```bash
# The timeline
./booth logs activity
./booth logs activity -f                 # follow a running session
./booth logs activity | grep ' cmd '     # only the commands
./booth logs --code ~/interviews/alice activity     # a booth that is long gone

# The files, over time
git --git-dir=.booth/.tmp/record/snapshots.git log --stat
git --git-dir=.booth/.tmp/record/snapshots.git log -p -- src/cart.js
git --git-dir=.booth/.tmp/record/snapshots.git show 8be41d0
git --git-dir=.booth/.tmp/record/snapshots.git diff 1f0c2aa HEAD      # start to end

# The terminal
asciinema play .booth/.tmp/record/terminal/s1-w0p0-20261116-101503.cast
asciinema play -i 2 <file>               # cap idle gaps at 2 seconds
```

`asciinema` is not part of CodingBooth; install it on the host (`apt install asciinema`,
`brew install asciinema`) or drop the file on any asciicast web player. The file is plain
JSON lines, so `jq -r 'select(type=="array") | .[2]' <file>` prints the raw text too.

To keep a session, copy `.booth/.tmp/record/` somewhere else. It is a plain folder.

## Inside the Booth

```bash
booth--record status      # is this booth recorded, is the recorder running, what is there
```

`booth--record event <name> [detail...]` appends a line of your own to the activity log (a
no-op in a booth that is not recorded), for a script that wants to mark a moment:
`booth--record event task-2-started`.

The recorder's own messages are in `/tmp/booth-record.log`: `./booth logs booth-record`.

## What It Does Not See

- **Commands that are not typed at a bash or zsh prompt.** fish, xonsh and nushell are not
  hooked. Commands run by a script, a Makefile, an IDE's Run button or task runner, or `booth
  exec` from the host do not appear as `cmd` lines. Their effects still show: file changes in
  the snapshots, servers in `port-listen`.
- **Terminals that are not tmux panes.** A VS Code / code-server terminal, a desktop terminal
  emulator, or `booth shell` gets its commands logged, but its screen is not recorded.
- **GUI activity.** On a desktop variant, nothing records the screen. What was clicked in a
  browser or an IDE is visible only through the files it changed.
- **A process that listens for less than two seconds**, files that changed and changed back
  within one 30-second window, UDP ports, and outgoing network traffic.
- **Nested git repositories** in the code folder: a snapshot notes that their commit moved,
  not what their files contain.

## It Is Not Tamper-Proof

The recorder runs inside the booth as `coder`, and writes to a folder `coder` can write to.
The person in the booth has `sudo` unless you take it away. They can stop the recorder,
edit the activity log, or delete a recording. The recorder restarts when a new shell opens
and re-attaches to a pane within two seconds, and `--no-sudo` raises the bar, but none of
that is a guarantee.

So read a recording as **an account of how someone worked**, not as proof that they did or
did not do something. For a setting where that distinction matters, see
[Not Done Yet](#not-done-yet).

## Tell the Person

Every interactive shell in a recorded booth opens with:

```
● This booth session is recorded: commands, terminal output, file changes and ports.
  Run booth--record status for what is kept and where.
```

`--hide-welcome` does not remove it. That is deliberate: recording someone who does not
know is, depending on where you are, somewhere between rude and unlawful. The notice covers
terminals only — on a code-server or desktop booth, a person who never opens a terminal
never sees it — so say it yourself as well, and get their agreement before the session.

## Settings

`--record` is one switch on purpose. The finer settings are environment variables read
inside the booth; pass them with `--env` or `.booth/.env`:

| Variable | Default | Meaning |
| --- | --- | --- |
| `BOOTH_RECORD_PARTS` | `ports,snapshots,terminal` | Which recorder parts run. Commands are always logged |
| `BOOTH_RECORD_SNAPSHOT_INTERVAL` | `30` | Seconds between looks for changed files |
| `BOOTH_RECORD_SNAPSHOT_MAX_FILE_KB` | `2048` | New files larger than this stay out of the snapshots |
| `BOOTH_RECORD_PORT_INTERVAL` | `2` | Seconds between looks at the listening ports |
| `BOOTH_RECORD_TERMINAL_INTERVAL` | `2` | Seconds between looks for new terminal panes |
| `BOOTH_RECORD_TERMINAL_MAX_MB` | `50` | A terminal recording stops growing at this size |

## Decisions

Why it is built this way. Each one was a choice between workable options.

1. **Insight, not evidence.** The goal is to understand how someone worked. Tamper-evidence
   needs capture from outside the container, which is a different feature with different
   costs (root on the host, kernel tracing). Doing the simple one first and saying plainly
   what it is not was preferred over a half-secure middle.
2. **In the base image, behind a run flag — not a template.** A template would make
   recording part of the booth's *definition* (the Boothfile, committed). Recording is a
   property of one *run*: the same booth is recorded for a candidate and not for the author.
   It mirrors `--idle-time`: CLI flag → environment variable → script in the base image.
3. **Kept in `.booth/.tmp/record/`.** `.booth/` is mounted read-only in the booth by
   default; `.booth/.tmp/` is the one part that is writable, already on the host, and
   already gitignored. Using it needed no new mount and no change to the generated
   `.gitignore` (which the wrapper script must match byte for byte). The cost is a
   deliverable living under a folder called `.tmp`; `record/` is exempted from the
   start/exit wipe the same way `lifecycle.log` is.
4. **One activity log, in the lifecycle log's format.** A second format would need a second
   reader. `booth logs activity` is the lifecycle reader pointed at another file. Lifecycle
   events are *copied* into it at write time rather than merged at read time: the booth and
   the host may be in different time zones, and a plain file that `grep` and `tail -f`
   work on beat a merge step.
5. **The host knows a booth is recorded by a marker file.** `booth stop` and `booth remove`
   are separate CLI runs that know nothing of `--record`. The recorder leaves
   `record/.recording`; the host copies its lifecycle lines into the activity log while that
   file is there, and clears it at the next start.
6. **`booth-entry` is not touched.** The recorder is started from `booth--lifecycle-log`,
   which `booth-entry` already calls with `started` on every boot — unlike the
   `/usr/share/startup.d` hooks, which run once per container and would miss a restart. A new
   shell also starts it if it is not running.
7. **Commands come from shell hooks, with a line at start and a line at end.** A command is
   logged *before* it runs (bash `PS0`, zsh `preexec`), so a server that never returns still
   appears; the end line carries exit status and duration. The alternative, the history file,
   has no times, no exit codes, is written when the shell exits, and is edited with any editor.
   In a recorded bash, `HISTCONTROL=ignorespace` and `HISTIGNORE` are switched off, because the
   hook reads the command from the history.
8. **Ports are polled from `/proc/net/tcp`.** The base image has no `ss`. Polling every two
   seconds catches servers however they were started, which answers "service start/stop"
   without a supervisor that booths do not have. The owning process is found once per new
   port, by socket inode.
9. **File history is a shadow git repository.** Git already solves "what changed, when, as a
   diff", respects the project's `.gitignore`, and every reviewer has the tool to read it.
   A separate git directory keeps it out of the person's way entirely. A timer was chosen
   over a file watcher: `inotifywait` is not in the image, and a 30-second grain is enough to
   follow someone's thinking.
10. **Terminal output through `tmux pipe-pane`, as asciicast.** Console UI panes are already
    tmux sessions, so nothing about how they start had to change. `script(1)` would have
    meant wrapping every pane's shell. asciicast is an open format with players everywhere;
    the writer is 90 lines of Perl because the base image has Perl and no Python.
11. **Output only, never keystrokes.** Keystrokes would capture passwords. Output shows what
    the person saw, which is what a reviewer wants.
12. **The notice cannot be switched off.** See [Tell the Person](#tell-the-person).
13. **No `BOOTH_RECORD` variable at all in a booth that is not recorded**, so existing
    booths, and the dry-run output tests pin, are unchanged.
14. **The activity log is never trimmed.** The lifecycle log is trimmed at 256 KB because it
    lives for the life of a folder. A recording is the thing you asked for; cutting its start
    off would be a bug. Terminal recordings are capped per file instead, which is where a
    runaway loop would do damage.

## Not Done Yet

- **Capture from the host**, for when tampering matters: `docker events`, process tracing
  with eBPF or auditd, and a record folder the booth cannot write to.
- **Screen recording** on the desktop variants.
- **fish, xonsh, nushell** command hooks; terminals of code-server and the desktops.
- **A viewer**: one page that plays the terminal next to the timeline and the diffs.
- **`booth record export`**: one archive of a session, for sending.
- **A notice in the web UIs** (the overlay), not only in terminals.
- **In `booth config`'s TUI**, `record` is under Session; it has no place in the web config yet.
