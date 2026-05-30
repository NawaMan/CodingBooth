# Installing and Uninstalling CodingBooth

CodingBooth is not one thing on disk. It is six small things, each with its
own lifecycle. Once you know which one you have a question about, the answer
is short. This document walks through all six from the user's point of view.

## The six layers

| # | Layer                | Lives in                                            | Scope         | Required for          |
|---|----------------------|-----------------------------------------------------|---------------|-----------------------|
| 1 | **Shell function**   | `~/.bashrc`, `~/.zshrc`, `~/.bash_profile`, `~/.profile` | Per user      | Typing `booth` from any subdirectory |
| 2 | **Wrapper**          | `<project>/booth`                                   | Per project   | Bootstrapping a project; downloading the binary |
| 3 | **Binary**           | shared cache **or** `<project>/.booth/tools/`       | Per user *or* per project | Actually running booths |
| 4 | **`.booth/` config** | `<project>/.booth/` (Boothfile, config.toml, generated scripts) | Per project   | Building/running this project's image |
| 5 | **Lock file**        | `<project>/.booth/tools/codingbooth.lock` + `codingbooth.sha256` | Per project   | Pinning which binary version this project uses |
| 6 | **Shared cache**     | `~/.cache/codingbooth/versions/<v>/` (Linux) <br> `~/Library/Caches/codingbooth/versions/<v>/` (macOS) | Per user      | Sharing one downloaded binary across many projects |

The layers stack. The shell function finds the wrapper; the wrapper finds (or
downloads) the binary; the binary reads `.booth/` to know what to build and
run. Each layer can be installed or removed without affecting the others —
except where it would leave an obvious orphan (e.g. removing the wrapper also
removes the shell function that points at it).

---

## 1. Shell convenience (removed)

Earlier versions of the wrapper shipped a `shell-config` subcommand that
installed a `booth()` shell function into your rc files, letting you type
`booth` from any subdirectory. That command has been **removed** — the
wrapper no longer touches `~/.bashrc` or its siblings. Always invoke `./booth`
by path, or write your own three-line shell function if you want a shortcut.

---

## 2. Wrapper (`./booth`)

The wrapper is a tiny shell script that lives at the root of a project. It
downloads the binary on first use, verifies its SHA256, and execs it. Project
wrappers are committed to git so collaborators get the same entry point.

**Install (new project)**

```bash
# Easiest: one-liner that fetches the wrapper, installs the binary,
# and sets up the shell function:
curl -fsSL https://codingbooth.io/install.sh | bash
```

Or from the shell function in a fresh directory:

```bash
cd ~/new-project
booth install        # interactive — prompts before downloading + before binary install
booth install -y     # non-interactive (required when stdin isn't a TTY)
```

`booth install` refuses to clobber if a non-executable file named `booth`
already exists in the current directory.

**Manual install**

```bash
curl -fsSL -o booth https://github.com/NawaMan/CodingBooth/releases/download/latest/booth
chmod +x booth
./booth install
```

**Uninstall**

```bash
booth uninstall --wrapper        # delete ./booth and strip the shell function
rm ./booth                        # just delete the file
```

`--wrapper` also strips the shell function from rc files, because a function
pointing at a deleted wrapper would print the "not found" hint every time
you tab-complete. If you want to keep the shell function for other projects,
use `rm ./booth` directly.

See [docs/implementations/WRAPPER.md](implementations/WRAPPER.md) for the
internals of the wrapper script.

---

## 3. Binary

The binary is the platform-specific Go executable that actually does the
work — building images, running containers, the config TUI. There is exactly
one binary per booth release per platform.

The wrapper picks where to store the binary based on a flag:

- `--cache=shared` (default) → `~/.cache/codingbooth/versions/<v>/` (see layer 6)
- `--cache=local` → `<project>/.booth/tools/`

**Install**

```bash
./booth install                       # shared cache, latest version
./booth install 0.53.0                # shared cache, specific version
./booth install --cache=local         # store in .booth/tools/ instead
./booth install --cache=local 0.53.0
```

If the binary for that version is already present (at the chosen location),
`install` is a no-op.

**Update to a newer version**

```bash
./booth update                # latest
./booth update 0.54.0         # specific version
./booth update-wrapper        # also update the ./booth wrapper script itself
```

**Uninstall**

There is no "uninstall just the binary" command — the binary is tracked
through the lock file (layer 5) and the cache (layer 6). Remove those and the
binary goes with them. Use:

```bash
booth uninstall                       # removes project binary + lock (always)
booth uninstall --shared-binary       # also removes shared-cache copy for this project's pinned version
booth uninstall --all-shared-binary   # also removes every version in the shared cache
booth tools-cache clean               # interactive: pick versions to remove
booth tools-cache clean --all
booth tools-cache clean 0.52.0
```

---

## 4. `.booth/` config directory

`.booth/` is the project's CodingBooth configuration. It holds the Boothfile,
`config.toml`, generated startup scripts, mounted cache directories, and
`.booth/tools/` (where layers 3 and 5 live for `--cache=local` or for the
lock file in either mode).

**Install (create)**

```bash
booth config                      # interactive TUI
booth config --no-tui --select <template-DSL>
booth config --no-tui --overwrite # regenerate from scratch
```

`booth config` is project setup, not booth-tool install. It is safe to run on
a fresh directory or on top of an existing `.booth/` (overwrite confirmations
are per-file).

**Uninstall (delete)**

There is no dedicated uninstall command for `.booth/` because there is no
state outside the directory itself. Delete it directly:

```bash
rm -rf .booth/
```

