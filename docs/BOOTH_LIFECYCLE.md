# booth lifecycle

> Pause your work, resume it tomorrow — your container picks up right where you left off.

By default, CodingBooth containers are removed when they exit. With `--keep-alive`, the container is preserved after exit so you can resume it later with all state intact.

```bash
./booth --keep-alive --name myproject
# ... work, then exit ...
./booth start myproject          # resume where you left off
```

Back to [README](../README.md)

---

## Table of Contents

- [Overview](#overview)
- [Default vs Keep-Alive](#default-vs-keep-alive)
- [Lifecycle Commands](#lifecycle-commands)
- [Common Workflows](#common-workflows)
- [Persistence Rules](#persistence-rules)
- [Container Snapshots](#container-snapshots)

---

## Overview

CodingBooth provides a set of lifecycle commands for managing container state. These commands let you list running and stopped booths, resume stopped containers, restart running ones, and clean up when you are done.

All lifecycle features are built on top of Docker container management. CodingBooth labels every container it creates so lifecycle commands can reliably find and operate on the right containers.

---

## Default vs Keep-Alive

### Default (no keep-alive)

```
run → RUNNING → exit → REMOVED (automatic cleanup)
```

The container is created with `--rm`. Once it exits, everything inside (installed packages, modified files outside mounted volumes) is gone.

### Keep-alive mode

```
run --keep-alive → RUNNING → exit → STOPPED (preserved)
                                       ↓
                                   start → RUNNING (resumed)
                                       ↓
                                   stop → STOPPED
                                       ↓
                                   remove → REMOVED
```

The container persists after exit. You can resume it, restart it, or explicitly remove it when done.

Enable keep-alive via CLI flag or config:

```bash
./booth --keep-alive
```

Or in `.booth/config.toml`:

```toml
keep-alive = true
```

---

## Lifecycle Commands

All commands below accept `--engine docker|podman|apple`, which overrides config and
`CB_ENGINE`. Flags on start/stop/restart/remove may appear after the booth name too.

File transfers and native inspection commands (`cp`, `inspect`, `stats`, `top`,
`diff`, `wait`) are documented in [Booth tools](BOOTH_TOOLS.md).

> **Podman and Apple container (experimental):** when you have not chosen an engine and more than one of Docker, Podman and Apple container is installed, these commands look at all of them and act on the engine that owns the booth (`booth list` then shows an `ENGINE` column). Set `CB_ENGINE=docker`, `podman` or `apple` (or `engine =` in the `.booth/config.toml` that `--code` points to) to use just one. `booth shell` and `booth exec` find their booth the same way. See [Container Engine](BOOTH_RUN.md#container-engine-experimental).

### `list`

Show all booth-managed containers.

```bash
./booth list              # all booths
./booth list --running    # only running
./booth list --stopped    # only stopped
./booth list --json       # structured array; [] if empty
./booth list --name-only  # just container names
```

Output includes: name, status, variant, port, code path, daemon, keep-alive, and creation time.

### `dashboard`

A live, full-screen table of every booth — `booth list` you can act on. It refreshes every 2
seconds (`--interval 5s` to change that) and takes `--engine` like the other commands.

```bash
./booth dashboard
```

| Key | Does |
| --- | --- |
| `↑`/`↓` (`j`/`k`), `g`/`G` | Select a booth |
| `enter` | Open a shell in it (`booth shell`); exiting the shell comes back to the dashboard. On a stopped booth it asks, then starts it for the shell and stops it again afterwards (`booth shell --run`). On a worktree with no booth it asks, then starts a terminal (base) booth there for the shell and removes it afterwards (`booth shell --run --code <worktree>`); `s` starts the project's own booth instead |
| `i` | Show or hide its details below the table (see below) |
| `c` | Show or hide its project config in the same place (see below) |
| `l` | Show its whole log, following it while it runs: piped into `less +F` (`ctrl+c` pauses to scroll or search with `/`, `F` follows again, `q` comes back); without `less`, `booth logs -f`, which `ctrl+c` ends |
| `t` | Open a shell on the host (`$SHELL`) in its folder — the booth's code path, or the worktree; `exit` comes back to the dashboard |
| `o` | Open its page in the browser (`http://localhost:<port>`, `https` for a `--public` booth) |
| `p` | Pick one of its TCP ports — what `booth expose list` shows: front door, published ports, `booth--expose` tunnels — and open it (`enter`; `esc` goes back) |
| `m` | Send its user a message (`booth message send`): pick the type with `←`/`→` — toast, banner, a yes/no question, ok, or text — then type the title and body; `enter` on the body sends, `esc` cancels |
| `e` | Open its folder in your editor (`$VISUAL`, else `$EDITOR`, else `code`) |
| `K` | Open its folder in GitKraken |
| `s` | Start it, as `booth start` does: a daemon booth's start, and an interactive booth's session, take the terminal and come back to the dashboard. On a worktree with no booth: start one there (`booth --worktree <name> --daemon`) |
| `x` | Stop it |
| `r` | Restart it |
| `d` | Delete it and its home volume (`booth remove`, `--force` when it is running). On a gone booth: forget it. On a worktree with no booth: delete the worktree. It reads the worktree's git status first. A clean one is deleted with `booth worktree remove <name>`, which keeps a branch with commits found nowhere else. One with uncommitted files or unmerged commits, or whose status cannot be read, gets a warning in red that names what is lost and urges a last look (`t`, `e`, `K`); `y` force-deletes it with `booth worktree remove <name> --force --yes`, which discards that work, its branch and its booths' volumes |
| `n` | New worktree in the selected row's repository: type a name (the new branch, from the repository's current commit); booth creates it and starts its booth (`booth --worktree <name> --daemon`) |
| `h` | Hide it from the table; it stays hidden the next time the dashboard opens. Under `H`: show it again |
| `H` | Show only the hidden rows (the title says how many); `H` again goes back |
| `ctrl+↑`/`ctrl+↓` | Move its group (a repository with its worktrees, or a booth in no repository) up or down; on a linked worktree, move that worktree within its repository. The order is kept for the next time (see below) |
| `R` | Refresh now |
| `q` | Quit |

Starting takes the terminal, because booth may build an image, and asks before starting a booth
that could reach the host (`--dind`, `--privileged`, …); when a start fails, the dashboard waits for
Enter so its reason stays readable. Everything else runs in the background, with no terminal it
could read your keys from.

It shows every booth on the machine, including ones other sessions started, so stop, restart and
delete ask `[y/N]` first — and the question says when a stop also removes the container (a booth
that is not keep-alive). Each action runs the same `booth` command you would type, naming the booth
and its engine, so it behaves exactly as it does from the command line. An engine that cannot answer
shows as a warning line, and the rest of the table stays. `booth dashboard` needs a terminal; scripts use
`booth list --json`.

**Booths it has seen stay listed.** The dashboard remembers every booth it has shown, in
`~/.cache/codingbooth/dashboard/seen.json` (the user cache directory). When such a booth's container
is gone — removed by `d`, `booth remove`, or a `--run` that cleaned up after itself — it stays on its
row, under its repository and worktree, for as long as its folder and that folder's `.booth` are
still there (an express booth's own `.booth` folder). Its STATUS is `-none-`, the same as a worktree
with no booth: the folder is there and nothing runs. The title counts only booths with a container.
On a gone booth, `enter` asks, then starts a terminal (base) booth under its old name for a shell and
removes it afterwards (`booth shell --run --name <name> --code <folder>`); `d` asks, then forgets it
(the folder is not touched); `t`, `e` and `K` open its folder; keys that need a container say so. A
booth whose engine did not answer is not shown as gone, and `--engine` shows only that engine's.
Only booths the dashboard has seen are remembered; deleting the cache file forgets them all.

**Hiding rows.** `h` takes the selected row out of the table, and the title counts what is hidden
(`3 booths · 2 hidden`). A booth row hides that booth; a worktree row with no booth hides that
worktree, and a booth started on it later shows. Hiding the main checkout hides only its row; its
worktrees stay listed. `H` switches to the hidden rows, where every key works as usual and `h` shows
a row again; `H` again goes back. The hidden rows are kept in
`~/.cache/codingbooth/dashboard/hidden.json`; an entry is dropped once its folder is gone, and
forgetting a gone booth (`d`) unhides it too.

**Grouped by repository.** Booths are grouped by the git repository their code is in. A group has no heading line: its main checkout leads it, not indented, its NAME in
the group colour — the booth's name, or the repository's when it has no booth, with `(here)` on the
repository the dashboard runs in. Its linked worktrees follow, indented, each with its booths or as
a `-none-` row of its own (the WORKTREE column), so a worktree that has no booth yet is still one
key away from one. A repository that is only its main checkout is therefore a single row. A booth whose code is
in no repository leads a group of its own (blue, not indented). `d` on a worktree row removes it only when
nothing would be lost, as [`booth worktree remove`](BOOTH_WORKTREE.md#removing-a-worktree) does,
and refuses while a booth runs on it; the main checkout is never removed. There is no landing or
merging here: open the worktree in your editor or GitKraken for that.

**Ordering rows.** The first time, the groups are sorted by name (ignoring case: the repositories,
and the booths in no repository among them), and each repository's linked worktrees by name under
its main checkout. `ctrl+↑`/`ctrl+↓` moves the selected row's group past the next group shown; on a
linked worktree's row it moves that worktree within its repository (the main checkout always leads,
and the booths on a worktree move with it). Hidden rows keep their place. The order is kept in
`~/.cache/codingbooth/dashboard/order.json`; anything not in it yet — a new repository, booth or
worktree — goes to the bottom (of the table, or of its repository), and an entry is dropped once its
folder is gone. The cursor starts on the repository the dashboard runs in, wherever it is.

**GIT** is each worktree's status: `*3` files changed (uncommitted or untracked; booth's own
`.booth/.tmp/` is not counted), `↑2` commits ahead and `↓5` behind, or `clean`. A worktree counts
against the main checkout's branch, and shows `merged` once its branch has landed there: nothing
ahead, and it has had commits of its own (read from the branch's reflog, so a branch that never had
a commit shows only `↓n`). The main checkout counts against its upstream — unpushed (`↑`) and
unpulled (`↓`) commits — and shows only changed files when it has none. Nothing is fetched: it is
what this clone last saw. A worktree with changes is drawn in the warning colour. Git status is read
only for the rows on screen, a few at a time, and kept for 10 seconds; `R`, an action, or coming
back from a shell, terminal or editor reads it again.

**VERSION** is the CodingBooth version that built each booth. It turns the warning colour when the
booth has fallen behind what `booth` would build for it now:

- it was built with an older version than its project now uses (the project's
  `.booth/tools/codingbooth.lock`, else the dashboard's own version). Only the numbers count, so a
  `--rc1` or session suffix does not;
- or its image name now points to a newer build (the Boothfile or a setup changed since), which a
  kept booth does not pick up.

The details pane (`i`) says which, and how to update: `booth remove --force --name <booth>`, then
`booth` in its folder. The dashboard does not do this for you, since removing a booth also removes
its persisted home (`--persist-home`).

A toast or banner is sent at once. A question (yes/no, ok, text) waits for the booth user's answer
in the background: its row shows `?` meanwhile, every key stays usable, and the answer comes back
on the status line (`web answered: yes`, or `no answer (timed out)` after 10 minutes). Quitting the
dashboard stops waiting; the question stays on the booth's screen until it is answered or expires.

`i` opens a pane below the table about the selected booth, and it follows the cursor:

- how long it has been up (or since it stopped), and its CPU and memory (`booth stats`; not on
  engine `apple`)
- how many browser pages are viewing it, and its idle shutdown — off, paused until a time, or after
  how long — both asked of the booth's own message API from inside it, so a password-protected
  booth answers too
- its ports, as `p` lists them
- the messages its user has not answered yet
- its last log lines (`booth logs`), as many as fit

The pane reloads every 5 seconds, for the selected booth only. A part that cannot load says why,
and the others still show; a stopped booth shows only its stop time, messages and logs.

`c` shows, in the same place (it replaces the `i` pane, and `i` replaces it), the selected row's
project config: the select DSL its `.booth` was generated from, as the `# Configured by:` header of
its `Boothfile` (else its `config.toml`) records it — the selection `booth config` starts from —
one item (a template with its extensions) per line, as many as fit. It
reads the `.booth` the booth itself uses, or the worktree's own for a row with no booth, and
follows the cursor. A `.booth` with no such header was not written by `booth config`, so the pane
says so instead of showing a selection. `R` reads it again.

### `start`

Resume a stopped booth container.

```bash
./booth start myproject           # by name
./booth start --code ~/projects   # by code path
./booth start --daemon myproject  # resume in background
```

Target resolution priority:
1. `--name <name>`
2. Positional argument
3. `--code <path>`
4. Default booth name from current directory

A started booth is the same container as before, so it keeps the image it was **created** from.
If that image has been rebuilt since — you changed the Boothfile or a setup, and `booth` or
`booth build` rebuilt it — those changes are not in the booth, and `start` says so:

```
Warning: booth "myproject" was created from an older build of codingbooth-local:myproject-base; changes since (Boothfile, setups) are not in it.
         To use the current image: booth remove --force --name myproject, then run booth again.
```

`booth shell` / `booth exec` with `--run` warn the same way when they start a stopped booth.
Removing the booth deletes the container, and with it anything kept only inside it; files in
the project folder stay. `booth remove` also deletes the booth's `--persist-home` home volume —
export it first (`booth home-volume-export`) if you want to keep it.

### `stop`

Stop a running booth container.

```bash
./booth stop myproject              # graceful stop (10s timeout)
./booth stop --force myproject      # immediate kill
./booth stop --timeout 30 myproject # custom timeout
```

If the container was created **without** `--keep-alive`, stop also removes it automatically.

### `restart`

Restart a running booth in-place (same container, same configuration).

```bash
./booth restart myproject
./booth restart --timeout 30 myproject
```

> **From inside the container:** Use `booth--restart` to restart with full config re-processing (re-reads `config.toml`, `Boothfile`, rebuilds image if needed). This is different from `booth restart` on the host, which keeps the same container and configuration. See [`booth run` — Shutdown & Restart](BOOTH_RUN.md#shutdown--restart).

### `remove`

Explicitly delete a booth container.

```bash
./booth remove myproject                 # remove a stopped booth
./booth remove --force myproject         # force-remove even if running
./booth remove container1 container2     # remove multiple
```

### `prune`

Batch-remove all stopped booth containers.

```bash
./booth prune        # prompts for confirmation
./booth prune --yes  # skip confirmation
```

Also cleans up orphaned sidecar containers (DinD, egress) whose parent no longer exists.

With `cache` or `shared` (`share`), it prunes this project's data instead of containers: what
`.booth/cache/` or `.booth/shared/` holds that `config.toml` does not declare — the leftovers of a
deselected template, which booth no longer mounts. It lists them with their sizes and asks;
refuses while a booth runs on the project.

```bash
./booth prune cache                       # this folder's project
./booth prune shared --yes --code ../app  # another project, no question
```

See [Leftovers of a Deselected Template](BOOTH_LOCALCACHE.md#leftovers-of-a-deselected-template).

### `logs`

Show what a booth printed, or the logs its services wrote.

```bash
./booth logs                       # container output, like `docker logs <booth>`
./booth logs -f --tail 100         # follow, starting from the last 100 lines
./booth logs --list                # the service log files in the booth's /tmp
./booth logs excalidraw -f         # follow /tmp/excalidraw.log
./booth logs --startup             # /tmp/startups.log, the image's startup hooks
./booth logs --name myproject      # another booth
./booth logs lifecycle             # what happened to the booth: started, stopped, idle, …
```

With no service named it is `<engine> logs` for the booth: the main process (ttyd, code-server,
Jupyter, …), booth-entry, and your `.booth/startups/` scripts. `-f`/`--follow`, `--tail`/`-n`,
`--since`, `--until` and `-t`/`--timestamps` are passed through. (Apple container has no
`--since`, `--until` or `--timestamps`, so those are refused there.)

Most autostarted services log to a file instead, so `docker logs` never shows them. A service
name selects `/tmp/<service>.log`, or, when there is none, every `/tmp/<service>-*.log`:
`booth logs n8n` shows `n8n-sandbox.log` and `n8n-search.log` together, with a `==> file <==`
header for each, the way `tail` shows several files. `--startup` is the service `startups`.
`--list` prints the names to use:

```
SERVICE       SIZE  MODIFIED             FILE
excalidraw    4.1K  2026-10-04 13:45:40  /tmp/excalidraw.log
startups      669B  2026-10-04 13:45:40  /tmp/startups.log
```

Positional arguments are service names, so the booth is picked with `--name` or `--code` (by
default, the booth of the current folder).

A stopped keep-alive booth still has its logs. Both forms read them from the stopped container
(log files through `<engine> cp`, which Apple container does not offer: start the booth there
first). `-f` then prints what is there and returns. A booth run without `--keep-alive` is removed
when it stops, and its logs go with it — all but the lifecycle log.

#### The lifecycle log

`booth logs lifecycle` answers "what happened to my booth?": one line per event, with the time,
the booth's name, and who or what caused it.

```
2026-10-04T14:42:23-0400 demo started version=0.80.0 variant=base mode=FOREGROUND port=10000
2026-10-04T14:42:38-0400 demo idle-prompted msg=idle-1791139358376557610 expires=2026-10-04T18:42:48Z
2026-10-04T14:42:48-0400 demo idle-timeout after=25s no answer to the prompt
2026-10-04T14:42:51-0400 demo shutdown reason=idle by=bash /opt/codingbooth/setups/booth--idle-monitor
2026-10-04T14:42:52-0400 demo exited status=0 idle-shutdown by=host-cli
```

| Event | Written when |
| --- | --- |
| `started` | the booth comes up (version, variant, run mode, host port) |
| `stop-requested`, `restart-requested`, `remove-requested` | `booth stop` / `restart` / `remove` is run on the host |
| `shutdown-requested`, `restart-requested` `by=web-ui` | the overlay's or console's Shut down / Restart button is pressed |
| `shutdown`, `restart` | `booth--shutdown` / `booth--restart` runs: `reason=` `idle`, `timer` or `requested` (a button), and `by=` the process that called it |
| `idle-monitor-started`, `idle-prompted`, `idle-answered`, `idle-paused`, `idle-disabled`, `idle-timeout` | the [idle monitor](BOOTH_IDLE.md) decides |
| `console-pane-exited` | a console pane's terminal server (`ttyd`) exits outside a shutdown: that pane then shows 502 until the booth restarts |
| `console-session-reset` | a console pane's session is reset, from the Console UI or `booth--console-reset` (`session=s1` … `s6`, `force=true` when everything started from it was killed first): its shell and what ran in it were ended |
| `exited` | a booth the CLI ran in the foreground ends: its `status`, the `signal` behind it (`SIGINT` = Ctrl+C, `SIGTERM` = `docker stop`, `SIGKILL` = `docker kill`), and whether a restart or idle shutdown asked for it |

The file is `.booth/.tmp/lifecycle.log` in the booth's code folder, on the host. The booth writes
to it through the `.booth/.tmp/` mount and the CLI appends to it directly, so it outlives the
container — `booth logs lifecycle` reads it with no booth running, and `--code <path>` reads one
whose booth is long removed. `booth express` keeps the same file in the spec directory it mounts
at `/home/coder/code/.booth`, and `booth logs --name <booth> lifecycle` reads that directory.
Unlike the rest of `.booth/.tmp/`, it is kept across runs (trimmed to
its newest half once it passes 256 KB), and like the rest of it, it is gitignored. A booth run
without a `.booth/` folder has no `.booth/.tmp/` mount, and so no lifecycle log.

Stopping a follow — Ctrl+C, a closed pipe, a killed terminal — also stops the `tail` inside the
booth, so following never leaves processes behind.

---

## Common Workflows

### Day-to-day development

```bash
# Day 1: Start a persistent booth
./booth --keep-alive --name myproject

# Work inside the container...
# Exit when done (Ctrl+D or exit)

# Day 2: Resume
./booth start myproject

# Day 3: Resume in the background (for web-based variants)
./booth start --daemon myproject
```

### Check what's running

```bash
./booth list
```

### Clean up old containers

```bash
# See what's stopped
./booth list --stopped

# Remove all stopped booths
./booth prune --yes

# Or remove a specific one
./booth remove myproject
```

### Run a daemon booth for a web IDE

```bash
./booth --keep-alive --daemon --variant codeserver --name my-ide
# Access VS Code at http://localhost:10000

# Later, stop and resume
./booth stop my-ide
./booth start --daemon my-ide
```

---

## Persistence Rules

When a container is resumed via `start` or `restart`, its configuration is unchanged. The following **cannot be modified** without removing and recreating the container:

- Container name (`--name`)
- UI port (`--port`)
- Bind mounts (`-v`)
- Port mappings (`-p`)

### Home directory persistence

Use `--persist-home` to preserve `/home/coder` (IDE settings, shell history, app configs) across sessions via a Docker named volume. See [Persist Home Directory](BOOTH_PERSIST_HOME.md) for details.

To change these values, remove the container and run a new one:

```bash
./booth remove myproject
./booth --keep-alive --name myproject --port 9000
```

---

## Container Snapshots

Stopped keep-alive containers can be saved and shared using standard Docker commands.

### Save container state as a new image

```bash
docker commit <container-name> <image-name>:<tag>
```

### Export/import container filesystem

```bash
# Export
docker export -o backup.tar <container-name>

# Import as a new image
cat backup.tar | docker import - my-image:restored
```

### Save/load images

```bash
# Save image to file
docker save -o my-image.tar <image-name>:<tag>

# Load on another machine
docker load -i my-image.tar
```

See the [Docker documentation](https://docs.docker.com/) for more options.
