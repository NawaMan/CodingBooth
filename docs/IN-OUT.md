# In and Out of the Booth

> Every way to put something into a booth, or connect it to something, outside `/home/coder/code`.

The project folder is bind-mounted at `/home/coder/code`, so anything in it is already shared with
the host. Everything else in the container is rebuilt from the image on every start, unless one of
the mechanisms below keeps it, puts it there, or connects it. This page lists all of them in one
place, and links to the guide that covers each in depth.

Setups and startup scripts are left out on purpose. They can do anything, so they are not a
mechanism of their own — see [Customization](BOOTH_CUSTOMIZATION.md) and [Setups](BOOTH_SETUP.md).

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
| **Docker storage** | `--persist-home` (one volume per booth); database volumes (one per machine) | — | — | — |
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
| **Named volume** | run-args `-v <name>:<path>` (`postgresql`, `mysql`, `redis`, `mongodb`, `penpot`) | Docker storage → path. The built-in names are fixed, so every project on the machine shares one volume per database |
| `--persist-home` | CLI / `config.toml` | Volume `cb-home-<name>` → the whole of `/home/coder`. Seeding stops after the first run |
| `--tls-cert`, `--tls-key` | CLI | Host files → `/tmp/booth-tls-*.pem`, read-only |
| Devices and GPUs | run-args `--device /dev/kvm`, `--gpus all` | Host hardware → the booth |

Cache and Shared follow the same layout rules: the folder tree mirrors the container's root; a file
is mounted on its own; a folder holding a `.mount-this` marker is mounted whole. Neither may mount
over `/opt/codingbooth` or `/home/coder/code`. Both are mounted whether or not `.booth/` itself is
writable (`--writable-booth`).

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

Every built-in name is **fixed and global**: all projects and booths on the machine that use it
share one volume.

| Volume | Template | Examples using it |
|---|---|---|
| `booth-pgdata` | `middlewares/postgresql` | affine, rails, data, pern, postgrest, `examples/demo` |
| `booth-mysqldata` | `middlewares/mysql` | lamp, lemp, wordpress |
| `booth-mongodata` | `middlewares/mongodb` | mean, mern |
| `booth-redisdata` | `middlewares/redis` | affine |
| `booth-kafkadata` | `middlewares/kafka` | — |
| `booth-rabbitmqdata` | `middlewares/rabbitmq` | — |
| `booth-flocidata` | `tools/floci` | floci |
| `booth-penpot-assets` | `tools/penpot` | — |
| `cb-home-<booth name>` | the CLI, for `--persist-home` | — (one per booth) |

So the six postgres examples share one database, and running two at once opens it twice. Appwrite
is different: its Compose volumes live in its own Docker-in-Docker sidecar, not on the host.

### Adding or changing a named volume

**Adding your own** works on any container path nothing else mounts. Use a name with no `/` as
the source, and Docker creates the volume on the first start:

```bash
booth config --no-tui --select go --mount 'myproj-data:/home/coder/.mydata'
# config.toml:  run-args = ["--volume", "myproj-data:/home/coder/.mydata"]
```

**Replacing a template's volume** is the hard case. Templates write their `-v` into `run-args`
in `.booth/config.toml`:

```toml
run-args = ["-v", "booth-pgdata:/var/lib/postgresql"]
```

To give one project its own database, **edit that line by hand**:

```toml
run-args = ["-v", "myproj-pgdata:/var/lib/postgresql"]
```

Docker creates the new volume on the next start. `booth config` then sees `config.toml` as
hand-edited — see [Hand-Written Files](BOOTH_CONFIG.md#hand-written-files).

The flags do **not** work for this today:

- `booth config --mount 'myproj-pgdata:/var/lib/postgresql'` *adds* a second entry beside the
  template's, and Docker refuses to start with two mounts on one path ("Duplicate mount point").
- `booth config --remove-mount /var/lib/postgresql` only matches mounts added with `--mount`, so it
  reports *did not match anything* and leaves the template's entry in place.

To reset a database instead, remove the volume while no booth uses it:
`docker volume rm booth-pgdata`. Every project that uses that name loses its data.

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
| Personal credentials from the host, copied in | `/etc/cb-home-seed/` via a `credential` extension or `--mount …:ro` |
| One host folder reused by every project — a package cache | **Bind mount** (`--mount ~/.m2:/home/coder/.m2`) |
| The whole home kept, without listing paths | `--persist-home` |
| Database data kept between runs | **Named volume** (the database templates) |

Never put a secret in a place that is in git: Shared, `.booth/home-seed/` and `.booth/home/` are
committed. Cache is gitignored, and the booth checks that.

---

## Known Gaps

Found while putting this map together; none is fixed yet.

- **Database volumes are shared by every project on the machine.** `booth-pgdata` and friends have
  fixed names, so two projects see each other's data, and two booths running at once open the same
  data directory.
- **A template's volume can only be changed by hand-editing `config.toml`.** `--mount` adds a
  duplicate on the same path, and `--remove-mount` does not see template entries. The templates
  already expand `${PARAM}` inside run-args, so the volume name could be a param.
- **Nothing keeps secrets out of Shared.** Cache has a strict gitignore check; Shared has none,
  yet a browser's shared `Default/` folder also holds cookies and saved logins. The sample
  gitignores in [Shared State](BOOTH_SHARED.md#sample-gitignores) must be copied in by hand.
- **`shared-files` starts as an empty file.** It is mounted over whatever the image put at that
  path, so the image's defaults (code-server's `settings.json`, for one) are probably hidden.
- **A single-file mount breaks for a tool that saves by writing a new file and renaming it.** KDE
  is known to fail this way; other `shared-files` entries need checking.
- **Package caches are uneven.** Only Java (`+m2`) and Rust (`+cargo-cache`) have a host-cache
  extension. They depend on the host's folder layout and are dropped when that folder is missing.
- **Overlapping Cache and Shared paths are not detected** — e.g. `+profile-cache` with
  `+bookmarks-shared`.
- **Copies reach only `/home/coder`.** Nothing copies into `/etc` or `/opt` at start, though Cache
  and Shared can mount there.
- **Template `[files]` cannot fill Cache or Shared** — only `home`, `home-seed` and `setups`.
- **There is no `booth cp`** to drop a file into a running booth outside `code/`.
- **Two front doors to one bind mount.** `--mount` and run-args `-v` produce the same `-v` but are
  edited in different places.

---

Back to [README](../README.md)
