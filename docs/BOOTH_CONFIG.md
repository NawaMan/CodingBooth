# booth config

> One command. A fully configured development environment.

`booth config` creates a complete `.booth/` configuration — Boothfile, config, startup scripts — from templates. Browse and select interactively via the TUI, or use `--no-tui` for scripting. Users can add their own startup scripts to `.booth/startups/` that survive re-generation. No manual Dockerfile writing required.

```bash
# Interactive TUI
./booth config

# CLI mode
./booth config --no-tui --select go+linter/python:3.13+uv/claude-code
```

For the full TUI guide, see **[booth config — Interactive Configuration](BOOTH_CONFIG_TUI.md)**.

Back to [README](../README.md)

---

## Table of Contents

- [Overview](#overview)
- [Modes](#modes)
- [Selection DSL](#selection-dsl)
- [Selection Sources](#selection-sources)
- [Flags](#flags)
- [Setting config values](#setting-config-values)
- [Browsing Templates](#browsing-templates)
- [What Gets Generated](#what-gets-generated)
- [Hand-Written Files](#hand-written-files)
- [Run-Args Ownership Convention](#run-args-ownership-convention)
- [Common Workflows](#common-workflows)
- [Package Management Templates](#package-management-templates)
- [Editor Extensions](#editor-extensions)
- [Binary companions — library X → also select Y](#binary-companions--library-x--also-select-y)

---

## Overview

Setting up a CodingBooth environment means creating a `.booth/` folder with a Boothfile, config.toml, and possibly startup scripts. For a simple single-language project this is straightforward, but for a polyglot project with multiple languages, AI tools, and IDE extensions, writing it all by hand is tedious.

`booth config` solves this with template-driven scaffolding. You select what you need — languages, tools, extensions — and config compiles everything into a ready-to-use `.booth/` configuration. Templates encode best practices (correct ordering, proper arguments, volume persistence) so you get a working environment without needing to understand every detail.

For more information on how setup scripts are generated and structured, see the **[Booth Setup Guide](BOOTH_SETUP.md)**.

---

## Modes

### TUI mode (default)

Opens an interactive terminal interface for browsing templates and configuring your booth. This is the default when you run `booth config`.

```bash
# Open TUI from scratch
./booth config

# Open TUI with templates pre-selected
./booth config --select go+linter --variant codeserver

# Edit an existing booth — reads .booth/Boothfile and pre-populates the TUI
./booth config ./existing-project
```

See **[booth config — Interactive Configuration](BOOTH_CONFIG_TUI.md)** for the full TUI guide.

### CLI mode (`--no-tui`)

Non-interactive mode for scripting and quick setup.

```bash
# Create a new booth configuration
./booth config --no-tui --select python+uv

# In a target directory
./booth config --no-tui ../my-project --select go+linter/python:3.13+uv

# Empty booth in a fresh directory (no templates, just CLI overrides)
./booth config --no-tui --variant codeserver --port 10080
```

If files config generated earlier already exist, it prompts for confirmation before overwriting them. Use `--overwrite` to skip the prompt.

If the Boothfile or config.toml is **hand-written**, config refuses outright rather than prompting — re-generating would destroy work it cannot reproduce. See [Hand-Written Files](#hand-written-files).

### Reconfiguring an existing booth

Both modes read an existing `.booth/` as their **baseline**, and the flags of this
run override it. The baseline comes from the `# Configured by:` header in
`.booth/Boothfile` (the selection, `--variant`, `--port`, `--cmd`, `--set`) and
from `.booth/config.toml` (the long-form `--env` / `--volume` / `--publish`
run-args, plus `cache-files` / `cache-dirs`).

So a reconfigure only has to state what changes:

```bash
# Add an extension. The variant, ports, envs, mounts and version pins all stay.
./booth config --no-tui --overwrite --select go+linter/python:3.13+uv
```

Omitting a flag **keeps** the recorded value; restating a list flag (`--env`,
`--mount`, `--expose`) **replaces** the whole list rather than adding to it —
which is how an entry is removed:

```bash
# Was: --env FOO=1 --env BAR=2. Now only BAR survives.
./booth config --no-tui --overwrite --env BAR=2
```

The flags that steer the run itself — `--overwrite`, `--beside`, `--dryrun`,
`--start` — are never inherited from the header, even though the header records
the `--overwrite` used to write it. Each run decides those for itself.

To start over rather than reconfigure, delete `.booth/` first.

### Dryrun

Preview what would be generated without writing any files. Works in both modes.

```bash
# CLI dryrun
./booth config --no-tui --dryrun --select go+linter/python:3.13

# TUI dryrun — opens TUI, prints output on confirm instead of writing files
./booth config --dryrun --select go+linter
```

---

## Selection DSL

The `--select` flag accepts a mini-language for specifying templates, versions, extensions, and exclusions.

### Templates

Separate multiple templates with `/`:

```
go/python/claude-code
```

### Version parameters

Append `:` to set a template's version parameter:

```
python:3.13
go:1.25
java:21
```

Multiple parameters use commas: `java:21,temurin`. Comma values are positional —
`playwright:chromium,1.58.2` sets the browsers (`PLAYWRIGHT_BROWSERS=chromium`)
and the Playwright package version (`PLAYWRIGHT_VERSION=1.58.2`). Pin the
Playwright version so the pre-baked browsers match the Playwright that `npm ci`
installs at runtime; it defaults to `latest`.

Version parameters compile to `arg NAME=VALUE` lines in the generated Boothfile
(e.g. `python:3.13` → `arg PYTHON_VERSION=3.13`). These pins are **preserved
across re-generation**: re-running `booth config --overwrite` to add or remove an
unrelated template keeps every non-default pin already in the Boothfile, unless
the new selection explicitly overrides it (an explicit `:value` always wins). So
adding a template no longer silently resets a pinned `NODE_VERSION`,
`PLAYWRIGHT_VERSION`, etc. back to its template default. The TUI likewise
pre-loads the real pinned values from the existing Boothfile into its param
fields.

A param whose default follows another param (see [Ports](#ports-which-knob-moves-what))
is **not** preserved this way when its value was merely derived. `arg` lines hold
resolved values, so a followed host port reaches the Boothfile as a number and cannot be
told from a pin by comparing it to `"${SVC_PORT}"`. The old value is re-resolved against
the Boothfile's own args to reconstruct what the default came to last time: a match is
derived and re-derives from the new selection, anything else is a real choice and
survives. So re-configuring `openssh+server:2200+expose` to `openssh+server:22+expose`
publishes `22:22`, while a pinned `+expose:2222` still publishes `2222` afterwards.

### Extensions

Append `+` to add extensions:

```
python+uv+pip+kernel
go+linter+vscode-ext
java+maven+lombok
```

Extensions take parameters the same way templates do — positionally, after `:`. The
service port and the port it is published on are separate params, and they compose:

```
openssh+server:2200+expose          # sshd on 2200, published on 2200
openssh+server:22+expose:2222       # sshd on 22, published on 2222
rabbitmq+start+expose:15672,25672   # AMQP on 15672, management UI on 25672
rabbitmq+start+expose:+4567         # AMQP published on offsetBase + 4567
```

### Ports: which knob moves what

Every service has exactly one param for the port it *listens* on, and its `expose`
extension has one for the *host* port it is published on. The host port defaults to
`"${SERVICE_PORT}"` — a reference, not a copy — so moving the service moves the
published port with it, and the two cannot drift apart:

| Selection | Publishes |
|---|---|
| `cloudbeaver+expose` | `8978:8978` |
| `cloudbeaver:25.3.5,9000+expose` | `9000:9000` — host follows the service |
| `cloudbeaver:25.3.5,9000+expose:19000` | `19000:9000` — host overridden alone |
| `cloudbeaver+expose:+8978` | `28978:8978` — host relative to an offset base of 20000 |

Override the host port only when the host port is taken but the booth's should not
move. The databases whose server has no port param of its own (`postgresql`, `mysql`,
`redis`, `mongodb`, `nginx`, `apache` — each listens on its stock port inside the
container) have only the host-side knob, on the `expose` extension.

#### Booth-relative host ports

A host port written as `+OFFSET` is **relative to the offset base**: it stays literal in
`run-args` and is resolved at container start as `offsetBase + OFFSET`. The base is the
**booth port** unless the booth sets one of its own — see *Moving the base* below. With a
booth port of 20000 and no base set, `rabbitmq+start+expose:+4567` writes `"-p",
"+4567:5672"` and publishes AMQP on `24567`. A bare number is still an absolute host port —
the `+` is what makes it relative.

This is the same `+OFFSET` form `--expose +4567:5672` and hand-written `run-args` already
use; the offset belongs on the **host** side only. Because it derives from the booth port,
two booths of the same project on different ports no longer collide on published ports.

##### Moving the base

`--offset-base <n>` (also `CB_OFFSET_BASE`, or `offset-base` in `config.toml`) decides what
`+OFFSET` counts from, without touching the booth port. Following the booth port is the
right default when several booths share a host and their published ports have to stay out
of each other's way. It is the wrong one for a booth that owns the machine: there the port
range is all its own and the front door sits wherever the platform put it, so services
should count from a base you chose.

```bash
booth --port 443 --offset-base 20000   # front door on 443, +4567 publishes on 24567
booth --offset-base 0                  # +8090 publishes on 8090 — offsets are absolute
```

A base of `0` is legal (a booth *port* of 0 is not) and is the way to make a config written
in offsets publish at stock ports unchanged. The duplicate-host-port check below runs after
resolution either way, so a moved base that lands a service on the booth's own port is
still refused rather than handed to docker.

The `+` survives the selection DSL even though `+` also separates extensions: inside a
param list, a `+` starts an extension only when followed by a letter, and names are never
digit-initial. So `expose:+4567+start` is a relative port *and* a `+start` extension.

#### Host-env host ports

A host port written as `${NAME}` or `${NAME:-digits}` is expanded from the **host
environment at booth start** (see [Booth Variable Expansion](BOOTH_VARS.md)). The
expression is stored literally in `run-args`; only the host side may use it — the
container port stays a number.

```text
postgresql+expose:${POSTGRES_PORT:-15432}     # -p ${POSTGRES_PORT:-15432}:5432
--expose '${SERVER_PORT:-12345}:1234'         # free-form publish
--expose '${APP_PORT:-3000}'                  # bare → HOST:HOST
```

Quote the value so your shell does not expand it at config time. At start:

```bash
booth                          # host 15432 → container 5432
POSTGRES_PORT=25432 booth      # host 25432 → container 5432
```

**The fallback itself may be base-relative.** Write `${NAME:-+OFFSET}` and the
default is not a fixed number but `offsetBase + OFFSET` — the env var wins when set,
otherwise the port follows the base, which is the booth port unless `--offset-base`
moved it (the two host-side forms composed):

```text
--expose '${SERVER_PORT:-+300}:1234'   # SERVER_PORT if set, else offsetBase+300
```

```bash
booth --port 10000             # host 10300 → container 1234
SERVER_PORT=25000 booth        # host 25000 → container 1234
```

A `+OFFSET` fallback needs an explicit `:CONTAINER`; the bare `HOST:HOST` shorthand
cannot carry an offset on the container side, so `--expose '${SERVER_PORT:-+300}'`
is rejected. This works because `${…}` is expanded (at TOML unmarshal) *before*
`+OFFSET` is resolved against the offset base — expansion yields `+300:1234`, then
the offset step rewrites it.

Three knobs, three jobs. The **booth port** (`--port` / `CB_PORT`) moves the primary
UI mapping, not every service publish. The **offset base** (`--offset-base` /
`CB_OFFSET_BASE`) moves what every `+OFFSET` counts from, without touching the booth
port. And a **host-env port** overrides one service alone. So: to follow the base,
use `+OFFSET`; to override one service's host port from the environment, use
`${NAME:-digits}`; to do both — env override with a base-relative default — use
`${NAME:-+OFFSET}`.

A param default may reference another param by name (`default = "${SVC_PORT}"`), and
references are resolved before anything consumes them, including transitively. A
circular reference is a config-time error. A `${NAME}` that is not a param — `${HOME}`,
or a host-env port like `${SERVER_PORT:-12345}` — is left alone for expansion at runtime.

### `--expose` is instead of `+expose`, not alongside it

`--expose` **adds** a mapping; it does not replace what the `+expose` extension
contributes. Selecting `cloudbeaver+expose` *and* passing `--expose 19000:8978` publishes
container port 8978 twice — on 8978 *and* on 19000 — and the first one stays bound, which
is the port you were presumably trying to get off. `booth config` says so:

```
Note: a selected template already publishes container port 8978 as "8978:8978".
      --expose 19000:8978 adds a second mapping; it does not move the first, which stays bound.
      To move it, give the expose extension the host port instead (e.g. +expose:19000).
```

Use `+expose:19000` to move the host port. Reach for `--expose` only for what the
extension cannot express: IP binding (`--expose 127.0.0.1:19000:8978`), or publishing a
port no template owns.

### One host port, one mapping

Docker cannot bind a host port twice — it fails the container with `address already in
use` — so a config that publishes one twice never starts. Two spellings of the same
mapping are **collapsed** rather than published twice, whether they came from a template
plus a `--expose` (`cloudbeaver+expose --expose 8978:8978`) or from two templates whose
ports resolve alike (`nginx+expose/apache+expose`, both `8080:80`). The user-owned
`--publish` is the form kept, since that is the one re-read into `--expose` on
reconfigure.

Anything that genuinely *cannot* bind is refused at start, naming both mappings, rather
than left to docker's `driver failed programming external connectivity`:

```
Error: host port 8978 is published twice — "8978:8978" (run-args) and "8978:9000" (run-args).
```

That check runs after `+OFFSET` resolution, so it catches an offset that lands on an
absolute mapping (`-p 28978:8978` next to `-p +8978:9000` on a booth at 20000), and it
includes the booth's own port — publishing over it is refused too. Publishing one
*container* port on two different host ports is legal in docker, so it is left alone.

### Excluding auto-selected extensions

Use `~` to exclude extensions that would otherwise be auto-selected:

```
firebase~credential
```

### Putting it together

```
go:1.25+linter+vscode-ext/python:3.13+uv+kernel/notebook/claude-code
```

This selects:
- Go 1.25 with linter and VS Code extension
- Python 3.13 with uv, and Jupyter kernel
- Notebook variant
- Claude Code AI assistant

### Quoting values that contain separators

A param value that holds a `/` has to be quoted, or the `/` starts a new
template. Go module paths are the usual case:

```bash
# Right
booth config --no-tui --select 'go+go-pkg:"github.com/fullstorydev/grpcurl/cmd/grpcurl@latest"'

# Wrong — selects go, then templates named "fullstorydev", "grpcurl", "cmd", …
booth config --no-tui --select go+go-pkg:github.com/fullstorydev/grpcurl/cmd/grpcurl@latest
```

The ambiguity is real, not an oversight: `go:1.25.7/claude-code` has the same
shape, and there the `/` genuinely does separate two templates. Quotes are how
you say which one you mean.

Either `"` or `'` works — pick the one that gets past your shell. Wrapping the
whole selection in single quotes and using `"` inside, as above, is the form
`booth config` writes into the generated headers.

Each value in a list is quoted on its own; the commas between them still
separate:

```bash
booth config --no-tui --select 'nodejs+npm-pkg:"@types/node","@types/react"'
```

Only param values are quotable — template and extension names never need it.
And only values that need it: `go:1.25.7`, `cloudbeaver+expose:+19000` and
`apt+apt-pkg:libstdc++6` all stay plain, because a `+` inside a param list
already stays with the value unless a letter follows it, and only the first `:`
of an item separates (`deno+deno-pkg:jsr:@luca` needs nothing).

### Whitespace rules

For readability in files and heredocs:
- Spaces around `+` and `~` are allowed: `java + maven` works
- Lines starting with `+` or `~` continue the previous template
- Remaining whitespace becomes `/` separators
- Whitespace inside a quoted value is part of the value

---

## Selection Sources

| Source           | Syntax        | Example                                      |
|------------------|---------------|----------------------------------------------|
| Inline           | Direct string | `--select go+linter/python:3.13`             |
| Multiple flags   | Repeated      | `--select go+linter --select python:3.13`    |
| Project recipe   | `@name`       | `--select @fullstack` → `.booth/recipes/fullstack.recipe` |
| Path             | `@/…` `@./…` `@~/…` | `--select @./shared/stack.recipe`      |
| URL              | `@@url`       | `--select @@codingbooth.io/r.recipe` (HTTPS if no scheme) |
| Stdin            | `-`           | `--select -` (type or pipe)                  |

Recipe files are plain text with the same DSL syntax — one template per line.
Bare `@name` looks under the config target’s `.booth/recipes/` (`.recipe` is
appended when missing). Path-shaped refs and `@@` URLs bypass that directory.
Project templates under `.booth/templates/` are merged into the catalog
automatically (local name overrides stock with a warning).

---

## Flags

| Flag                       | Description                                                    |
|----------------------------|----------------------------------------------------------------|
| `--select <dsl>`           | Template selection (repeatable)                                |
| `--no-tui`                 | Non-interactive CLI mode                                       |
| `--dryrun`                 | Preview what would be generated without writing files           |
| `--variant <name>`         | Set variant (default, console, terminal, base, notebook, codeserver, xfce, kde) |
| `--port <port>`            | Set port in generated config.toml (number, NEXT[:base], RANDOM[:base]) |
| `--cmd <command>`          | Set the default start command (repeatable)                     |
| `--expose <port>`          | Expose extra port (HOST:CONTAINER, +OFFSET, or host-side `${NAME:-digits}`; produces long-form `--publish` in run-args; repeatable) |
| `--env <KEY=VALUE>`        | Set container environment variable (produces long-form `--env` in run-args to distinguish from template-contributed `-e`; repeatable) |
| `--mount <host:container>` | Mount volume (produces long-form `--volume` in run-args to distinguish from template-contributed `-v`; repeatable) |
| `--set <key=value>`        | Set a config.toml value (repeatable; bare key = boolean true). See [Setting config values](#setting-config-values) |
| `--version <ver>`          | Use templates from a specific release version                  |
| `--templates-path <dir>`   | Use local templates directory                                  |
| `--overwrite`              | Overwrite existing files without prompting — including [hand-written](#hand-written-files) ones, which are kept as `<name>.bak` (`--no-tui` only) |
| `--beside`                 | Keep [hand-written](#hand-written-files) files; write the generated content next to them as `<name>.new` to merge by hand (`--no-tui` only) |
| `--start`                  | Launch the booth immediately after config                      |
| `--debug`                  | Print resolved selection and compiled output as JSON           |

---

## Setting config values

`--set` writes a key into the generated `config.toml`. The value is written in the
shape that key expects, so it lands in the booth as the right type:

```bash
booth config --no-tui --select go \
    --set persist-home \                # bare key → boolean true
    --set keep-alive=false \            # explicit boolean
    --set timezone=Asia/Bangkok \       # string
    --set idle-time=30 \                # integer — written unquoted
    --set egress-allowlist=example.com  # list — repeat the flag to add more
```

A bare key means "turn this on", which only reads as an intent for a boolean —
`--set timezone` is an error, not an empty string.

### Keys are checked

Only keys booth actually reads are accepted. A typo is refused up front rather than
written into `config.toml` and silently ignored at every start afterwards:

```
Error parsing --set: unknown --set key "persist-hom": booth does not read that from config.toml
       Did you mean "persist-home"?
```

The same applies to the value's type — `--set idle-time=soon` is refused, because an
integer key holding a string produces a `config.toml` booth cannot load at all.

### Exposure and TLS are start-time only

`public`, `tls-cert` and `tls-key` are **not** config.toml settings. They are real —
`booth --public --tls-cert cert.pem --tls-key key.pem` binds the booth on all
interfaces behind a password over HTTPS — but booth reads them only as flags, never
from a file, so they are not something `booth config` can store:

```bash
booth --public                                   # this works
booth config --no-tui --set public               # this does not — warns, and is ignored
```

That is deliberate. `config.toml` is committed, so a stored `public = true` would
expose the booth on every machine that clones the project, while the password it
requires lives in `.booth/.booth.password`, which is gitignored and therefore absent
for everyone but you.

`booth config` has no fields for these, and a value recorded by an older version is
dropped on the next reconfigure with a note.

---

## Browsing Templates

Use `booth template` to explore what's available before running init.

```bash
# List all primary templates
./booth template list

# Search by name, description, or tag
./booth template search python

# Show detailed info (parameters, extensions, tags)
./booth template show go

# Show extension details
./booth template show python+uv

# Show file and segment contents
./booth template show go --detail

# Show raw template code
./booth template cat go
```

Use `--full` with `list` or `search` to include secondary (non-primary) templates.

There are **190+ templates** across 7 categories: languages, ai-tools, tools, IDEs, desktops, databases, and browsers.

---

## What Gets Generated

`booth config` creates a `.booth/` directory with the following structure:

```
.booth/
├── config.toml      # Runtime configuration (variant, port, run-args, etc.)
├── Boothfile        # Build instructions (compiled from templates)
├── startups/        # Startup scripts (one per template segment, plus user scripts)
│   ├── 10-claude-code-auto-accept--startup.sh   # Generated from template
│   ├── 50-my-custom--startup.sh                 # User-added (survives adjust)
│   └── 65-excalidraw-autostart--startup.sh      # Generated from template
├── .gitignore       # Protects .booth.password, .env, and .bak/.new merge artifacts
├── .generated       # Fingerprints of the files above (see Hand-Written Files)
├── setups/          # Custom setup scripts from templates
├── home/            # Home directory team files
└── home-seed/       # Home directory defaults
```

### Startup scripts

Template-generated startup segments are written as individual files in `.booth/startups/`, named `NN-name--startup.sh` where `NN` is the order number.

**Adding your own startup scripts:** Create files matching the `*--startup.sh` pattern in `.booth/startups/`. Files without a `NN-` prefix default to order 50. User-added files (without the `# Generated by:` header) survive re-generation.

**Execution order:** At container start, all `*--startup.sh` files in `startups/` are sourced in sorted order. Files without a number prefix are treated as order 50.

**Legacy:** If `.booth/startup.sh` exists (from older configurations), it is still executed after `startups/` scripts for backward compatibility.

Generated files include a header comment showing the exact command used and an `adjust` command for easy re-generation:

```bash
# Generated by: booth config --no-tui --select go/python
# Adjust with : booth config --no-tui --overwrite --select go/python
```

---

## Hand-Written Files

`booth config` regenerates `.booth/Boothfile` and `.booth/config.toml` **from scratch** every time it writes — it does not edit them in place. Anything a human put in them by hand is therefore something config cannot reproduce from your selection, and re-generating would destroy it.

So it doesn't. Config first works out whether it is looking at its own output or yours.

### How it knows

Every time config writes those two files, it records a SHA-256 fingerprint of exactly what it wrote in `.booth/.generated`. On the next run it re-hashes what is on disk and compares:

| State | Meaning | What happens |
|-------|---------|--------------|
| Fingerprint matches | Config wrote it, nobody has touched it | Regenerated freely |
| Fingerprint differs | Config wrote it, then a human edited it | **Protected** |
| No fingerprint, but a `# Configured by:` header | Generated before `.generated` existed | Adopted — regenerated freely, and fingerprinted from now on |
| No fingerprint, no header | Hand-written from the start | **Protected** |

The `# Configured by:` header alone is not enough to decide this: it survives a hand-edit, so a file can carry the header and still be full of someone's own work. Only the fingerprint distinguishes "still ours" from "someone has been here."

`.booth/.generated` is committed alongside the Boothfile — drift detection has to survive a clone. Delete it and config will treat those files as hand-written again.

### The two ways through

When a file is protected, you choose what happens to it. Nothing is decided until you do.

**Keep yours** — the generated content is written next to your file as `<name>.new` and your file is not touched. You merge the two by hand. Same idea as `pacnew` / `rpmnew` / `dpkg-dist`.

```bash
./booth config --no-tui --beside --select go+linter

# → .booth/Boothfile      unchanged (yours)
#   .booth/Boothfile.new  what config would have written
diff .booth/Boothfile .booth/Boothfile.new
```

The kept file stays protected until you actually merge it — writing `.new` does not bless your file as config's own.

**Replace yours** — your file is replaced, and the original is kept as `<name>.bak`.

```bash
./booth config --no-tui --overwrite --select go+linter

# → .booth/Boothfile      regenerated
#   .booth/Boothfile.bak  what was replaced
```

With neither flag, config refuses and tells you both options. The rest of `.booth/` (`setups/`, `startups/`, `home/`, `cache/`) is written normally either way, so merging the `.new` file is all that remains to complete the reconfigure.

`.bak` and `.new` are gitignored — they are merge scratch, not configuration.

### In the TUI

The TUI warns as soon as it opens, so you find out before configuring rather than after:

```
┌──────────────────────────────────────────────────┐
│                   ⚠ Warning                      │
│                                                  │
│ This booth contains hand-written files:          │
│                                                  │
│   .booth/Boothfile                               │
│                                                  │
│ Nothing is decided yet. When you save, you       │
│ choose ...                                       │
│                                                  │
│ Go on in and look around — nothing is touched    │
│ until you save.                                  │
│                                                  │
│        Enter/Space: continue  │  Esc: quit       │
└──────────────────────────────────────────────────┘
```

It is a heads-up, not a blocker — press Enter and configure as normal. On save, `Ctrl+S` raises the choice: **Enter** keeps your files and writes `.new` beside them, and typing `overwrite` replaces them. See [BOOTH_CONFIG_TUI.md](BOOTH_CONFIG_TUI.md#saving-over-hand-written-files).

---

## Run-Args Ownership Convention

Templates and users both contribute `run-args` to `config.toml`, but they use different flag forms to signal ownership.

### Short-form = template-owned

Templates use short-form Docker flags in their run-args contributions:

- `-e KEY=VALUE` (environment variable)
- `-v host:container` (volume mount)
- `-p hostPort:containerPort` (port mapping)

These are added automatically when a template is selected and are considered template-owned.

### Long-form = user-owned

Values set via `--env`, `--expose`, and `--mount` CLI flags (or the TUI input fields) produce long-form Docker flags:

- `--env KEY=VALUE`
- `--volume host:container`
- `--publish hostPort:containerPort`

These are considered user-owned.

### Docker treats both identically

Docker does not distinguish between `-e` and `--env`, or `-v` and `--volume`, or `-p` and `--publish`. The container behavior is the same regardless of which form is used. The distinction is purely a convention within CodingBooth.

### How the TUI uses this convention

When you re-open `booth config` on an existing project, the TUI reads `config.toml` and parses `run-args`. Only long-form flags (user-owned) appear in the Expose, Env, and Mount input fields. Template-contributed short-form flags are invisible in the TUI because they are automatically re-added when the corresponding template is selected.

This means users only see and edit their own overrides. Template values are managed by the template selection itself.

### Example config.toml with mixed forms

```toml
run-args = [
    "-e", "PYTHONDONTWRITEBYTECODE=1",           # short-form: added by python template
    "-p", "2222:2222",                            # short-form: added by openssh template
    "--env", "MY_APP_ENV=development",            # long-form: user-set via --env
    "--volume", "/host/data:/container/data",     # long-form: user-set via --mount
    "--publish", "3000:3000",                     # long-form: user-set via --expose
]
```

When this config is loaded in the TUI:
- The Env field shows `MY_APP_ENV=development`
- The Mount field shows `/host/data:/container/data`
- The Expose field shows `3000`
- The template-contributed `-e` and `-p` entries do not appear in the fields

---

## Common Workflows

### Quick single-language project

```bash
./booth config --no-tui --select python+uv
./booth
```

### Polyglot project with IDE

```bash
./booth config --no-tui --select go+linter/python:3.13+uv --variant codeserver
./booth
```

### Data science environment

```bash
./booth config --no-tui --select python:3.13+uv+kernel/notebook/postgresql
./booth
```

### Full desktop with AI tools

```bash
./booth config --no-tui --select java:21+maven/claude-code --variant desktop-xfce
./booth
```

### Project with extra ports, env vars, and mounts

```bash
./booth config --no-tui --select nodejs --expose 3000 --env NODE_ENV=development --mount /data:/app/data
./booth
```

### Using a recipe file

Create `<project>/.booth/recipes/my-project.recipe` (or any path-shaped `@` ref):

```
go:1.25
  + linter
  + vscode-ext

python:3.13
  + uv
  + kernel

notebook
claude-code
```

Then:

```bash
./booth config --no-tui ./my-project --select @my-project
# or: --select @./path/to/my-project.recipe
```

### Re-generate after adding a template

```bash
./booth config --no-tui --overwrite --select go+linter/python:3.13+uv/postgresql
```

Version pins already in the Boothfile are carried over — you don't need to
re-specify `nodejs:22` or `playwright:chromium,1.58.2` just because you're adding
`postgresql`. See [Version parameters](#version-parameters).

### Interactive configuration

```bash
./booth config
```

---

## Package Management Templates

CodingBooth templates include two types of package management extensions: **global tool installation** and **project dependency pre-installation**.

### Global Package Installation

Install tools globally into the image at build time using `install <manager> <packages>`. These are available via variadic parameter extensions:

```bash
# Install global npm packages
booth config --no-tui --select nodejs+npm-pkg:pnpm,typescript

# Install global pip packages
booth config --no-tui --select python+pip-pkg:numpy,pandas

# Install global cargo crates
booth config --no-tui --select rust+cargo-pkg:ripgrep,fd-find
```

The full list of package manager extensions:

| Extension          | Manager    | Example                            |
|--------------------|------------|------------------------------------|
| `nodejs/npm-pkg`   | npm        | `nodejs+npm-pkg:pnpm,typescript`   |
| `nodejs/yarn-pkg`  | yarn       | `nodejs+yarn-pkg:create-react-app` |
| `bun/bun-pkg`      | bun        | `bun+bun-pkg:elysia`              |
| `python/pip-pkg`   | pip        | `python+pip-pkg:numpy,pandas`      |
| `python/uv-pkg`    | uv         | `python+uv-pkg:ruff,black`        |
| `python/conda-pkg` | conda      | `python+conda-pkg:scipy`          |
| `rust/cargo-pkg`   | cargo      | `rust+cargo-pkg:ripgrep`          |
| `go/go-pkg`        | go install | `go+go-pkg:gopls@latest`          |
| `csharp/dotnet-pkg`| dotnet tool| `csharp+dotnet-pkg:dotnet-ef`     |
| `dotnet/dotnet-pkg`| dotnet tool| `dotnet+dotnet-pkg:dotnet-ef@8.0.11` |
| `ruby/gem-pkg`     | gem        | `ruby+gem-pkg:rails,bundler`      |
| `haskell/cabal-pkg`| cabal      | `haskell+cabal-pkg:hlint`         |
| `elixir/hex-pkg`   | hex        | `elixir+hex-pkg:phoenix`          |
| `lua/luarocks-pkg` | luarocks   | `lua+luarocks-pkg:luacheck`       |
| `php/pecl-pkg`     | pecl       | `php+pecl-pkg:redis`              |
| `deno/pkg`         | deno add   | `deno+pkg:npm:cowsay`             |
| `deno/tool`        | deno install | `deno+tool:npm:cowsay`          |
| `conan/conan-pkg`  | Conan      | `conan+conan-pkg:"fmt/10.2.1"`    |
| `brew-pkg`         | Homebrew   | `brew-pkg:htop,tmux`              |
| `apt-pkg`          | apt        | `apt-pkg:htop,jq`                |
| `code-ext-pkg`     | VS Code / code-server | `code-ext-pkg:elixir-lsp.elixir-ls` |
| `jetbrains-plugin-pkg` | JetBrains IDEs | `jetbrains-plugin-pkg:IdeaVIM`    |

These translate to `install <manager> <packages>` in the Boothfile, which runs the corresponding `<manager>--install.sh` script during `docker build`.

> **Package names with a `/`** — Go module paths, scoped npm names, Conan
> `name/version` refs — must be quoted, or the `/` reads as a template separator:
> `--select 'go+go-pkg:"github.com/user/tool@latest"'`. See
> [Quoting values that contain separators](#quoting-values-that-contain-separators).

> **Editor extensions (`code-ext-pkg`):** bakes any VS Code / code-server extension
> into the image by marketplace id, for anything the curated per-language extensions
> don't cover. See [Editor Extensions](#editor-extensions) below.

> **IDE plugins (`jetbrains-plugin-pkg`):** the same idea for the JetBrains IDEs —
> bakes any plugin from plugins.jetbrains.com into the image. See
> [JetBrains IDE Plugins](#jetbrains-ide-plugins) below.

> **System packages (apt):** `apt-pkg` installs Debian/Ubuntu packages with apt. It supports apt's native `pkg=version` pinning (`apt-pkg:htop,jq=1.6-2.1`) and honors the `APT_SNAPSHOT` archive freeze that `booth config` stamps for reproducible builds. You can also add `install apt <pkgs>` directly to the Boothfile by hand. See [BOOTH_CUSTOMIZATION.md](BOOTH_CUSTOMIZATION.md#using-built-in-installs) and [REPRODUCIBILITY.md](REPRODUCIBILITY.md#apt--pin-the-snapshot-not-the-package).

> **Upgrading the bundled npm (`nodejs+npm-upgrade`):** distinct from the `-pkg` extensions, this opt-in extension upgrades the *global npm itself* to a newer version than the selected Node.js bundles — `run npm install -g npm@NPM_VERSION` at build time. Use `--select nodejs+npm-upgrade` for the latest, or `nodejs+npm-upgrade:11.18.0` to pin a version. It's off by default so the npm that ships with Node.js stays the reproducible baseline.

### Editor Extensions

VS Code / code-server extensions come two ways, and the curated way is the one to
reach for first.

**Curated, per language — `<language>+vscode-ext`.** Each language template that has
a well-known extension ships one, auto-selected, pinning an id that is known to
resolve. Nothing to type but the language:

```bash
booth config --no-tui --variant codeserver --select "elixir"          # +vscode-ext is auto-selected
booth config --no-tui --variant codeserver --select "go/rust/python"  # one per language
```

Each compiles to `setup <language>-code-extension` in the Boothfile. If an editor
isn't in the image, the setup skips itself quietly, so a language selection stays
valid on a variant with no IDE.

**Arbitrary, by id — `code-ext-pkg`.** For anything not covered by a curated
extension, name the marketplace id directly:

```bash
booth config --no-tui --variant codeserver --select "code-ext-pkg:eamodio.gitlens"
booth config --no-tui --variant codeserver --select "code-ext-pkg:eamodio.gitlens,esbenp.prettier-vscode"
booth config --no-tui --variant codeserver --select "code-ext-pkg:eamodio.gitlens@15.6.0"   # pinned
```

This compiles to `install code-extension ${CODE_EXT_PKGS}` at Boothfile order 65 —
the same slot as the curated extensions, after the editor is installed. The two mix
freely: `--select "elixir+vscode-ext/code-ext-pkg:eamodio.gitlens"`.

Three things to know about ids:

- **Which registry an id resolves against depends on your variant.** code-server
  queries [Open VSX](https://open-vsx.org); desktop VS Code queries the
  [Microsoft Marketplace](https://marketplace.visualstudio.com). The publisher
  namespaces are independent, so the same extension often has a different id on each
  — ElixirLS is `elixir-lsp.elixir-ls` on Open VSX and `JakeBecker.elixir-ls` on the
  Marketplace — and Microsoft-licensed ones (`ms-dotnettools.*`, `ms-vscode.cpptools`)
  are absent from Open VSX entirely. Look your id up on the registry your variant
  uses, per the table below.
- A trailing `@version` pins the release; without one you get whatever is latest at
  build time. See [REPRODUCIBILITY.md](REPRODUCIBILITY.md).
- An id that fails to install **fails the build**, unlike the curated extensions,
  which warn and carry on. You named it explicitly, so a silent no-op would hand you
  an image missing the extension you asked for.

#### Which editor gets the extension

Both, when both are there. code-server and desktop VS Code keep separate extension
trees and separate CLIs, and every install path here — curated and arbitrary alike —
installs into each one it finds. Which one a booth has, and therefore **which
registry your ids must come from**, comes from its variant:

| Variant | Editor | Registry for ids | Where extensions land |
|---------|--------|------------------|-----------------------|
| `codeserver` | code-server | Open VSX | `/usr/local/share/code-server/extensions` |
| `desktop-xfce` / `-kde` / `-lxqt` / `-wayland` | desktop VS Code | MS Marketplace | `/usr/local/share/code/extensions` |
| `base`, `notebook` | none | — | build stops with a message |

The curated `<language>+vscode-ext` extensions already handle this split for you —
`elixir+vscode-ext` installs `elixir-lsp.elixir-ls` on code-server and
`JakeBecker.elixir-ls` on desktop VS Code, both the real ElixirLS. `code-ext-pkg`
takes ids verbatim, so on a mixed image (`setup codeserver` *and* `setup vscode` on a
base build) an id must resolve on both registries or the build fails. Real variants
carry exactly one editor, so this only comes up if you install both by hand.

So `code-ext-pkg` needs *an* editor, not a specific one: any of the five variants
above, or `setup codeserver` / `setup vscode` in the Boothfile on a bare `base`
build. This is also why `code-ext-pkg` is a top-level template rather than an
extension hanging off `codeserver` — desktop variants have an editor without that
template ever being selected, and requiring it would mean installing a second,
browser-based editor just to name an extension.

> On a bare `base` build, `setup vscode` currently needs `setup python` before it —
> it installs Jupyter and a Bash kernel with pip. The desktop variants don't hit this
> because their desktop setup installs python first.

### JetBrains IDE JDKs

A JetBrains IDE auto-detects the JDK that `JAVA_HOME` points at, so a booth with a
single JDK already opens a Java project fine. What it does *not* do is find the others:
a booth can install six, and only one is on `JAVA_HOME`. So `idea` carries an
auto-selected `jdk-sdk` extension that registers every JDK in the image:

```bash
booth config --no-tui --variant xfce --select "java/idea"           # jdk-sdk is auto-selected
booth config --no-tui --variant xfce --select "java/idea~jdk-sdk"   # opt out
```

This compiles to `setup jetbrains-jdk` at Boothfile order 70, after both the JDK and
the IDE. SDKs are named `<vendor>-<major>` (`temurin-25`, `corretto-17`) — the name the
IDE gives a JDK it discovers itself, and the name a project's `.idea/misc.xml` already
refers to, so an existing project resolves without being edited.

The table is written to `/etc/cb-home-seed`, not into the image, because it is per-user
config and the container home is recreated per run. Seeding is **no-clobber**: change
the SDK list from File → Project Structure → SDKs and your version survives every
restart. Selecting an IDE with no Java, or Java with no IDE, stays valid — the setup
skips.

### JetBrains IDE Plugins

The JetBrains IDEs (IntelliJ IDEA, PyCharm, GoLand, ...) come with no plugins beyond
the bundled set — notably **not** Lombok, which IDEA Community stopped bundling.
`jetbrains-plugin-pkg` bakes any plugin from
[plugins.jetbrains.com](https://plugins.jetbrains.com) into the image:

```bash
booth config --no-tui --variant xfce --select "idea/jetbrains-plugin-pkg:IdeaVIM"
booth config --no-tui --variant xfce --select "idea/jetbrains-plugin-pkg:IdeaVIM,6317"
booth config --no-tui --variant xfce --select "idea/jetbrains-plugin-pkg:IdeaVIM@2.31.0"   # pinned
```

This compiles to `install jetbrains-plugin ${JETBRAINS_PLUGIN_PKGS}` at Boothfile
order 70, after the IDE is installed. Plugins land in
`/opt/jetbrains-plugins/<product>/`, which the IDE is pointed at with
`idea.plugins.path` — an image-level dir rather than the user's home, because the
container home is recreated per run.

**Curated first, where one exists.** `idea+lombok` compiles to `setup lombok-idea` — the
counterpart to `setup lombok-eclipse` — and is the way to get Lombok, rather than naming
its id. Reach for `jetbrains-plugin-pkg` for anything without a curated script of its own;
the two mix freely.

Three things to know about ids:

- **Both id forms work.** A plugin page carries an xmlId (`IdeaVIM`,
  `izhangzhihao.rainbow.brackets`) and a number in its URL (`6317`). Use the number
  when the xmlId contains a space — through a Boothfile the param expands unquoted, so
  the shell splits on whitespace before the installer sees it, and Lombok's xmlId really
  is the two-word, misspelled `Lombook Plugin`. (A curated setup calling the installer
  directly can pass such an id whole, which is what `lombok-idea` does.)
- **A plugin need not exist for every IDE in the image.** Many are IntelliJ IDEA
  Ultimate only, and asking for one in Community is a 404 rather than a mistake.
  Landing in at least one IDE is a success; landing in none fails the build.
- **`@version` pins, and gives up dependency resolution.** Unpinned ids go through
  the IDE's own installer, which picks the newest compatible build and pulls in the
  plugins this one depends on. A pinned id is fetched from the marketplace directly,
  which resolves nothing — name its dependencies too. See
  [REPRODUCIBILITY.md](REPRODUCIBILITY.md).

With no JetBrains IDE in the image the install skips rather than failing, so the
selection stays valid on a variant that has no IDE to receive it.

> **Plugins not published by JetBrains raise a modal on first launch.** The IDE shows a
> "Third-Party Plugins Notice" listing them, and waits for Accept before it opens. That
> is the IDE's own trust prompt and it appears however the plugin was installed — it is
> not something baking the plugin in avoids. Plugins whose vendor *is* JetBrains, Lombok
> among them, do not trigger it. To pre-answer it, see
> [Skipping the first-run prompts](#skipping-the-first-run-prompts).

### Skipping the first-run prompts

A fresh container means clicking through up to four JetBrains dialogs before the IDE is
usable — and since the home is recreated per run, that is every start. `idea+skip-first-run`
seeds the answers to three of them:

```bash
booth config --no-tui --variant xfce --select "java/idea+skip-first-run"
```

| Prompt | What is seeded |
| --- | --- |
| Third-Party Plugins Notice | `options/updates.xml` → `THIRD_PARTY_PLUGINS_ALLOWED=true` |
| Trust and Open Project | `options/trusted-paths.xml` → the workspace path only |
| Data Sharing | `consentOptions/accepted` → **declined** |

Two deliberate limits. The **User Agreement is not answered** — accepting a licence on your
behalf at image-build time is a legal act rather than a configuration default, so that one
dialog still appears and a human still clicks it. And the extension is **off by default**
for the same reason: these are consent decisions, so you opt in rather than having them
made for you.

Trust is scoped to the workspace path, never the "trust all projects in this folder"
checkbox — the prompt exists to stop untrusted project code from executing, and the booth's
own project is the only thing its author vouched for. Pass a different path as an argument
to `setup jetbrains-first-run` if your project lives elsewhere.

Everything is seeded no-clobber, so changing any of it in the IDE sticks.

> There is also an older `setup jetbrains-plugin <ide> "<plugin>"`, which installs one
> plugin into one IDE at *container start* instead of at build time. It still works,
> but it re-downloads on every start and needs network at runtime;
> `jetbrains-plugin-pkg` is the one to reach for.

### Project Dependency Pre-Installation

Pre-download project dependencies into the image so they're available immediately — no waiting for downloads on every container start.

```bash
# Pre-install npm dependencies from package.json
booth config --no-tui --select nodejs+npm-install

# Pre-install with pnpm (also installs pnpm globally)
booth config --no-tui --select nodejs+pnpm-install

# Pre-download Maven dependencies
booth config --no-tui --select java+maven+mvn-install
```

#### How it works

CodingBooth containers bind-mount your project at runtime, so project files aren't available during `docker build`. These templates use Docker BuildKit's `--mount=type=bind` to access your project's manifest files (e.g., `package.json`, `pom.xml`) at build time, then install dependencies into a cache directory inside the image.

**Globally-cached dependencies** (no startup step needed):

These package managers store dependencies in a global cache that persists in the image:

| Extension          | Manifest files          | Cache location       |
|--------------------|-------------------------|----------------------|
| `go/go-mod`        | `go.mod`, `go.sum`      | `$GOPATH/pkg/mod/`   |
| `rust/cargo-build` | `Cargo.toml`, `Cargo.lock` | `~/.cargo/registry/` |
| `java/mvn-install` | `pom.xml`               | `~/.m2/repository/`  |
| `java/gradle-deps` | `build.gradle[.kts]`    | `~/.gradle/caches/`  |

For these, `go build`, `cargo build`, `mvn compile`, or `gradle build` can run immediately without downloading anything.

**Project-local dependencies** (startup copy from cache):

These package managers install into the project directory (e.g., `node_modules/`, `vendor/`). Since the project directory is bind-mounted at runtime, the templates cache dependencies in `/opt/` during build and restore them on first startup via a local filesystem copy (no network needed):

| Extension              | Manifest files                      | Image cache            | Restored to    |
|------------------------|-------------------------------------|------------------------|----------------|
| `nodejs/npm-install`   | `package.json`, `package-lock.json` | `/opt/npm-cache/`      | `node_modules/`|
| `nodejs/yarn-install`  | `package.json`, `yarn.lock`         | `/opt/yarn-cache/`     | `node_modules/`|
| `nodejs/pnpm-install`  | `package.json`, `pnpm-lock.yaml`    | `/opt/pnpm-cache/`     | `node_modules/`|
| `bun/bun-install`      | `package.json`, `bun.lockb`         | `/opt/bun-cache/`      | `node_modules/`|
| `ruby/bundle-install`  | `Gemfile`, `Gemfile.lock`           | `/opt/bundle-cache/`   | `vendor/`      |
| `elixir/mix-deps`      | `mix.exs`, `mix.lock`               | `/opt/mix-cache/`      | `deps/`        |
| `php/composer-install` | `composer.json`, `composer.lock`    | `/opt/composer-cache/` | `vendor/`      |

The startup copy only runs if the target directory doesn't already exist. Once `node_modules/` (or equivalent) is present, the startup script is a no-op.

**Existing pip template** (`python+pip`):

Python's pip installs to system site-packages (not the project directory), so it works directly at build time with no startup step. It reads from `.booth/requirements.txt`:

```bash
booth config --no-tui --select python+pip
# Then create .booth/requirements.txt with your dependencies
```

#### When to rebuild

Dependencies are baked into the image. When you change your manifest files (add/remove packages), rebuild the image:

```bash
booth   # Booth auto-rebuilds when the Boothfile or manifest files change
```

Between rebuilds, you can still run `npm install`, `pip install`, etc. manually inside the container — those changes apply immediately but won't survive container recreation.

---

## Binary companions — library X → also select Y

Some language libraries need a **separate tool binary** that the package install
does not pull in. Selecting `python+pip-pkg:grpcio` installs the Python package;
it does **not** install `protoc`. Same pattern for browser automation, media
tooling, and ORM CLIs.

Use this catalog when a dependency works on your laptop but the booth is missing
a CLI or engine. Prefer a **dedicated template** when one exists (discoverable in
the TUI, pin-friendly, `requires` edges). Fall back to a `*-pkg` selection when
the companion is a normal package-manager install.

Full audit and implementation notes: [TODO-BINARY_COMPANIONS.md](TODO-BINARY_COMPANIONS.md).

### Dedicated templates (preferred when listed)

| You need | Select | What you get |
|---|---|---|
| **protoc** (Protocol Buffers compiler) | `protobuf` | apt `protobuf-compiler` |
| **Go protoc plugins** | `protobuf+go` (or `go/protobuf+go`) | `protoc-gen-go` + `protoc-gen-go-grpc` (auto-pulls go) |
| **Buf CLI** | `buf` or `buf:1.72.0` | official release binary via `setup buf` |
| **ffmpeg** (standalone) | `ffmpeg` | apt `ffmpeg` (Remotion/VHS still install their own) |
| **Graphviz** / `dot` | `graphviz` | apt `graphviz` (PlantUML still installs its own) |
| **Playwright** browsers | `playwright` | browsers under `/opt/ms-playwright` |
| **Puppeteer** Chromium | `puppeteer` | shared `PUPPETEER_CACHE_DIR=/opt/puppeteer` |
| **Cypress** binary | `cypress` | shared `CYPRESS_CACHE_FOLDER=/opt/cypress` |
| **Selenium** drivers | `selenium` or `selenium:all` | Chrome for Testing + chromedriver (+ geckodriver for `all`) |
| **.NET global tools** (e.g. `dotnet ef`) | `csharp+dotnet-pkg:dotnet-ef` | `dotnet tool install --global` |
| **Mermaid CLI** | `mermaid` | dedicated template (also via npm) |
| **PlantUML** | `plantuml` | CLI + server; pulls Graphviz |
| **Remotion** / **VHS** | `remotion` / `vhs` | product setups (include ffmpeg as needed) |

```bash
# gRPC / protobuf with Go plugins + modern Buf workflow
booth config --no-tui --select go/protobuf+go/buf

# Entity Framework CLI on C#
booth config --no-tui --select csharp+dotnet-pkg:dotnet-ef

# Headless browser stacks
booth config --no-tui --select puppeteer
booth config --no-tui --select cypress
booth config --no-tui --select selenium
```

### Library → companion (`*-pkg` recipes)

When there is no dedicated template, or you prefer a one-line package install:

| Library / ecosystem package | Also select | Notes |
|---|---|---|
| `grpc` / `grpcio` / `@grpc/grpc-js` / `google.golang.org/grpc` | `protobuf` **or** `apt-pkg:protobuf-compiler` + language plugins | Prefer `protobuf` + `protobuf+go` for Go |
| Python gRPC plugins only | `python+pip-pkg:grpcio-tools` | Still needs `protoc` itself |
| Connect-RPC / Buf workflows | `buf` **or** `go+go-pkg:"…/buf@latest"` / `nodejs+npm-pkg:"@bufbuild/buf"` | Prefer `buf` template |
| Apache Thrift | `apt-pkg:thrift-compiler` | |
| FlatBuffers | `apt-pkg:flatbuffers-compiler` | |
| Cap’n Proto | `apt-pkg:capnproto` | |
| OpenAPI generators | `nodejs+npm-pkg:"@openapitools/openapi-generator-cli"` or go-pkg oapi-codegen | |
| GraphQL codegen | `nodejs+npm-pkg:"@graphql-codegen/cli"` | |
| grpcurl | `go+go-pkg:"github.com/fullstorydev/grpcurl/cmd/grpcurl@latest"` | |
| ANTLR runtimes | `apt-pkg:antlr4` | apt may lag upstream |
| JavaCC | `apt-pkg:javacc` | |
| Bison / Flex | `apt-pkg:bison,flex` | |
| tree-sitter CLI | `rust+cargo-pkg:tree-sitter-cli` | |
| moviepy / pydub / similar | `ffmpeg` **or** `apt-pkg:ffmpeg` | Prefer `ffmpeg` template |
| Graphviz language bindings | `graphviz` **or** `apt-pkg:graphviz` | Prefer `graphviz` template |
| pandoc filters | `apt-pkg:pandoc` | |
| Prisma | `nodejs+npm-pkg:prisma` | runtime `@prisma/client` is a project dep |
| diesel / sqlx CLIs | `rust+cargo-pkg:diesel_cli` / `sqlx-cli` | diesel may need cargo features |
| Entity Framework | `csharp+dotnet-pkg:dotnet-ef` | pin with `dotnet-ef@8.0.11` |
| wasm-pack | `rust+cargo-pkg:wasm-pack` | |
| Puppeteer (project dep only) | still select `puppeteer` for browsers | npm package alone is not enough |
| Cypress (project dep only) | still select `cypress` for the binary | same |
| Selenium language bindings | `selenium` + `python+pip-pkg:selenium` or `nodejs+npm-pkg:selenium-webdriver` | drivers ≠ bindings |

```bash
# Older style: pure *-pkg, no dedicated protobuf/buf templates
booth config --no-tui \
  --select 'go+go-pkg:"google.golang.org/protobuf/cmd/protoc-gen-go@latest","google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest"' \
  --select apt-pkg:protobuf-compiler

# Media libs that shell out to ffmpeg
booth config --no-tui --select python+pip-pkg:moviepy/ffmpeg
```

### Rule of thumb

1. **Codegen** (`.proto`, thrift, grammars) → need a CLI on `PATH`.
2. **Embedded engines** (browsers, ffmpeg, graphviz) → need a system or cached binary.
3. **ORM / schema CLIs** (Prisma, `diesel_cli`, `dotnet ef`) → separate from the runtime package.

It does **not** apply when the package only needs `lib*-dev` (C/C++ track) or already
**vendors** its binary inside `node_modules` / a wheel after install.

C/C++ `lib-*` / `*-dev` packages and full toolchains (GraalVM, Android SDK, CUDA) are
out of scope here — see [TODO-BINARY_COMPANIONS.md](TODO-BINARY_COMPANIONS.md).
