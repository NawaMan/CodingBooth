# Copying and Inspecting Booths

`booth cp`, `inspect`, `stats`, `top`, `diff`, and `wait` select an existing booth and
run its engine's native command. They do not create or start containers.

Back to [README](../README.md)

## Choosing the booth

Inspection commands accept a positional name, `--name`, or `--code`:

```bash
booth inspect                          # name derived from the current directory
booth stats worker --no-stream
booth top --name worker
booth diff --code ~/projects/app
booth inspect worker --engine podman
```

`--code` searches the path recorded when the booth was created. Several matching
booths are an error: choose one with `--name`. With both a name and `--code`, the
named booth must belong to that project. `cp` takes its name from an endpoint or
`--name`, because its two positional arguments are paths.

`--engine docker|podman|apple` overrides config and `CB_ENGINE`. Otherwise these
commands use the existing engine discovery: config under an explicit `--code`,
then `CB_ENGINE`, then all installed engines. A name on several engines requires
an explicit engine. Flags can appear before or after operands; `--` ends flags.

All lifecycle and connection commands also accept `--engine`, including
`list`, `start`, `stop`, `restart`, `remove`, `prune`, `logs`, `shell`, `exec`,
`expose list`, message subcommands, and `home-volume-*`. Home-volume commands
still use a single engine (the default if none was chosen).

## Copy files outside the shared project

Your project is already mounted at `/home/coder/code`. Use `cp` for other paths,
such as `/tmp`, `/home/coder/.config`, `/etc`, or `/opt`:

```bash
booth cp ./settings.json :/tmp/settings.json
booth cp :/tmp/results ./results
booth cp ./custom.conf worker:/etc/myapp/custom.conf
booth cp --name worker ./data/. :/tmp/data/
booth cp --code ~/projects/app :/tmp/report.txt ./report.txt
```

Exactly one endpoint is a booth path: `:PATH` selects the default booth or the
one chosen by flags; `NAME:PATH` names it explicitly. Both host-to-host and
booth-to-booth copies are refused. Conflicting endpoint and `--name` names are
also refused.

Host relative paths start at the current working directory. Container relative
paths start at `/`: `:tmp/file` means `:/tmp/file`, not a path under the project
or home. There is no shell expansion inside the booth: quote spaces, and use
explicit paths rather than remote `~`, variables, or wildcards.

Files overwrite existing files. Directories copy recursively according to the
engine's native rules. Under Docker/Podman, `dir/.` copies the directory's
contents into an existing destination directory. Parent directories must exist.

Use `./file:name` for a local filename containing a colon. Windows drive paths
such as `C:\Users\me\file` and `C:/Users/me/file` stay local; for a one-letter
booth name, use `--name c` with `:/path`. Protect a filename beginning with `-`
using `--`, for example `booth cp -- -settings.json :/tmp/settings.json`.

### Ownership, links, and persistence

Ownership, permissions, and symlinks follow the engine's native defaults.
Docker copy-in creates root-owned files; copying out creates files owned by the
invoking host user. Podman has different ownership and link defaults. Booth does
not run `chown`, create parents, or override these defaults. This first interface
only accepts the selection flags above; it does not expose engine-specific copy
options such as `--archive` or `--follow-link`.

A copy does not configure persistence. Files in the container's writable layer
survive stopping a kept booth, and disappear when that container is removed.
Files copied into a bind mount or named volume follow that storage's lifetime.
See [Persistence](BOOTH_LIFECYCLE.md#persistence-rules).

### Stopped booths and tar streams

Docker and Podman can copy to or from a stopped booth. With those engines, `-`
is a tar stream, not a plain file stream:

```bash
booth cp worker:/tmp/results - > results.tar
booth cp - worker:/tmp/ < results.tar
```

Apple container requires a running booth and a version with `container cp`.
Booth refuses tar-stream copies on Apple. An unavailable native command reports
the engine's error; Booth does not silently switch engines or start the booth.

## Inspect configuration and resource use

```bash
booth inspect worker
booth inspect worker --json
booth inspect worker --format '{{json .Mounts}}'   # Docker/Podman
booth stats worker                               # live, Ctrl+C to finish
booth stats worker --no-stream                    # one sample
booth stats worker --no-stream --format json       # native JSON formatting
booth top worker
booth top worker -- -eo pid,args                   # native process-list options
```

`inspect` prints the engine's complete JSON document by default; `--json` is an
explicit spelling of that default. Its schema is engine-specific, including on
Apple. `--format` is native Docker/Podman formatting and cannot be combined with
`--json`. Apple inspection does not support `--format` here.

`stats` and `top` require a running booth. Stats formats and available metrics
depend on the engine. Arguments after `top --` pass unchanged to the engine's
process listing; Docker's `ps` arguments and Podman's descriptors differ.

## Filesystem changes and exit status

```bash
booth diff worker
booth wait worker
```

`diff` prints paths marked `A` (added), `C` (changed), or `D` (deleted), not content
diffs. It reports the engine's container filesystem changes, not a backup inventory
of the project's bind mounts and volumes. It is useful for spotting manual changes
that should become Boothfile directives or be retrieved with `cp`.

`wait` blocks until the booth stops, then prints its exit code. Like the engine
command, `booth wait` itself exits successfully if waiting succeeds, even when
the printed container exit code is nonzero. A failure of the engine command is
forwarded as the command's exit status. A kept, already-stopped booth answers
immediately; an already-removed booth cannot be queried.

| Command | Docker | Podman | Apple container |
|---|---|---|---|
| `cp` | Running or stopped; tar streams | Running or stopped; tar streams | Running; file/directory paths only |
| `inspect` | Native JSON; `--format` | Native JSON; `--format` | Native JSON |
| `stats` | Running booth | Running booth | Running booth |
| `top` | Native process listing | Native process listing | Refused: no native command |
| `diff` | Native filesystem changes | Native filesystem changes | Refused: no native command |
| `wait` | Native exit wait | Native exit wait | Refused: no native command |

## JSON for scripts

`booth list --json` produces a JSON array, including `[]` when there are no matches.
Each entry contains `name`, `engine`, `state`, `variant`, `code_path`, `port`,
`daemon`, `keep_alive`, and `created_at`. `port` is a string, empty when absent.
Combine with `--running` or `--stopped`; `--name-only` and `--json` are exclusive.

`booth expose list --name worker --json` returns `{ "name": ..., "engine": ...,
"ports": [...] }`. Port entries contain `container_port`, `host_ip`, `host_port`,
`proto`, `kind`, `live`, and `source`; no ports produces an empty array.

These two schemas are Booth's own. Native `inspect` and `stats` output remains
engine-specific. Discovery warnings go to stderr, keeping JSON stdout parseable.

See also [Lifecycle](BOOTH_LIFECYCLE.md), [Connect](BOOTH_CONNECT.md),
[Expose](BOOTH_EXPOSE.md), and [Container engines](BOOTH_ENGINES.md).
