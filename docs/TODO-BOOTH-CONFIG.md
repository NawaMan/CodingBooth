# TODO — booth config: TUI vs. Boothfile/config.toml gaps

Findings from an audit of the configuration feature (2026-07-22, against `v0.63.0` /
commit `715dd3a6`). The question asked was: *does the config TUI support everything a
Boothfile / config.toml can express?* It did not — the TUI reached well under half of
`config.toml`, none of the Boothfile directly, and along the way it **destroyed**
settings it did not know about.

Every claim below was verified against the built `./codingbooth` binary; the TUI ones
were driven with VHS, the same way `tests/config-tui/` does.

**Status:** all five sections are closed. Four were fixed; §5 was answered rather
than fixed — the audit's framing of it was wrong, and the section now records why.
Each one keeps the original finding below its resolution, since the reasoning is
what makes the outcome useful.

Back to [TODO](TODO.md) | See also: [booth config](BOOTH_CONFIG.md), [config TUI](BOOTH_CONFIG_TUI.md)

---

## Table of Contents

- [Priority](#priority)
- [1. The TUI silently drops baseline settings on save](#1-the-tui-silently-drops-baseline-settings-on-save)
- [2. Dead fields — written to config.toml, never read back](#2-dead-fields--written-to-configtoml-never-read-back)
- [3. `--set` is unvalidated and cannot write integers](#3---set-is-unvalidated-and-cannot-write-integers)
- [4. config.toml keys with no TUI field](#4-configtoml-keys-with-no-tui-field)
- [5. The TUI cannot express the Boothfile — and should not](#5-the-tui-cannot-express-the-boothfile--and-should-not)

---

## Priority

§1–§3 were **defects**, and §1 lost user data on a no-op save, so it outranked any
amount of field-table expansion. §4 was a *missing feature*. §5 was filed as the
largest gap of the three and turned out not to be a gap at all — see the section.

All five are now closed; the follow-up §5 spun out is tracked on its own.

- [x] **§1** — TUI save drops `cmds`, `timezone`, `persist-home`, `idle-*`, `sudo=false`, … — **fixed**
- [x] **§2** — `Public` / `TLS Cert` / `TLS Key` TUI fields do nothing — **fixed** (fields removed)
- [x] **§3** — `--set` accepts any key; integer keys produce an unloadable config.toml — **fixed**
- [x] **§4** — 30 config.toml keys had no TUI field — **fixed** (field table generated from the schema)
- [x] **§5** — raw-Boothfile escape hatch — **won't fix**: declarative editor, procedural
      file; the seam is a boundary, not a gap. Follow-up spun out: project-local templates

---

## 1. The TUI silently drops baseline settings on save

> **FIXED.** The save now starts from the merged baseline, strips only the keys the
> TUI renders, and re-derives those from the TUI result — so unmodeled settings pass
> through untouched while unchecking a box still removes its key. `sudo` is
> pre-populated as a string so the tri-state field can see `false`. Covered by
> `tests/config-tui/test16-tui-preserves-unmodeled-settings.sh`. The rest of this
> section is kept as the record of what went wrong.

`runConfigTUI` builds `mergedFlags` (existing booth as baseline + CLI overrides) but
uses it **only** to pre-populate the TUI — [`cli/src/cmd/codingbooth/config.go:285-289`](../cli/src/cmd/codingbooth/config.go).
After the TUI returns, the output is generated from `flags` (the CLI-only flags),
reconstructed from a **fixed allowlist** of field keys —
[`config.go:315-382`](../cli/src/cmd/codingbooth/config.go). Anything in the baseline
that has no corresponding TUI field is never re-emitted, so it is gone from the
regenerated `config.toml`.

`runConfigCLI` does this correctly — [`config.go:91`](../cli/src/cmd/codingbooth/config.go),
`flags = mergeFlags(readExistingBooth(targetPath), flags)`. The bug is TUI-path only.

### Reproduction

```bash
codingbooth config --no-tui --select go \
    --cmd "echo hello" --env FOO=bar \
    --set persist-home --set timezone=Asia/Bangkok --set idle-time=30

codingbooth config          # open the TUI, change nothing, press Ctrl+S
```

```toml
# .booth/config.toml BEFORE            # AFTER Ctrl+S (no edits made)
timezone = "Asia/Bangkok"              run-args = ["--env", "FOO=bar"]
cmds = ["echo", "hello"]
run-args = ["--env", "FOO=bar"]
idle-time = "30"
persist-home = true
```

`cmds`, `timezone`, `persist-home` and `idle-time` are lost.

### The `sudo=false` variant of the same bug

`--set sudo=false` is parsed into `BoolFields["sudo"] = false` by `buildPreSelection`
([`config.go:698-711`](../cli/src/cmd/codingbooth/config.go)), but the TUI's `sudo` is a
tri-state **cycle** field read back from `StringFields`
([`config.go:353-356`](../cli/src/cmd/codingbooth/config.go)). The two never meet, so
`sudo = false` is dropped on save — and since sudo defaults to **true**, a booth that
deliberately disabled passwordless sudo silently gets it back.

Verified: `--set keep-alive --set name=mybooth --set sudo=false` → after a no-edit TUI
save, `keep-alive` and `name` survive, `sudo = false` does not.

### Fix sketch

Use `mergedFlags` (not `flags`) after the TUI returns, and carry keys the TUI does not
recognise straight through `PreSelection` → `ConfigResult` → `flags.sets` untouched,
instead of re-deriving the whole set from `boolSetKeys` / `stringSetKeys`. The result
maps already pass unknown keys through ([`tui/model.go:165-175`](../cli/src/pkg/boothinit/tui/model.go));
it is only the write-back that discards them.

---

## 2. Dead fields — written to config.toml, never read back

> **FIXED — the three TUI fields are removed.** The *feature* was never in question:
> `booth --public --tls-cert ... --tls-key ...` works and is untouched. What was
> wrong is that `booth config` offered to persist a start-time-only setting, writing
> a `public = true` that booth ignores. Persisting it is also the wrong shape:
> `config.toml` is committed, so a stored `public = true` would expose the booth for
> everyone who clones, while the password it needs lives in a gitignored file they do
> not have. Values recorded by older versions are now dropped on the next
> reconfigure with a note. The rest of this section is the record of what went wrong.

`Public`, `Password`, `TLSCert` and `TLSKey` are declared `toml:"-" ignored:"true"` in
[`cli/src/pkg/appctx/app_config.go:126-129`](../cli/src/pkg/appctx/app_config.go) —
deliberately never read from TOML or environment variables. But the config TUI offers
**Public**, **TLS Cert** and **TLS Key** fields
([`tui/configfields.go:56-79`](../cli/src/pkg/boothinit/tui/configfields.go)), and both
they and `--set` write those keys into `config.toml`.

```bash
codingbooth config --no-tui --select go --set public --set tls-cert=/tmp/a.pem
# → config.toml gets:  public = true / tls-cert = "/tmp/a.pem"

codingbooth --dryrun
# → -p 127.0.0.1:10000:10000     (still loopback-bound; `public` had no effect)
```

Three of the TUI's 26 fields are inert. Either wire these keys up (they are excluded
from TOML on purpose, presumably because `--public` needs the interactive password
flow) or remove the fields and say so in the docs.

---

## 3. `--set` is unvalidated and cannot write integers

> **FIXED.** `--set` is now typed and validated against a schema reflected from
> `AppConfig` (`pkg/appctx/config_keys.go` — `ConfigKeys()`), which is also the
> single source of truth §4 should build on. Integer keys write unquoted, list keys
> accumulate across repeats, unknown keys are refused with a "did you mean"
> suggestion, and the `toml:"-"` keys are accepted with a warning that booth will
> not read them back. The rest of this section is kept as the record of what went
> wrong.

`parseSetOverrides` classifies every value as `bool` or `string` only, and no key is
checked against `AppConfig`. Two consequences:

**Unknown keys are accepted silently.**

```bash
codingbooth config --no-tui --select go --set totally-bogus-key=42
# → config.toml gets:  totally-bogus-key = "42"     (ignored at run time, no warning)
```

**Integer keys produce a config.toml that booth refuses to load.** `--set idle-time=30`
writes the TOML *string* `"30"`, while `AppConfig.IdleTime` is an `int`:

```
❌ failed to read toml config: toml: line 6 (last key "idle-time"):
   incompatible types: TOML value has type string; destination has type integer
```

So `idle-time`, `idle-shutdown-time` and `idle-exit-code` are unreachable from *both*
the TUI and `--set` — writing them at all breaks the booth. The TUI will need a
`fieldKindInt` before §4 can cover them.

---

## 4. config.toml keys with no TUI field

> **FIXED via option 2 below.** The field table is now generated: each field
> carries a label and its help text, and its *shape* is resolved from
> `appctx.ConfigKeys()` at build time. All 30 missing keys have fields, int keys
> got `fieldKindInt` (digits only, written unquoted through the typed `--set`
> path), and list keys got a real write-back. `cmd/codingbooth` no longer keeps
> its own copy of the key set — it asks `tui.RenderedConfigKeys()`, which is what
> drifted before. `TestFieldTableCoversSchema` fails on any AppConfig key that is
> neither rendered nor recorded in `unrenderedKeys` with a reason.
>
> Two things surfaced while wiring it up:
>
> - The **`version` collision**. The TUI's "Version" field was labelled and
>   documented as the prebuilt image tag, but has always been wired to
>   `--version` — the *template release* this configure run compiles from — and
>   never wrote the `version` key at all. Same family as §2: a field describing a
>   setting it does not write. Split into **Templates Version** (TUI-only,
>   accurate label) and **Image Version** (the real `version` key).
> - **Cache lists grew on every reconfigure** — a pre-existing defect on the
>   `--no-tui` path, not a TUI one. A cache entry reaches the regenerated file
>   both from the existing `config.toml` and from the `--set cache-files=…` in
>   the `Configured by:` header, so it was written twice, then four times, then
>   eight. Deduped in `mergeConfigCache`; covered by
>   `tests/config/test76-reconfigure-cache-no-growth.sh`.
>
> Covered by `tests/config-tui/test17-tui-covers-schema-keys.sh` — these keys are
> now keys the TUI *owns*, so a save strips and re-derives them, which is a
> stronger claim than §1's pass-through: a pre-population gap would delete the
> value rather than leave it alone. The rest of this section is the record of
> what was missing.

### Where the authoritative list lives

Booth does **not** read whatever happens to be in `config.toml`. It decodes into the
`AppConfig` struct ([`cli/src/pkg/appctx/app_config.go:190`](../cli/src/pkg/appctx/app_config.go)),
and BurntSushi's decoder only fills fields that exist. The returned `MetaData` is
discarded, so unknown keys are dropped silently — no error at read time, no warning at
write time. That is why §3's bogus key sails through both ends.

Reflecting over `AppConfig` yields **50 fields: 46 live TOML keys + 4 tagged `toml:"-"`**
(the dead ones from §2).

**The struct is not the whole truth, though.** `cache-files` and `cache-dirs` are real,
honored keys read by two *separate* ad-hoc structs — `ensureCacheFromConfig`
([`pkg/booth/booth.go:584-589`](../cli/src/pkg/booth/booth.go)) and `extractUserRunArgs`
([`cmd/codingbooth/config.go:516-519`](../cli/src/cmd/codingbooth/config.go)) — and are
absent from `AppConfig` entirely. The true surface is **48 keys across three readers**,
with no single source of truth.

- [x] Consolidate the three readers, or at least document `AppConfig` + the two cache
      keys as *the* list. Any future "validate `--set` keys" work must consult all
      three or it will reject two valid keys. — **done**: `appctx.ConfigKeys()`
      reflects over `AppConfig` and folds in the two cache keys explicitly, so there
      is now one answer to "what may appear in a config.toml". The two ad-hoc
      readers still exist; they are just no longer the only record of those keys.

### The 28 keys booth reads that the TUI cannot set

| Group | Missing keys | Type note |
|---|---|---|
| Idle / countdown | `idle-time`, `idle-shutdown-time`, `idle-exit-code`, `show-run-time`, `show-count-down`, `count-down-exit-code` | first three are `int` → need `fieldKindInt` (writing them is safe now that §3 is fixed); the last three are `string` despite sounding numeric |
| Egress detail | `egress-mode`, `egress-enforcement`, `egress-allowlist`, `egress-allowlist-file`, `egress-policy-file` | `egress-allowlist` is `[]string` → `fieldKindList`; only the on/off toggle exists today |
| Home / tmp | `persist-home`, `leave-tmp-on-exit`, `keep-tmp-on-start` | bool |
| Identity / runtime | `project-name`, `host-uid`, `host-gid`, `timezone`, `log-time` | |
| Image | `dockerfile`, `boothfile`, `emit-dockerfile` | |
| Arrays | `cmds`, `common-args`, `build-args`, `run-args` | `run-args` is *partially* covered via env/expose/mount |
| Meta | `config`, `code` | arguably should not be in a project config.toml at all |

Plus `cache-files` / `cache-dirs` from the non-struct readers above.

### The 8 TUI fields that are not live config.toml keys

Three are benign, five are not:

| TUI field | Verdict |
|---|---|
| `env`, `expose`, `mount` | fine — they compile into `run-args` |
| `booth-version` | fine — writes to the lock file, not config.toml |
| `version` | ~~fine~~ — **not fine**: labelled and documented as the prebuilt image tag, but wired to `--version`, the template release. Fixed with §4: split into `templates-version` (TUI-only) and `version` (the real key) |
| `debug` | ~~junk~~ — **fixed with §3**: it is a `booth config` flag, not an `AppConfig` key, so it now steers the run (`flags.debug`, printing the resolved selection) instead of being written into config.toml as a line nothing reads |
| `public`, `tls-cert`, `tls-key` | ~~dead~~ — **fixed with §2**: the fields are removed; these stay start-time flags |

The `run-args` restriction to `--env` / `--publish` / `--volume` is documented as
intentional (short-form = template-owned, see
[BOOTH_CONFIG.md](BOOTH_CONFIG.md#run-args-ownership-convention)), but it does mean
`--cap-add`, `--network`, `--gpus`, `--device`, `--user`, `--add-host` and friends are
TUI-unreachable. They survive a TUI save today only because templates re-emit them.

### Two ways to close it

1. **Round-trip unknowns** (minimal) — carry any `--set` key the TUI does not model
   straight through baseline → result → output untouched. Stops the §1 data loss
   without needing a field per key; does not make them editable. *(This is what §1's
   fix does.)*
2. **Generate the field table from the struct** (durable) — drive the TUI's field list
   off `AppConfig` reflection plus per-key display metadata, so the two cannot drift
   again. The current drift happened precisely because the list is hand-maintained in
   a second place ([`tui/configfields.go:28`](../cli/src/pkg/boothinit/tui/configfields.go)).
   *(This is what shipped — see the note at the top of this section.)*

---

## 5. The TUI cannot express the Boothfile — and should not

> **WON'T FIX — this is a boundary, not a gap.** The section was written as
> though the TUI ought to reach the Boothfile and merely lacked the widgets. It
> cannot, and the reason is not expressiveness. The two halves of a booth are
> different kinds of thing, and the audit had mistaken the seam between them for
> a hole. The reasoning is kept below because the conclusion is only useful with
> it.

### The observation

The Boothfile parser accepts `run`, `copy`, `env`, `workdir`, `expose`, `label`, `arg`,
`setup` and `install` — [`cli/src/pkg/boothfile/parser.go:423-447`](../cli/src/pkg/boothfile/parser.go).
The TUI's entire Boothfile surface is **template selection plus template parameters**;
it compiles templates and emits nothing else. There is no way, from the TUI, to add:

- an ad-hoc `run` / `copy` / `workdir` / `label` / build-time `env` line
- an `install <mgr> <pkgs>` for a manager with no `*-pkg` extension
- a `.booth/startups/*--startup.sh` script (they survive regeneration, but cannot be authored)

### Why no escape hatch works

`config.toml` is a set of settings: unordered, each key independent, every one
meaningful on its own. The Boothfile is a **program**: `run apt-get install X`
before `setup go` and after it are different builds. The TUI is a declarative
editor, and it is a good one — §4 made it complete over `config.toml` precisely
because that half *is* a set of independent facts.

A procedural line has one property the declarative model has nowhere to store:
**where it goes**. The obvious escape hatch — a "raw Boothfile lines" block the
compiler emits verbatim and the TUI round-trips — founders on exactly that. The
block has to sit somewhere, and any fixed position is a guess about a build step
whose whole meaning is its position. Worse, the position is not even stable:
select one more template next month and the resolver reorders what precedes the
block, so the same preserved text silently becomes a different program. Round-
tripping preserves the characters and loses the semantics, which is the failure
mode that looks like it works.

Every variant of the idea has the same shape. Making the TUI *author* `run`
lines does not help either — it would be reimplementing a text editor inside a
template picker, badly, for a file the user's own editor already handles.

### So the drift lockout is correct

As soon as a project needs one custom build step the user hand-edits the
Boothfile, and drift detection then restricts them to `.new` / `.bak` merges
(see [BOOTH_CONFIG.md](BOOTH_CONFIG.md#hand-written-files)). The original text
called this a one-way door and counted it as part of the gap.

It is the honest behaviour. If a hand-edited procedural file cannot be
regenerated without losing the edits — and per the argument above it cannot —
then refusing to overwrite it is right. Softening the lockout would not recover
the edits; it would only lose them more quietly.

### What the declarative half *can* hold: a name

It cannot hold a sequence, but it can hold a **named unit**, and that mechanism
already exists. `.booth/setups/<name>--setup.sh` is copied into the image and
put on `PATH` ([`pkg/boothfile/compiler.go:57`](../cli/src/pkg/boothfile/compiler.go)),
and a `setup <name>` line resolves to it. The procedural part lives in a shell
script — a procedural tool for a procedural job — and the declarative part
refers to it by name, ordered by the same dependency rules as everything else.

What is missing is only that a project cannot contribute such a unit to the
picker: [`LoadRegistry`](../cli/src/pkg/boothinit/template/loader.go) reads
exactly one templates directory, so a hand-written setup script can be *written*
but never *selected*.

That is the shape of a real follow-up — project-local templates under
`.booth/templates/`, merged into the registry so a local unit gets a name,
dependencies and params like any other. It is a feature on its own merits
(registry merge, name-collision rules, how a local template interacts with
drift), not a way of closing this section, and it should be scoped as one.

### The boundary, stated

The config TUI owns `config.toml`, completely as of §4. It owns the Boothfile
only while that file is purely template-generated. Once a booth needs a custom
build step, the Boothfile is the user's, and the TUI stops writing it.

That is a property of the design, not a defect in it.
