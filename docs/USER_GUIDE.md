# CodingBooth — Developing in a Booth

This guide is for the developer who **works in** a booth: the project already has a `.booth/`
folder (a teammate set it up, or you did once), and now you just want to write software in it.

It follows a working day, roughly in order. Each section says what the task is, gives the quick
way to do it, and links to the detailed document.

Setting a booth up — choosing tools, templates, ports, mounts, credentials — is a different job
with its own guide:
[Setting Up a Booth](https://github.com/NawaMan/CodingBooth/blob/main/docs/SETUP_GUIDE.md). When a
section below says "ask whoever set up the booth", that is the line between the two.

> Inside a booth, the in-image help is [`GUIDE.md`](https://github.com/NawaMan/CodingBooth/blob/main/docs/GUIDE.md)
> (desktop tiling, clipboard). AI agents working inside a booth should read
> [`AGENT.md`](https://github.com/NawaMan/CodingBooth/blob/main/docs/AGENT.md).

---

## Table of Contents

1. [Getting going](#1-getting-going)
2. [Daily coding](#2-daily-coding)
3. [Running and seeing the app](#3-running-and-seeing-the-app)
4. [Git and credentials](#4-git-and-credentials)
5. [Living with it day to day](#5-living-with-it-day-to-day)
6. [When something isn't there](#6-when-something-isnt-there)
7. [Upkeep](#7-upkeep)

---

## 1. Getting going

### Install Docker

CodingBooth runs on Docker: Docker Engine (rootful) on Linux, Docker Desktop on macOS and Windows.
`docker info` must work **without sudo**. On Linux, add yourself to the `docker` group and log out
and back in:

```bash
docker info                          # must succeed without sudo
sudo usermod -aG docker $USER        # Linux only, then log out and back in
```

Rootless Docker and userns-remap are not supported on Linux. Podman and Apple container work as
experimental engines.

More: [README → Troubleshooting](https://github.com/NawaMan/CodingBooth/blob/main/README.md#troubleshooting) ·
[Container engines](https://github.com/NawaMan/CodingBooth/blob/main/docs/BOOTH_ENGINES.md)

### Start a project that already has a booth

The project's `./booth` script is committed to git. It downloads the right CodingBooth binary on
first use (pinned by `.booth/tools/codingbooth.lock`, checked against a SHA-256), so everyone on
the project runs the same version. Nothing else needs installing.

```bash
git clone <repo> && cd <repo>
./booth
```

The `booth` script works relative to its own location, so `/path/to/project/booth` runs that
project's booth from anywhere.

More: [booth install → Wrapper](https://github.com/NawaMan/CodingBooth/blob/main/docs/BOOTH_INSTALL.md) ·
[Lock file](https://github.com/NawaMan/CodingBooth/blob/main/docs/BOOTH_INSTALL.md#5-lock-file)

### The first run is slow

The first `./booth` builds the project's image from `.booth/Boothfile`: it pulls the base image and
installs the project's tools. Later runs reuse Docker's build cache and start in seconds.

More: [README → "Build takes forever"](https://github.com/NawaMan/CodingBooth/blob/main/README.md#troubleshooting)

### Choose how to open it

A booth can open in a browser, in your terminal, or just run one command and exit:

| You want | Run |
|---|---|
| The booth's UI (terminal, VS Code, Jupyter or a desktop — depends on the variant) | `./booth`, then open `http://localhost:10000` (the URL is printed) |
| A plain shell in your own terminal, no browser | `./booth -- bash` |
| One command, then exit | `./booth -- just test` |
| Start in the background | `./booth --daemon` |
| Don't open the browser automatically | `./booth --no-browser` |

More: [README → Command Passthrough](https://github.com/NawaMan/CodingBooth/blob/main/README.md#command-passthrough) ·
[Variants](https://github.com/NawaMan/CodingBooth/blob/main/docs/BOOTH_VARIANTS.md) ·
[booth run → Run Modes](https://github.com/NawaMan/CodingBooth/blob/main/docs/BOOTH_RUN.md#run-modes)

---

## 2. Daily coding

### Find the project's commands

Every booth has [`just`](https://just.systems/). If the project has a `Justfile`, it is the menu of
everything the project knows how to do:

```bash
just --list          # what can I run?
just test            # or: just run, just build, ...
```

Run `booth--info` to see this booth's version, variant and key paths.

### Edit with your own editor

The project folder is mounted into the booth at `/home/coder/code`, and file ownership is mapped to
your host user. Edit on the host with any editor, and build or run inside the booth. Files created
inside the booth belong to you on the host, not to root.

More: [How it works](https://github.com/NawaMan/CodingBooth/blob/main/docs/HOW_IT_WORKS.md) ·
[README → "Permission denied" on project files](https://github.com/NawaMan/CodingBooth/blob/main/README.md#troubleshooting)

### Use the IDE inside the booth

If the booth's variant comes with an IDE, it is in the browser: `codeserver` gives VS Code,
`notebook` gives JupyterLab, and the desktop variants run IDEs such as IntelliJ when the booth was
set up with them.

> **Not covered yet:** attaching a host IDE to a running booth (VS Code Dev Containers'
> "Attach to Running Container", JetBrains Gateway). Booths are ordinary Docker containers, so
> these may work, but they are not tested or documented.

More: [Variants](https://github.com/NawaMan/CodingBooth/blob/main/docs/BOOTH_VARIANTS.md)

### Open another terminal

Run a second shell next to a long build, or a one-off command from the host, in the booth that is
already running:

```bash
./booth shell                    # another interactive shell in this project's booth
./booth exec -- make test        # run one command and get its exit code
./booth exec --run -- make test  # start the booth first if it isn't running
```

Both find the booth from the current folder. Without `--run` they fail if the booth isn't running;
with it they start or create it as needed.

More: [booth connect](https://github.com/NawaMan/CodingBooth/blob/main/docs/BOOTH_CONNECT.md)

### Arrange the console and desktop

The base variant's browser terminal (the Console UI) splits into panes and tabs with i3-style
`Ctrl+Alt` shortcuts, and a project can check in a starting layout. Desktop booths can tile
windows (i3, KDE Krohnkite, sway) and share the clipboard with the host.

More: [Console layout](https://github.com/NawaMan/CodingBooth/blob/main/docs/BOOTH_CONSOLE.md) ·
[In-booth guide: tiling and clipboard](https://github.com/NawaMan/CodingBooth/blob/main/docs/GUIDE.md)

---

## 3. Running and seeing the app

### Open a dev server in your host browser

There are two ways, depending on whether the port is already published:

- **Published by the booth's config:** just open it. `./booth expose list` (on the host) shows what
  is published and where. The server must listen on `0.0.0.0` inside the booth (for most dev
  servers that means `--host 0.0.0.0`).
- **Not published:** tunnel it from inside the booth, with no restart:

```bash
booth--expose 8080             # container :8080 → host localhost:8080
booth--expose 8080 +8080       # → host (booth port + 8080), e.g. 18080 — avoids clashes between booths
booth--expose list             # what is tunnelled now
```

A tunnel lasts until the booth stops. If you use the same port every time, ask whoever set up the
booth to publish it (`booth config --expose <port>`).

More: [booth expose](https://github.com/NawaMan/CodingBooth/blob/main/docs/BOOTH_EXPOSE.md) ·
[booth run → Ports](https://github.com/NawaMan/CodingBooth/blob/main/docs/BOOTH_RUN.md#ports)

### Reach a database or API on the host

The host is always reachable from inside the booth as `host.docker.internal` (also in
`$BOOTH_HOST_NAME`). No tunnel is needed.

```bash
curl http://host.docker.internal:3000/
psql -h host.docker.internal -p 5432 -U postgres
```

The host service must listen on `0.0.0.0`, not only on `127.0.0.1`.

More: [booth expose → The other direction](https://github.com/NawaMan/CodingBooth/blob/main/docs/BOOTH_EXPOSE.md#the-other-direction-reaching-a-service-on-the-host)

### Use Docker or Compose inside the booth

If the booth was set up with Docker-in-Docker (`--dind`), `docker` and `docker compose` work inside
it against a sidecar daemon. Docker-in-Docker is privileged, so `./booth` asks before starting it.
Read what it allows before you answer yes.

More: [booth run](https://github.com/NawaMan/CodingBooth/blob/main/docs/BOOTH_RUN.md) ·
[Security → Docker-in-Docker](https://github.com/NawaMan/CodingBooth/blob/main/docs/BOOTH_SECURITY.md)

---

## 4. Git and credentials

### Push and pull

`git`, `gh`, `tig` and `lazygit` are in every booth. Whether you can **push** depends on which
credentials the booth was set up to bring in from the host:

| Booth set up with | Gives you |
|---|---|
| `git-credential` | your host `~/.gitconfig` (name, email, credential helper) |
| `ssh` / `openssh/credential` | your host `~/.ssh` keys and config, read-only |
| `gh/credential` | your host GitHub CLI login |

They are copied into the booth's home at start (from `/etc/cb-home-seed/`), so the host files are
never written. If a push fails for authentication, check what is there (`ls ~/.ssh`,
`gh auth status`) and ask whoever set up the booth to add the matching template.

Logging in from inside (`gh auth login`) works, but the login is lost when the booth stops unless
home is persisted (see [What survives a restart](#what-survives-a-restart)).

More: [booth home → Credential seeding](https://github.com/NawaMan/CodingBooth/blob/main/docs/BOOTH_HOME.md#common-credential-seeding-examples) ·
[Security → Convenience mounts](https://github.com/NawaMan/CodingBooth/blob/main/docs/BOOTH_SECURITY.md)

> **Not covered yet:** SSH agent forwarding (using your host's `ssh-agent` instead of copying
> keys) and GPG-signed commits. Neither is built in today.

### Log in to AI coding tools

Claude Code, Codex, Gemini CLI, Copilot and others are booth templates. Most have a `credential`
extension that brings your host login in, so you don't log in again in every booth. Claude Code
also has `auto-accept`, which allows edits without prompting and keeps a deny list for
destructive git and `rm -rf` commands.

More: [booth home](https://github.com/NawaMan/CodingBooth/blob/main/docs/BOOTH_HOME.md) ·
[booth cache](https://github.com/NawaMan/CodingBooth/blob/main/docs/BOOTH_LOCALCACHE.md) ·
[Security](https://github.com/NawaMan/CodingBooth/blob/main/docs/BOOTH_SECURITY.md)

---

## 5. Living with it day to day

### Stop and come back

By default a booth is removed when you exit. Your **code** stays, because it lives on the host;
everything else in the container is discarded. To keep the container between sessions, use
keep-alive:

```bash
./booth --keep-alive        # exit leaves it stopped, not removed
./booth list                # booths on this machine: name, status, port, code path
./booth start               # resume this project's booth
./booth stop                # stop it
./booth remove              # delete it
```

Inside the booth, `booth--shutdown` stops it and `booth--restart` restarts it.

More: [booth lifecycle](https://github.com/NawaMan/CodingBooth/blob/main/docs/BOOTH_LIFECYCLE.md)

### What survives a restart

| Where | Survives? |
|---|---|
| `/home/coder/code` — your project | **Yes** — it is the host folder |
| `.booth/cache/`, `.booth/shared/` mounts | **Yes** — they are host folders (local-only and committed, respectively) |
| The rest of `/home/coder` — shell history, IDE settings, logins | **No**, unless the booth uses `--persist-home` or the setup caches that path |
| Packages you install yourself (`apt`, `pip`, `npm -g`) | **No** — see [Try a tool for now](#try-a-tool-for-now) |
| A stopped keep-alive container | **Everything**, until you remove it |

To keep your whole home directory in a Docker volume:

```bash
./booth --persist-home
```

More: [Persist home](https://github.com/NawaMan/CodingBooth/blob/main/docs/BOOTH_PERSIST_HOME.md) ·
[booth home](https://github.com/NawaMan/CodingBooth/blob/main/docs/BOOTH_HOME.md) ·
[Local cache](https://github.com/NawaMan/CodingBooth/blob/main/docs/BOOTH_LOCALCACHE.md) ·
[Shared state](https://github.com/NawaMan/CodingBooth/blob/main/docs/BOOTH_SHARED.md) ·
[Lifecycle → Persistence rules](https://github.com/NawaMan/CodingBooth/blob/main/docs/BOOTH_LIFECYCLE.md#persistence-rules)

### Switch between setups with profiles

A project can ship named overlays — for example `dev`, `deploy` or `trace` — each changing only
what differs from the base config:

```bash
./booth --profile dev               # base config + .booth/dev--config.toml
BOOTH_PROFILES=dev ./booth          # same
```

Your own secrets for a profile go in `.booth/.<name>--env`, which must stay out of git.

More: [booth profiles](https://github.com/NawaMan/CodingBooth/blob/main/docs/BOOTH_PROFILES.md)

### Run two booths of the same code

Starting a second booth from the same folder just works: it gets the next free port and the name
`<project>-<port>`. Each git worktree is its own folder, so each gets its own booth. Plain
lifecycle commands act on the first booth. Name the second one to target it:

```bash
./booth                               # second booth → e.g. myproj-12000
./booth stop myproj-12000
./booth --name '{project}-{port}'     # an explicit name that is still unique
```

More: [booth run → Container name](https://github.com/NawaMan/CodingBooth/blob/main/docs/BOOTH_RUN.md#container-name)

### Shut down when idle, or watch the clock

```bash
./booth --idle-time 600              # after 10 min idle, ask "still there?", stop 60 s later
./booth --show-run-time              # show elapsed time in the booth UI
```

More: [booth idle](https://github.com/NawaMan/CodingBooth/blob/main/docs/BOOTH_IDLE.md) ·
[booth runtime](https://github.com/NawaMan/CodingBooth/blob/main/docs/BOOTH_RUNTIME.md)

### Messages from scripts and the host

Scripts, CI and the host can send dialogs and toasts into the booth's web UI (`booth message
send`). A message that arrives while the tab is in the background chimes and marks the tab title.
From a terminal inside the booth, read and answer them with:

```bash
booth--msg           # walk through pending messages
booth--msg list      # all messages, answered or not
```

More: [booth message](https://github.com/NawaMan/CodingBooth/blob/main/docs/BOOTH_MESSAGE.md) ·
[UI overlay → Attention signals](https://github.com/NawaMan/CodingBooth/blob/main/docs/BOOTH_UI_OVERLAY.md#attention-signals)

---

## 6. When something isn't there

### Try a tool for now

You have passwordless `sudo` inside the booth. Install anything to try it. It is gone at the next
restart, which keeps experiments from leaking into the project:

```bash
sudo apt-get update && sudo apt-get install -y htop
npm install -g some-tool             # if the booth has Node
```

### Make it permanent

If the tool turns out to be needed, it belongs in the booth's setup, not in your memory of what to
reinstall. That is a change to `.booth/`. Ask whoever set up the booth, or add it yourself on the host:

```bash
booth template search htop                               # is there a template?
booth config --no-tui --overwrite --add-select 'apt-pkg:htop'   # add it, keep everything else
```

Don't hand-edit `.booth/Boothfile` or `.booth/config.toml`. They are generated, and editing them
can make `booth config` refuse to regenerate them later. `.booth/` is read-only inside the booth,
so this change is made on the host.

More: [Setting Up a Booth](https://github.com/NawaMan/CodingBooth/blob/main/docs/SETUP_GUIDE.md) ·
[booth config](https://github.com/NawaMan/CodingBooth/blob/main/docs/BOOTH_CONFIG.md) ·
[booth config → Hand-written files](https://github.com/NawaMan/CodingBooth/blob/main/docs/BOOTH_CONFIG.md#hand-written-files)

### Pick up a change to the booth

After a teammate changes `.booth/` (or you pull one), start the booth fresh and the image rebuilds
from the new Boothfile:

```bash
./booth                      # a fresh run always rebuilds (cached layers make it quick)
booth--restart               # from inside a running booth: exit and come back rebuilt
```

A **kept-alive** container resumed with `./booth start` keeps its old image and settings. Remove
it (`./booth remove`) and run `./booth` again to get the change.

More: [Lifecycle → Persistence rules](https://github.com/NawaMan/CodingBooth/blob/main/docs/BOOTH_LIFECYCLE.md#persistence-rules)

---

## 7. Upkeep

### Update CodingBooth

```bash
booth install                # update to the latest version
booth install <version>      # or a specific one
./booth --pull               # refresh the base image even if a local copy exists
```

`booth install` in a project updates that project's lock file. Commit it, so the whole team moves
together.

More: [booth install](https://github.com/NawaMan/CodingBooth/blob/main/docs/BOOTH_INSTALL.md) ·
[booth run → Pulling images](https://github.com/NawaMan/CodingBooth/blob/main/docs/BOOTH_RUN.md#pulling-images)

### When it doesn't work

| Question | Look at |
|---|---|
| What did the container print? | `./booth logs` (`-f` to follow) |
| Did a startup hook fail? | `./booth logs --startup` |
| Why did the booth stop? | `./booth logs lifecycle` |
| A background service's log | `./booth logs --list`, then `./booth logs <service>` |
| What would `./booth` actually run? | `./booth --dryrun --verbose` |
| What config is the booth running with? | `booth--info`, `booth--envs` (inside) |
| Files left behind by a run | `.booth/.tmp/` — keep them with `--leave-tmp-on-exit` |

More: [README → Troubleshooting](https://github.com/NawaMan/CodingBooth/blob/main/README.md#troubleshooting) ·
[Lifecycle → logs](https://github.com/NawaMan/CodingBooth/blob/main/docs/BOOTH_LIFECYCLE.md) ·
[booth tmp](https://github.com/NawaMan/CodingBooth/blob/main/docs/BOOTH_TMP.md) ·
[booth health](https://github.com/NawaMan/CodingBooth/blob/main/docs/BOOTH_HEALTH.md)

### Clean up

```bash
./booth list --stopped        # what is lying around
./booth prune                 # remove all stopped booths (asks first)
booth home-volume-list        # volumes left by --persist-home
```

More: [booth lifecycle](https://github.com/NawaMan/CodingBooth/blob/main/docs/BOOTH_LIFECYCLE.md) ·
[Persist home → Volume management](https://github.com/NawaMan/CodingBooth/blob/main/docs/BOOTH_PERSIST_HOME.md#volume-management)

### Know what the booth protects

A booth isolates the project's tools and processes from your machine, but anything mounted into it
— credentials, caches, the Docker socket, Docker-in-Docker — is reachable from inside. `./booth`
warns when a booth's settings could reach the host, and asks before starting privileged ones.

More: [Security](https://github.com/NawaMan/CodingBooth/blob/main/docs/BOOTH_SECURITY.md) ·
[Security → Checklist before launching](https://github.com/NawaMan/CodingBooth/blob/main/docs/BOOTH_SECURITY.md#7-checklist-before-launching-a-booth)
