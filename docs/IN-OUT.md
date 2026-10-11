# In and Out of the Booth

> Every way to put something into a booth, or connect it to something, outside `/home/coder/code`.

The project folder is bind-mounted at `/home/coder/code`, so anything in it is already shared with
the host. Everything else in the container is rebuilt from the image on every start, unless one of
the mechanisms below keeps it, puts it there, or connects it. This page lists all of them in one
place, and links to the guide that covers each in depth.

Setups and startup scripts are left out on purpose. They can do anything, so they are not a
mechanism of their own — see [Customization](BOOTH_CUSTOMIZATION.md) and [Setups](BOOTH_SETUP.md).
The one exception is [copying a file outside home on every start](#copying-outside-home), using a
startup script. For a copy into an existing booth, use [`booth cp`](BOOTH_TOOLS.md).

Back to [README](../README.md)

---

## Table of Contents

- [Two Questions](#two-questions)
- [The Map](#the-map)
- [1. Build Time — Baked into the Image](#1-build-time--baked-into-the-image)
- [2. Start Time — Live Links](#2-start-time--live-links)
- [3. Start Time — Copies into Home](#3-start-time--copies-into-home)
- [4. Start Time — Environment and Connections](#4-start-time--environment-and-connections)
- [5. While Running](#5-while-running)
- [Choosing One](#choosing-one)
- [Known Gaps](#known-gaps)

---

## Two Questions

Each mechanism answers two separate questions:

1. **How does the data get in?**
   - **Built in** — it is part of the image, the same on every run.
   - **Live link** — a bind mount or volume. Changes made inside the booth flow back out.
   - **Copy, no overwrite** (*seed*) — copied in at start only where nothing is there yet.
   - **Copy, overwrite** (*override*) — copied in at start every time, replacing what is there.
   - **None** — the container's own writable layer. It survives a stop/start of a
     `--keep-alive` container and is gone when the container is removed.

2. **Where does the data live, and who shares it?**
   - **The host user** — every project on this machine.
   - **The project, in git** — the whole team.
   - **The project, not in git** — this folder on this machine only. A second worktree of the same
     repo has its own.
   - **Docker storage** — a named volume, not a folder you can see on the host.
   - **The image** — whoever runs the same image.

Cache and Shared are both live links; they differ only in where the files are kept and whether git
may see them. The two seed folders and the two override folders are the same copy step fed from
different places.

---

## The Map

| Where the data lives ↓ / how it gets in → | **Live link** | **Copy, no overwrite** | **Copy, overwrite** | **Built in** |
|---|---|---|---|---|
| **Host user** | `--mount` / run-args `-v $HOME/…` (`java+m2`, `rust+cargo-cache`) | `/etc/cb-home-seed/` (credential extensions, `npmrc`, `pip-config`) | `/etc/cb-home/` | — |
| **Project, in git** | **Shared** — `.booth/shared/` | `.booth/home-seed/` | `.booth/home/` | Boothfile, `*-install` extensions |
| **Project, not in git** | **Cache** — `.booth/cache/` | — | — | — |
| **Docker storage** | `--persist-home` (one volume per booth); service volumes (one per booth); package caches (one per tool, every booth) | — | — | — |
| **Image** | — | `/etc/skel` re-seed (desktop launchers) | — | variant, `--image`, `--dockerfile` |
| **None** | the container's own layer | | | |

---

## 1. Build Time — Baked into the Image

| Mechanism | Where it is set | What it does |
|---|---|---|
| Boothfile `copy` | `.booth/Boothfile` | Copies project files to any path in the image |
| Boothfile `run --mount=type=bind,target=/tmp/ctx …` | Boothfile; the `*-install` extensions (`npm-install`, `pnpm-install`, `go-mod`, `mvn-install`, `gradle-deps`, `pip`, `uv`, …) | Reads project files during the build and keeps the result, e.g. downloaded dependencies |
| Boothfile `install`, `run` | Boothfile; the `*-pkg` templates (`apt-pkg`, `brew-pkg`, …) | Installs packages, or runs any command |
| Boothfile `env`, `arg`, `workdir`, `label` | Boothfile | Settings stored in the image |
| `--build-arg`, `--apt-snapshot` | CLI / `config.toml` | Changes what the build produces |
| `--variant`, `--image`, `--dockerfile`, `--boothfile` | CLI / `config.toml` | Chooses the image as a whole |

See [Build](BOOTH_BUILD.md), [Customization](BOOTH_CUSTOMIZATION.md) and
[Reproducibility](REPRODUCIBILITY.md).

---

## 2. Start Time — Live Links

| Mechanism | Where it is set | Source → target |
|---|---|---|
| **Cache** | `cache-files` / `cache-dirs` in a template or `config.toml`; or files placed in `.booth/cache/` by hand | `.booth/cache/<path>` → `/<path>`. Read-write. **Must not be in git** — the booth refuses to start otherwise |
| **Shared** | `shared-files` / `shared-dirs`; or files placed in `.booth/shared/` by hand | `.booth/shared/<path>` → `/<path>`. Read-write. **Meant for git** |
| **Bind mount** | `booth config --mount` / `--add-mount` (each adds a `-v`); `run-args = ["-v", …]` in `config.toml` or a template | Any host path → any container path, read-write or `:ro`. An entry whose host path does not exist is dropped with a notice |
| `@code` source | run-args `-v @code:<path>` (`anythingllm+project-fs`) | The project folder, mounted a second time at another path |
| **Named volume** | run-args `-v <name>:<path>` (`postgresql`, `mysql`, `redis`, `mongodb`, `penpot`, …) | Docker storage → path. `{name}` in the name makes it one volume per booth, `{project}` one per project |
| `--persist-home` | CLI / `config.toml` | Volume `cb-home-<name>` → the whole of `/home/coder`. Seeding stops after the first run |
| `--tls-cert`, `--tls-key` | CLI | Host files → `/tmp/booth-tls-*.pem`, read-only |
| Devices and GPUs | run-args `--device /dev/kvm`, `--gpus all` | Host hardware → the booth |
| Owner and mode | `[[owner-permission]]` in a template → `.booth/owner-permission.yaml` | Sets the owner and mode of a mount point on every start. See [Owner and mode of a mount](#owner-and-mode-of-a-mount) |

Cache and Shared follow the same layout rules: the folder tree mirrors the container's root; a file
is mounted on its own; a folder holding a `.mount-this` marker is mounted whole. Neither may mount
over `/opt/codingbooth` or `/home/coder/code`. Both are mounted whether or not `.booth/` itself is
writable (`--writable-booth`).

A declared path starts empty unless a **seed** gives it content: `.booth/cache-seed/` and
`.booth/shared-seed/` are committed, use the same layout, and are copied into `.booth/cache/` and
`.booth/shared/` while a path there is missing or empty — never over content. A template ships
them with `[files.cache-seed]` / `[files.shared-seed]`. Because the Cache seed is in git, a fresh
clone gets the content too. See [Initial Content](BOOTH_LOCALCACHE.md#initial-content).

The two are checked against each other. A path in both refuses to start. One inside the other —
`+profile-cache` with `+bookmarks-shared` — starts with a notice saying which part goes to git;
`booth config` prints the same notice. See
[Cache and Shared on the same path](BOOTH_LOCALCACHE.md#cache-and-shared-on-the-same-path).

See [Local Cache](BOOTH_LOCALCACHE.md), [Shared State](BOOTH_SHARED.md) and
[Persist Home](BOOTH_PERSIST_HOME.md).

### Read-only or read-write

A plain bind mount takes Docker's own suffixes, because booth passes the spec through unchanged:

| Spec | Effect |
|---|---|
| `~/.m2:/home/coder/.m2` or `…:rw` | Read-write (Docker's default) |
| `~/.aws:/etc/cb-home-seed/.aws:ro` | Read-only |
| `…:ro,z`, `…:Z` | Read-only plus an SELinux label; any Docker option passes through |

It is the same from `booth config --mount '<spec>'` and from `run-args = ["-v", "<spec>"]`. booth reads
the spec only to find the host path: it expands `~`, drops the mount when the path is missing, and
when several per-platform paths point at one target it keeps the first that exists.

In the catalog, every host → `/etc/cb-home*` mount is `:ro` (pip, npmrc, claude, aws, gcloud,
antigravity, docker, firebase, gem): the copy step only reads them. The host package caches
(`~/.m2`, `~/.cargo/registry`) are read-write, because the tools write into them.

Cache and Shared are **always read-write**; their only per-path option is a permission mode
(`"home/coder/.gnupg:0700"`). booth itself mounts the project's `.booth/` read-only — except
`.booth/.tmp/` — unless `--writable-booth` is given.

### The `@code` source

`@code` in the source part of a run-args `-v` means **the host project folder** — the same path
already mounted at `/home/coder/code`. Just before `docker run`, booth replaces `@code` with that
path, so the project is mounted a second time, somewhere else in the booth.

It exists because a template cannot know where the project lives on the host: `$PWD` and `~` do
not mean "the project", so without `@code` a template had no way to say "mount the project here
too".

Its one user is `ai-tools/anythingllm+project-fs`:

```toml
run-args = ["-v", "@code:/home/coder/.anythingllm/anythingllm-fs/code"]
```

AnythingLLM's file-system agent only touches files inside its own folder, and resolves symlinks
to check — so a symlink to `~/code` is rejected. A second bind mount makes the project really be
inside that folder.

### Named volumes in use

The service templates name their volume `<prefix>-{name}`. `{name}` stays literal in
`config.toml` and becomes the booth's name when the booth starts. A booth's default name is its
folder name, so a project — each clone, each worktree — has its own data, and a second booth of the
same folder has its own too.

| Volume | Template | Examples using it |
|---|---|---|
| `booth-pgdata-{name}` | `middlewares/postgresql` | affine, rails, data, pern, postgrest, `examples/demo` |
| `booth-mysqldata-{name}` | `middlewares/mysql` | lamp, lemp, wordpress |
| `booth-mongodata-{name}` | `middlewares/mongodb` | mean, mern |
| `booth-redisdata-{name}` | `middlewares/redis` | affine |
| `booth-kafkadata-{name}` | `middlewares/kafka` | — |
| `booth-rabbitmqdata-{name}` | `middlewares/rabbitmq` | — |
| `booth-flocidata-{name}` | `tools/floci` | floci |
| `booth-penpot-assets-{name}` | `tools/penpot` | — |
| `cb-home-<booth name>` | the CLI, for `--persist-home` | — (one per booth) |
| `booth-cache-gomod`, `booth-cache-gobuild` | `go+mod-cache` | go-example |
| `booth-cache-npm` | `nodejs+npm-cache` | npm-example |
| `booth-cache-pnpm` | `nodejs+pnpm-cache` | npm-example |
| `booth-cache-pip` | `python+pip-cache` (owner and mode set at start) | pip-example |
| `booth-cache-uv` | `python+uv-cache` | pip-example |
| `booth-cache-gradle` | `java+gradle-cache` | spring-boot-example |

A `booth-cache-*` volume is created the first time a booth mounts it, labelled `cb.volume=cache`
and shared by every project on this machine. List them with `docker volume ls --filter
label=cb.volume=cache` and reset one with `docker volume rm booth-cache-gomod` (the booth must not
be using it). Podman keeps a separate store: `CB_ENGINE=podman` and `podman volume ls --filter
label=cb.volume=cache`. With `--persist-home`, the cache mount sits inside the home volume, and
the downloads live in the cache volume.

Two placeholders work in a volume source:

| Placeholder | Becomes | So the volume is |
|---|---|---|
| `{name}` | the booth's final name — `--name`, or the folder name by default | one per booth |
| `{project}` | the project (folder) name | shared by every booth of the folder |

Booth creates such a volume the first time it is needed, labelled `cb.project=<project>` and
`cb.volume=project`, plus `cb.booth=<name>` for a `{name}` volume. `docker volume ls --filter
label=cb.project=myproj` lists all of a project's data, from every booth.

**A second booth of the same folder** gets its own volume, because it must have another name:
`--name other`, `--name '{project}-{port}'`, or the automatic `<project>-<port>` booth gives it
when the default name is taken. It starts empty. When the default booth already has data, the first
start prints where it is and the command to copy it — stop the default booth first. Data follows
the name: a booth you rename, or one whose name holds `{port}` and gets a new port, starts with a
new volume, and the old one stays.

Two folders with the same name share a default booth name, and so a volume, when their booths
run at different times. Run at once, the second booth is named `<project>-<port>` and gets its own.

**Before per-booth names** these volumes had one fixed name (`booth-pgdata`, …) shared by every
project. The first start that creates a booth's new volume while the old one exists prints a
notice with both ways to keep the old data: mount it (`booth config --add-mount
booth-pgdata:/var/lib/postgresql`) or copy it into the new volume. The old volume is never removed
by booth.

Appwrite is different: its Compose volumes live in its own Docker-in-Docker sidecar, not on the
host.

### Adding or changing a named volume

**Adding your own** works on any container path. Use a name with no `/` as the source; `{name}`
and `{project}` work here too. Docker creates the volume on the first start:

```bash
booth config --no-tui --select go --mount 'myproj-data:/home/coder/.mydata'
# config.toml:  run-args = ["--volume", "myproj-data:/home/coder/.mydata"]
```

**Replacing a template's volume** is the same flag on the template's path. A user mount replaces
the template's mount on the same container path, and survives every later `booth config`:

```bash
booth config --no-tui --add-mount 'shared-pgdata:/var/lib/postgresql'   # use your own volume
booth config --no-tui --remove-mount /var/lib/postgresql                # back to the template's
```

The TUI's Mount field does the same. See
[Run-Args Ownership](BOOTH_CONFIG.md#a-user-mount-replaces-the-templates-on-the-same-path).

To reset a booth's data, remove its volume while no booth uses it:
`docker volume rm booth-pgdata-<booth name>`.

### Owner and mode of a mount

A volume that Docker creates, or one that an image build wrote into, can hold directories owned by
root, which coder cannot write. A template lists `[[owner-permission]]` entries: `path` (absolute),
and the optional `user`, `group` and `mode` (an octal string such as `"1777"`). `booth config`
merges them into `.booth/owner-permission.yaml`. It is a generated file, fingerprinted in
`.booth/.generated` like the Boothfile, so do not edit it by hand.

```yaml
- path: "/opt/pip-cache"
  user: "coder"
  group: "coder"
  mode: "1777"
```

On every start, `booth-entry` applies each entry as root. A directory entry sets the owner and mode
on that directory and every directory under it, and does not cross onto another filesystem. Files
keep the mode they have. A path that is not a mount point, or does not exist, is skipped with a
notice.

Its one user is `python+pip-cache`: `/opt/pip-cache` becomes `coder:coder`, mode `1777`. See the
`owner-permission` key in [Template schema](AGENT_TEMPLATE.md).

### Who uses `--persist-home`

Nothing in the catalog turns it on: no template, example, variant or recipe sets it. It is the
user's choice — `--persist-home` on the command line, or `persist-home = true` in `config.toml` —
and is marked experimental.

| Part | What it does |
|---|---|
| CLI | Creates volume `cb-home-<name>` and mounts it on `/home/coder` before the code mount; sets `BOOTH_HOME_PERSISTED=true` and the label `cb.persist-home=true` |
| `booth-entry` | After the first start writes `~/.cb-home-seeded`, and from then on **skips both seed copies**. The override copies still run every start |
| Lifecycle | `booth remove` deletes the volume; `booth home-volume-list` / `-export` / `-import` manage it |
| Docs | Offered where Cache and Shared cannot help: KDE's desktop layout, DBeaver's full UI state, a full personal browser profile |

Because seeding stops, a rebuilt image's new desktop launchers no longer appear in a persisted
home.

---

## 3. Start Time — Copies into Home

All four copy into `/home/coder` at start, in this order. A seed fills only what is still missing;
an override replaces what is there:

| Order | Mechanism | Source | Overwrites? | For |
|---|---|---|---|---|
| 1 | `.booth/home-seed/` | Project, in git | No | Team defaults each user may change |
| 2 | `.booth/home/` | Project, in git | **Yes** | Team settings every user must have |
| 3 | `/etc/cb-home-seed/` | Host, through a read-only bind mount | No | Personal defaults and credentials (`aws-cli+credential`, `nodejs+npmrc`, …) |
| 4 | `/etc/cb-home/` | Host, through a bind mount | **Yes** | Personal values that must win, e.g. fresh credentials over a cached `~/.claude/` |

The copy follows the same `.mount-this` rule as Cache: a marked folder is copied as one unit,
otherwise file by file.

A template fills the two project folders through `[files.home-seed]` and `[files.home]`; `booth
config` writes them out. The image also re-seeds `/etc/skel/Desktop` without overwriting, so a
rebuilt image's new desktop launchers appear.

See [Home Directory](BOOTH_HOME.md) for the exact precedence.

### Copying outside home

None of the four copies reaches outside `/home/coder`. To copy a file to a system path on every
start, use a startup script: it runs as `coder`, and it may use `sudo` even with `--no-sudo`, which
takes sudo away only after the startup scripts have run.

```bash
# .booth/startups/20-corp-conf--startup.sh
sudo install -D -m 0644 -o root -g root \
    "$HOME/code/.booth/files/etc/foo/corp.conf" /etc/foo/corp.conf
```

The source can be any project file; `.booth/files/` above is only a convention. Use `install`, not a
link: `.booth/` is mounted read-only. Unlike the copies above, the script can also run a command
after the copy, e.g. `sudo update-ca-certificates` for a CA certificate.

For a one-time transfer into or out of an existing booth, use
[`booth cp`](BOOTH_TOOLS.md#copy-files-outside-the-shared-project). It can copy outside home, but
does not repeat the copy on future starts or run commands afterwards.

Some paths have a better way:

| Path | Use instead |
|---|---|
| `/etc/hosts` | `run-args = ["--add-host", "myapi.local:10.0.0.5"]`. Docker rewrites the file on every start; a startup script works too, because it runs again |
| The same file for everyone, rarely changed | Boothfile `copy` — baked into the image |
| A host file, read-only | `--mount '<host-path>:<path>:ro'` — a live link, but read-only it acts like a copy |
| A file edited inside the booth and kept | Cache or Shared on that path |

---

## 4. Start Time — Environment and Connections

| Mechanism | Where it is set | What it does |
|---|---|---|
| Environment variables | `.booth/.env`, `.booth/.<profile>--env`, `--env-file`, `booth config --env`, Boothfile `env` | Puts values into the booth's environment |
| Ports | `--port`, `booth config --expose` | Connects host ports to booth ports |
| `--dind` | CLI | Runs a Docker sidecar on a private network and sets `DOCKER_HOST` |
| `--egress` | CLI | Sends outbound traffic through a proxy that enforces a policy |
| `--public` | CLI | Listens on every interface, behind a password |
| Other run-args | `config.toml` / template | Anything `docker run` accepts — `--network`, `--add-host`, `--cap-add`, a mounted `docker.sock`, … Ones that let the booth reach the host need consent |
| `--sudo`, `--rootless`, `--apple-low-ports`, `--vm-*` | CLI | Permissions and VM resources |

See [Expose](BOOTH_EXPOSE.md), [Profiles](BOOTH_PROFILES.md) and [Security](BOOTH_SECURITY.md).

---

## 5. While Running

| Mechanism | What it does |
|---|---|
| [`booth cp`](BOOTH_TOOLS.md#copy-files-outside-the-shared-project) | Copies files between host and booth outside the already-shared project; the destination determines persistence |
| `booth exec`, `booth shell` | Runs commands inside the booth — which can change anything |
| `booth message` | Sends a message from the host to the booth's user |
| `booth home-volume-import` / `-export` | Moves a persisted home's contents in or out (experimental) |
| `.booth/.tmp/` | Runtime exchange between host and booth, emptied on every start. It lives under `code/`, so it is listed only to complete the picture |

See [Connect](BOOTH_CONNECT.md), [Message](BOOTH_MESSAGE.md) and [booth tmp](BOOTH_TMP.md).

---

## Choosing One

| You want… | Use |
|---|---|
| A tool or dependency present on every run, identical for everyone | **Built in** — Boothfile, setup, `*-install` extension |
| Team settings that users may then change | `.booth/home-seed/` |
| Team settings that must always apply | `.booth/home/` |
| A team file that is edited inside the booth and committed | **Shared** |
| Personal state kept between runs of this project — history, profiles, tool logins | **Cache** |
| A Cache or Shared path that starts with content, not empty | A seed — `.booth/cache-seed/`, `.booth/shared-seed/` |
| A file copied to a system path, such as `/etc`, on every start | A startup script with `sudo install` ([Copying outside home](#copying-outside-home)) |
| A one-time file transfer between host and an existing booth | [`booth cp`](BOOTH_TOOLS.md#copy-files-outside-the-shared-project) |
| Personal credentials from the host, copied in | `/etc/cb-home-seed/` via a `credential` extension or `--mount …:ro` |
| One host folder reused by every project — a package cache the host already has | **Bind mount** (`java+m2`, `rust+cargo-cache`) |
| One download cache reused by every booth, with no host toolchain | **Named volume** (`go+mod-cache`, `nodejs+npm-cache`, `nodejs+pnpm-cache`, `python+pip-cache`, `python+uv-cache`, `java+gradle-cache`) |
| The whole home kept, without listing paths | `--persist-home` |
| Database data kept between runs | **Named volume** (the database templates) |

Never put a secret in a place that is in git: Shared, `.booth/home-seed/` and `.booth/home/` are
committed. Cache is gitignored, and the booth checks that.

---

## Known Gaps

Found while putting this map together. The shared download caches are in the map above. What follows is still open.

- **Nothing keeps secrets out of Shared.** Cache has a strict gitignore check; Shared has none,
  yet a browser's shared `Default/` folder also holds cookies and saved logins. The sample
  gitignores in [Shared State](BOOTH_SHARED.md#sample-gitignores) must be copied in by hand.
- **A Cache or Shared file with no seed starts empty.** It is mounted over whatever the image put
  at that path, hiding the image's own default. A seed fixes it per path
  ([Initial Content](BOOTH_LOCALCACHE.md#initial-content)); nothing copies the image's file in by
  itself.
- **A single-file mount breaks for a tool that saves by writing a new file and renaming it.** KDE
  is known to fail this way; other `shared-files` entries need checking.
- **Host package caches still follow the host.** `java+m2` and `rust+cargo-cache` bind-mount
  `$HOME/.m2` and `$HOME/.cargo/registry`. The mount is dropped when that folder is missing, and
  a writable mount of a host dot-directory needs consent (`--privileged-allowed` when there is
  no terminal). The named-volume caches above do not.
- **The four startup copy folders reach only `/home/coder`.** There is no folder that copies
  into `/etc` or `/opt` at start; a startup script does it instead
  ([Copying outside home](#copying-outside-home)).

---

Back to [README](../README.md)
