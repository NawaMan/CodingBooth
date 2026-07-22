# TODO — booth config: TUI vs. Boothfile/config.toml gaps

Findings from an audit of the configuration feature (2026-07-22, against `v0.63.0` /
commit `715dd3a6`). The question asked was: *does the config TUI support everything a
Boothfile / config.toml can express?* It does not — the TUI reaches well under half of
`config.toml`, none of the Boothfile directly, and along the way it **destroys**
settings it does not know about.

Every claim below was verified against the built `./codingbooth` binary; the TUI ones
were driven with VHS, the same way `tests/config-tui/` does.

Back to [TODO](TODO.md) | See also: [booth config](BOOTH_CONFIG.md), [config TUI](BOOTH_CONFIG_TUI.md)

---

## Table of Contents

- [Priority](#priority)
- [1. The TUI silently drops baseline settings on save](#1-the-tui-silently-drops-baseline-settings-on-save)
- [2. Dead fields — written to config.toml, never read back](#2-dead-fields--written-to-configtoml-never-read-back)
- [3. `--set` is unvalidated and cannot write integers](#3---set-is-unvalidated-and-cannot-write-integers)
- [4. config.toml keys with no TUI field](#4-configtoml-keys-with-no-tui-field)
- [5. The TUI cannot express the Boothfile at all](#5-the-tui-cannot-express-the-boothfile-at-all)

---

## Priority

The gaps in §4 and §5 are *missing features*. §1–§3 are **defects**, and §1 loses user
data on a no-op save, so it outranks any amount of field-table expansion.

- [x] **§1** — TUI save drops `cmds`, `timezone`, `persist-home`, `idle-*`, `sudo=false`, … — **fixed**
- [x] **§2** — `Public` / `TLS Cert` / `TLS Key` TUI fields do nothing — **fixed** (fields removed)
- [x] **§3** — `--set` accepts any key; integer keys produce an unloadable config.toml — **fixed**
- [ ] **§4** — add the missing config.toml fields to the TUI (needs `fieldKindInt` first)
- [ ] **§5** — decide whether the TUI gets a raw-Boothfile escape hatch

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

### Where the authoritative list lives

Booth does **not** read whatever happens to be in `config.toml`. It decodes into the
`AppConfig` struct ([`cli/src/pkg/appctx/app_config.go:190`](../cli/src/pkg/appctx/app_config.go)),
and BurntSushi's decoder only fills fields that exist. The returned `MetaData` is
discarded, so unknown keys are dropped silently — no error at read time, no warning at
write time. That is why §3's bogus key sails through both ends.

Reflecting over `AppConfig` yields **49 fields: 45 live TOML keys + 4 tagged `toml:"-"`**
(the dead ones from §2).

**The struct is not the whole truth, though.** `cache-files` and `cache-dirs` are real,
honored keys read by two *separate* ad-hoc structs — `ensureCacheFromConfig`
([`pkg/booth/booth.go:584-589`](../cli/src/pkg/booth/booth.go)) and `extractUserRunArgs`
([`cmd/codingbooth/config.go:516-519`](../cli/src/cmd/codingbooth/config.go)) — and are
absent from `AppConfig` entirely. The true surface is **47 keys across three readers**,
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

---

## 5. The TUI cannot express the Boothfile at all

The Boothfile parser accepts `run`, `copy`, `env`, `workdir`, `expose`, `label`, `arg`,
`setup` and `install` — [`cli/src/pkg/boothfile/parser.go:423-447`](../cli/src/pkg/boothfile/parser.go).
The TUI's entire Boothfile surface is **template selection plus template parameters**;
it compiles templates and emits nothing else. There is no way, from the TUI, to add:

- an ad-hoc `run` / `copy` / `workdir` / `label` / build-time `env` line
- a `setup <script>` pointing at a hand-written `.booth/setups/` script
- an `install <mgr> <pkgs>` for a manager with no `*-pkg` extension
- a `.booth/startups/*--startup.sh` script (they survive regeneration, but cannot be authored)

This is the structural gap. As soon as a project needs one custom build step the user
hand-edits the Boothfile — and drift detection then locks them out of the TUI's write
path for good (`.new` / `.bak` merge only, see
[BOOTH_CONFIG.md](BOOTH_CONFIG.md#hand-written-files)). The TUI is effectively a
one-way door: good for greenfield, unusable as the ongoing editor for any booth that
has outgrown templates.

Worth considering: a "raw Boothfile lines" block the compiler appends verbatim and the
TUI round-trips, so hand-written additions stop counting as drift. That is a design
decision, not a missing widget, which is why it sits last here despite being the
largest gap.
