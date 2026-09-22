# Booth Profiles

> Named overlays for `.booth/config.toml` and `.booth/.env`. Keep one booth
> definition and switch a few settings — port, command, env values — per
> situation (`dev`, `deploy`, `demo`) without a second copy of the config.

Back to [README](../README.md)

---

## Quick start

```
.booth/config.toml         # base — always applied
.booth/dev--config.toml    # overlay — applied only for --profile dev
.booth/.dev--env           # optional env overlay for the same profile
```

```toml
# .booth/config.toml
variant = "base"
port    = "9000"
cmds    = ["echo", "BASE"]
```

```toml
# .booth/dev--config.toml — only what differs
port = "9100"
```

```bash
booth                      # base:          port 9000
booth --profile dev        # base + dev:    port 9100, everything else from base
BOOTH_PROFILES=dev booth   # same as --profile dev
```

The flag is `--profile` (singular), and the value goes in the **next** argument:
`--profile dev`, not `--profile=dev` (see [Gotchas](#gotchas)).

---

## Layout

Profiles are flat files under `.booth/`:

| File | Role |
|---|---|
| `.booth/config.toml` | Base config — always applied |
| `.booth/.env` | Base env — always applied |
| `.booth/<name>--config.toml` | Config overlay for profile `<name>` |
| `.booth/.<name>--env` | Env overlay for profile `<name>` (the leading dot keeps it hidden, like `.env`) |

A profile needs **either or both** files. `--profile envonly` works with just
`.envonly--env`. Only the exact shapes above are recognised — a file called
`.env--dev` is not a profile.

Profiles overlay **only** `config.toml` and `.env`. `Boothfile`, `setups/` and
`startups/` are baked into the image, so they are not per-profile: switching
profiles never rebuilds an image on its own.

Any `config.toml` key can appear in an overlay — the overlay is decoded on top of
the base, so it sets exactly the keys it names.

---

## Selecting profiles

Highest priority first:

| # | Source | Notes |
|---|---|---|
| 1 | `--profile <list>` | Repeatable, and each value may be comma-separated: `--profile a --profile b` = `--profile a,b` |
| 2 | `BOOTH_PROFILES=<list>` | Comma-separated. **Ignored entirely** when `--profile` is given — sources are never merged |
| 3 | implicit `default` | Applied only when 1 and 2 are both absent **and** `default--config.toml` or `.default--env` exists |
| 4 | none | Base only — a project with no profile files behaves exactly as before |

Rules for the list:

- **Order is apply order; the later profile wins.** `--profile dev,deploy`
  layers `dev` first, then `deploy` on top.
- **Errors** (booth exits before touching Docker): an unknown name, an empty
  name, a duplicate name, or `common`.
- **`common` is reserved** — the base is always applied, so it cannot be
  selected. A file named `common--config.toml` is ignored (silently).

### The `default` profile

`default` is the profile you get when you don't ask for one. It is a
**fallback, not an always-on layer**: as soon as you select anything, it steps
aside.

```bash
booth                        # base + default
booth --profile dev          # base + dev              (default NOT applied)
booth --profile default,dev  # base + default + dev    (default named explicitly)
```

If you want something applied in every case, put it in the base
(`config.toml`), not in `default`.

### Conflicts with `--config` and `--env-file`

Profiles *are* the declaration of "this is the config", so mixing them with a
one-off file re-introduces the ambiguity they exist to remove:

- `--profile` (or `BOOTH_PROFILES`) together with `--config <file>` → **error**
- `--profile` (or `BOOTH_PROFILES`) together with `--env-file <file>` → **error**

Only explicit CLI flags trigger this; a `CB_CONFIG` or `CB_ENV_FILE` left in your
shell does not.

---

## How everything combines

One rule covers most of it:

> Sources apply in a fixed order, and **the later one wins for any single
> value**. Lists are the exception: they only ever **grow**. An overlay can *add*
> to a list, but it cannot replace what an earlier layer put there — and if it
> tries to claim something an earlier layer already claimed, booth **refuses to
> start** instead of guessing.

### The order

Lowest priority first — each layer overrides the one above it:

```
built-in defaults
  → CB_* environment variables
    → .booth/config.toml                       (the base)
      → profile overlays, in the order listed  (--profile a,b: a, then b)
        → command-line options                 (--port 9500)
```

So with `CB_PORT=7777` set, a profile's `port = "9100"` still wins; only an
explicit `--port` beats it. With `--profile a,b`, `b` beats `a`.

### What happens when two layers set the same key

| Kind of key | Examples | Result |
|---|---|---|
| Scalar | `port`, `variant`, `image`, `name` | Later layer **replaces** the value. Absent from the overlay → the base value stays |
| Boolean | `keep-alive`, `daemon` | Same — and an explicit `false` in an overlay does override a `true` base |
| Docker-arg list | `run-args`, `build-args`, `common-args` | Entries are **added, in order** (base first, then overlay). An exactly repeated entry collapses to one. An entry that *conflicts* with an earlier one is an **error** — see [Collisions](#collisions-are-errors) |
| Command | `cmds` | Later layer **replaces** the whole command. It is one logical command, so two are never concatenated (`-- <cmd>` on the CLI replaces it too) |
| Egress allowlist | `egress-allowlist` | Later layer **replaces** the list — it is *not* a union. If the base lists `base.example.com` and a profile sets `egress-allowlist = ["dev.example.com"]`, only `dev.example.com` remains. Repeat the base entries in the overlay if you want both |

Scalars, `cmds` and `egress-allowlist` are *values* with a defined "later wins", so
overriding them is what an overlay is for. A list is different: it has no way to
say "replace that entry", so an overlay that repeats a claim is a mistake worth
stopping on rather than something to resolve quietly.

### Collisions are errors

When an overlay's `run-args`, `common-args` or `build-args` claim something an
earlier layer already claimed — with a different value — booth stops before
starting anything and names both entries:

```
Error: profile "trace" (trace--config.toml) collides with an earlier layer (the base
config.toml or a profile applied before it):
  run-args: environment variable LOG
      earlier: -e LOG=debug
      trace: -e LOG=trace
An overlay's lists add to the base; they cannot replace what it already sets. Set each of
these in only one place — move it out of the base and into the profiles that need it.
```

"Earlier" means everything applied before the overlay: the base `config.toml`, any
`CB_*` list variables, and profiles listed before it.

| Flag | Two entries collide when they share… | Example |
|---|---|---|
| `-e` / `--env` | the variable name | `-e LOG=info` and `-e LOG=debug`; also `-e TOKEN` (pass the host's) against `-e TOKEN=x` |
| `-v` / `--volume` | the container mount target | `-v /etc:/cfg` and `-v /usr:/cfg`; also when only the options differ (`:ro`) |
| `-p` / `--publish` | the host port, **or** the container port | `-p 39200:80` and `-p 39200:81` (same host port); `-p 39200:80` and `-p 39300:80` (same container port — the overlay meant to *move* it, but both would be published) |
| `-l` / `--label` | the label name | `-l team=a` and `-l team=b` |
| `--build-arg` | the arg name | `--build-arg NODE=18` and `--build-arg NODE=20` |

**Not a collision:**

- An **exactly repeated** entry — it collapses to one. `8080:80` and `8080:80/tcp`
  are the same mapping.
- The same port on **different protocols** (`5353:53/udp` and `5353:53`), or on
  different **specific** bind addresses (`127.0.0.1:…` and `10.0.0.5:…`). A
  wildcard bind (no address, or `0.0.0.0`) covers every address, so it does collide
  with a specific one.
- **Scalars, `cmds`, `egress-allowlist`** — replaced by design (above).
- **Other flags** (`--cpus`, `--network`, `--name`, …). These are not examined:
  both entries are passed to Docker, in order.
- A repeat **within one file**, and any run with **no profile selected**. The check
  only compares a profile against the layers before it, so a config that worked
  without profiles works exactly as before.

**Resolving one:** set it in only one place. Move it out of the base and into just
the profiles that need it, or use a mechanism that *does* override — a scalar key,
or the profile's env file (next section).

### Environment values

A value can reach the container three ways. When the same variable is set in
more than one, this is the order — highest first:

| # | Where | Note |
|---|---|---|
| 1 | `-e KEY=value` in `run-args` | Beats **every** env file, wherever the flag sits in the command |
| 2 | `.booth/.<name>--env` | Later profile beats earlier: with `--profile a,b`, `b`'s file wins over `a`'s |
| 3 | `.booth/.env` | The base. Always loaded; profile files are applied *after* it, so they win |

Env **files** are values that override by design — a profile's `.dev--env` setting
`API_URL` replaces the base `.env`'s, and that is not a collision. So the way to
give one variable a different value per profile is the env file, not `-e` in
`run-args` (which would collide with the base). Set such a variable in the env
files only: if the base also sets it with `-e`, that `-e` beats the profile's env
file (row 1 above), so the profile's value would never take effect.

Files add up rather than replace each other: a variable that only the base
`.env` sets is still there when a profile file sets other variables. Only a
variable set in both is decided by the order above. Values are expanded by booth
as usual — see [Booth Variable Expansion](BOOTH_VARS.md).

### A worked example

```toml
# .booth/config.toml — only what every profile shares
variant    = "base"
port       = "9000"
keep-alive = true
cmds       = ["echo", "BASE"]
run-args   = ["-e", "TZ=UTC", "-v", "/etc:/cfg", "-p", "39200:80"]
```
```toml
# .booth/default--config.toml
port = "9900"
```
```toml
# .booth/dev--config.toml
port       = "9100"
keep-alive = false
run-args   = ["-e", "LOG=debug", "-p", "39300:81"]
```
```toml
# .booth/deploy--config.toml
name     = "myproj-deploy"
cmds     = ["echo", "DEPLOY"]
run-args = ["-e", "STAGE=prod"]
```
```toml
# .booth/trace--config.toml
run-args = ["-e", "LOG=trace"]
```

| Command | Port | keep-alive | Command run | Env added | Published | Name |
|---|---|---|---|---|---|---|
| `booth` | 9900 (`default`) | true | `echo BASE` | `TZ` | 39200 | folder |
| `booth --profile dev` | 9100 | **false** | `echo BASE` | `TZ`, **`LOG=debug`** | 39200 **and** 39300 | folder |
| `booth --profile dev,deploy` | 9100 (`deploy` sets none) | false | **`echo DEPLOY`** | `TZ`, `LOG=debug`, **`STAGE=prod`** | 39200 and 39300 | **`myproj-deploy`** |
| `booth --profile dev --port 9500` | **9500** (CLI wins) | false | `echo BASE` | `TZ`, `LOG=debug` | 39200 and 39300 | folder |
| `booth --profile default,dev` | 9100 (`dev` after `default`) | false | `echo BASE` | `TZ`, `LOG=debug` | 39200 and 39300 | folder |
| `booth --profile dev,trace` | — | — | — | **error:** both set `LOG` | — | — |

Things to notice: `default` disappears the moment `--profile dev` is given;
`cmds` was replaced, not joined; the base's `TZ`, mount and port came along
untouched while `dev` *added* its own; and the base holds only what is shared —
`LOG` lives in the overlays that need it, which is why `dev,trace` is refused
instead of one silently beating the other.

---

## Names and containers

A profile does **not** change the container name. If `dev` and `deploy` should
be distinguishable, set `name` in each overlay:

```toml
# .booth/deploy--config.toml
name = "myproj-deploy"
```

`booth stop`, `restart`, `exec`, `shell` and the other lifecycle commands resolve
the booth from the folder name and do not read `config.toml` or profiles. If an
overlay renames the booth, pass that name explicitly (`booth stop myproj-deploy`).

There is no `{profile}` placeholder for `--name` (see
[Name placeholders](BOOTH_RUN.md#name-placeholders)).

---

## Secrets and `.gitignore`

Put credentials in `.env` / `.<name>--env`, and keep them out of git:

```
# .booth/.gitignore
.env
.*--env
```

Booth enforces this. Before starting, it checks that **every env file it is about
to use** — the base `.env` and each selected profile's `.<name>--env` — is
ignored by git, and refuses to run if one is not:

```
Error: booth env file ".../.booth/.prod--env" is NOT gitignored. Add '.*--env' to
.booth/.gitignore before using this feature. Refusing to run to prevent accidental
credential exposure
```

Details worth knowing:

- Each file is checked on its own. Ignoring the base `.env` does not cover a
  profile file, and ignoring `.dev--env` does not cover `.prod--env`.
- Only the profile files you **select** are checked; an unselected `.staging--env`
  is not.
- A file git already **tracks** is refused even if an ignore pattern now matches
  it — ignoring a committed secret does not un-commit it.
- The check is skipped when the project is not a git repository or `git` is not
  installed.

---

## Gotchas

- **`--profile=dev` does not work.** Only the two-argument form `--profile dev`
  is recognised. The `=` form is not an error — it is not seen at all, so no
  profile is selected and the implicit `default` profile (if you have one)
  applies. This is true of every booth flag (`--port=9500` is ignored the same
  way), not just `--profile`.
- **`--profile` is a command-line option.** It is not read from `common-args`
  in `config.toml`. Use `BOOTH_PROFILES` for a persistent choice.
- **An overlay names a file that must exist.** `--profile dv` fails with
  `profile "dv" not found under .booth/ (looked for dv--config.toml and .dv--env)`.
- **`default` does not stack.** See [above](#the-default-profile).
- **The same `-e`, mount target or port in the base and an overlay is an error,
  not an override.** Put shared entries in the base and differing ones in the
  overlays. See [Collisions are errors](#collisions-are-errors).
- **`booth config` does not know about profiles.** It reads and writes the base
  `config.toml` only; overlays are hand-written.

---

## See also

- [booth run](BOOTH_RUN.md#config-files) — `config.toml` keys and precedence
- [Booth Variable Expansion](BOOTH_VARS.md) — `$VAR` / `~` in `config.toml` and `.env`