If you also want to remove the lock file specifically without touching the
rest of `.booth/`, use `booth uninstall` (no flags) — it removes
`.booth/tools/codingbooth.lock`, `codingbooth.sha256`, and project-local
binaries, then `rmdir`s `.booth/tools/` and `.booth/` if they end up empty.

See [BOOTH_CONFIG.md](BOOTH_CONFIG.md) and
[BOOTH_CONFIG_TUI.md](BOOTH_CONFIG_TUI.md) for what `booth config` actually
writes into `.booth/`.

---

## 5. Lock file

`.booth/tools/codingbooth.lock` records which binary version this project
pins. `.booth/tools/codingbooth.sha256` records the expected SHA256 of that
binary. Commit both to git so collaborators get the same version.

```
.booth/tools/
├── codingbooth.lock          # version=0.53.0
├── codingbooth.sha256        # SHA256 of the binary for this platform
└── codingbooth-linux-amd64   # only present with --cache=local
```

**Install**

`./booth install` writes the lock and sha. There is no separate command.

**Uninstall**

```bash
booth uninstall      # default: removes lock, sha, project-local binaries
                     #          (does NOT touch shared cache, wrapper, shell function)
```

This is the "unhook this project from CodingBooth, but leave the tool installed
for other projects" path.

---

## 6. Shared binary cache

The shared cache stores downloaded binaries once per version, so multiple
projects on the same machine don't each have to download their own copy.

| Platform | Path                                                  |
|----------|-------------------------------------------------------|
| Linux    | `${XDG_CACHE_HOME:-~/.cache}/codingbooth/versions/<v>/` |
| macOS    | `~/Library/Caches/codingbooth/versions/<v>/`            |

Override with the `BOOTH_CACHE_DIR` env var.

**Install (populate)**

The cache is populated by `./booth install` (the default `--cache=shared`).
You don't manage it directly.

**Inspect**

```bash
booth tools-cache list           # show cached versions and disk usage
```

**Uninstall**

```bash
booth tools-cache clean          # interactive picker
booth tools-cache clean --all    # remove every cached version
booth tools-cache clean 0.52.0   # remove one version

booth uninstall --shared-binary       # remove only this project's pinned version
booth uninstall --all-shared-binary   # remove every cached version
```

`tools-cache` is the cache-only entry point. `uninstall --shared-binary` is
useful when you're already running uninstall for other reasons and want one
prompt that summarises everything.

---

## Common scenarios

### First-time setup on a new machine

```bash
curl -fsSL https://codingbooth.io/install.sh | bash
# → writes ./booth in $PWD, downloads the binary into the shared cache,
#   adds the shell function to your rc files.
exec $SHELL   # or open a new terminal
booth version
```

### Add CodingBooth to a new project

```bash
cd ~/projects/myapp
booth install -y     # or: booth install (interactive)
booth config         # configure variant, templates, etc.
booth                # run
```

### Update to a newer release

```bash
booth update              # binary only — latest
booth update 0.54.0       # binary only — specific
```

To update the wrapper itself, re-run the installer:
`curl -fsSL https://codingbooth.io/install.sh | bash`.

### Remove CodingBooth from one project but keep using it elsewhere

```bash
cd ~/projects/myapp
booth uninstall          # removes lock + sha + project-local binaries
rm -rf .booth/           # if you also want to throw away the project config
```

The wrapper, shell function, and shared cache stay in place.

### Free disk: drop one cached binary version

```bash
booth tools-cache clean 0.52.0
```

### Free disk: drop every cached binary version

```bash
booth tools-cache clean --all
```

Projects still have their lock files; the next `booth` invocation in each
project will redownload the pinned version into the cache on demand.

### Remove everything CodingBooth

```bash
cd ~/projects/myapp                # any project with a ./booth wrapper
booth uninstall --all -y
# → removes:
#   - project binary association (lock + sha + local binaries)
#   - every cached binary version (shared cache)
#   - ./booth wrapper
#   - shell function from all rc files (because --wrapper implies it)

# Then, if you want the project config gone too:
rm -rf .booth/
```

Restart your shell to pick up the missing function.

---

## Where things live (cheat sheet)

```
~/                                    ← user home
├── .bashrc, .zshrc, .bash_profile, .profile     [layer 1: shell function]
├── .cache/codingbooth/versions/<v>/              [layer 6: shared cache]   (Linux)
└── Library/Caches/codingbooth/versions/<v>/     [layer 6: shared cache]   (macOS)

<project>/                            ← any project
├── booth                             [layer 2: wrapper]
└── .booth/                           [layer 4: project config]
    ├── Boothfile
    ├── config.toml
    ├── startups/, cache/, .tmp/, ...
    └── tools/
        ├── codingbooth.lock          [layer 5: lock file]
        ├── codingbooth.sha256        [layer 5: lock file]
        └── codingbooth-<platform>    [layer 3: binary, only with --cache=local]
```

## Quick reference

| I want to…                                | Command                                     |
|-------------------------------------------|---------------------------------------------|
| Add CodingBooth to my machine             | `curl -fsSL https://codingbooth.io/install.sh \| bash` |
| Add CodingBooth to a new project          | `booth install -y && booth config`          |
| Update the binary                         | `booth update`                              |
| Update the wrapper                        | `curl -fsSL https://codingbooth.io/install.sh \| bash` |
| Detach this project from CodingBooth      | `booth uninstall`                           |
| Drop one cached binary version            | `booth tools-cache clean <version>`         |
| Drop all cached binary versions           | `booth tools-cache clean --all`             |
| Remove the wrapper from this project      | `booth uninstall --wrapper`                 |
| Remove everything                         | `booth uninstall --all -y && rm -rf .booth/` |
