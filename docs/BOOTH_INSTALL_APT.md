# `install apt` — design & implementation notes

> Status: **implemented**. User-facing docs live in
> [BOOTH_CUSTOMIZATION.md](BOOTH_CUSTOMIZATION.md) (install-managers table) and
> [REPRODUCIBILITY.md](REPRODUCIBILITY.md#apt--pin-the-snapshot-not-the-package).
> This file records the design rationale and the moving parts.

## What it does

```
install apt <pkg>[=<version>] [<pkg>[=<version>] ...]
```

installs Debian/Ubuntu system packages, e.g. `install apt jq htop=3.0.5-7`. Version
pinning uses apt's native `=` syntax, passed straight through. Reproducibility comes
from the Ubuntu **snapshot service**, driven by an `APT_SNAPSHOT` env var that
`booth config` sets to the configuration date.

## Moving parts

### 1. `variants/base/setups/apt--install.sh`

Matches the existing install-script preamble (root check, empty-args check, comma
expansion). Core:

```bash
SNAPSHOT_ARGS=()
if [ -n "${APT_SNAPSHOT:-}" ]; then
    SNAPSHOT_ARGS=(--snapshot "${APT_SNAPSHOT}")
fi
apt-get update "${SNAPSHOT_ARGS[@]}"
apt-get install -y --no-install-recommends "${SNAPSHOT_ARGS[@]}" "$@"
rm -rf /var/lib/apt/lists/*
```

- `APT_SNAPSHOT` set → `--snapshot <id>` on both `update` and `install` (whole archive,
  incl. transitive deps, frozen to that instant). Base is Ubuntu 24.04, where
  `--snapshot` is auto-supported.
- `APT_SNAPSHOT` empty/unset → no `--snapshot`; apt resolves against the live archive
  (its default). This is the "not from config" path.

### 2. Auto-registration (no Go change for dispatch)

`compiler.go:compileInstall` turns `install apt <pkgs>` into `RUN apt--install.sh
<pkgs>`, resolved via `PATH`. Known-manager validation is fed by
`boothfile.ScanSetupsDir` (`compiler.go:688`), which `os.ReadDir`s the setups dir and
registers every `*--install.sh`. Dropping the script in registers `apt`; verified that
`apt` compiles with no warning while `aptt` warns *"Did you mean 'apt'?"*.

### 3. `booth config` stamps the date

`cli/src/cmd/codingbooth/config.go` adds two helpers and calls `applyAptSnapshot(out)` in
both `runConfigCLI` and `runConfigTUI` (after `out` is built, before the dryrun/write
fork, so dryrun previews it too):

- `aptSnapshotID()` → `CB_APT_SNAPSHOT` if set, else `time.Now().UTC().Format("20060102")
  + "T000000Z"` (today, UTC midnight — day granularity).
- `applyAptSnapshot(out)` prepends `env APT_SNAPSHOT=<id>\n\n` to the generated
  Boothfile. No-op when there is no Boothfile content, and idempotent (skips if an
  `APT_SNAPSHOT` directive is already present).

The existing `env` Boothfile command compiles to a Dockerfile `ENV`, emitted before the
install `RUN` lines, so the script sees it. Verified end-to-end: generated Dockerfile has
`ENV APT_SNAPSHOT=…` immediately above `RUN apt--install.sh …`.

## Decisions made

- **Day granularity, captured at config time.** "Set the current date" → `T000000Z`
  today, baked in literally (not recomputed per build). Matches the
  capture-don't-recompute principle in REPRODUCIBILITY.md.
- **Scoped to `booth config`, not `booth init`/`emit`.** The injection lives only in
  `config.go`, so the init/emit paths and their fixtures are untouched.
- **`CB_APT_SNAPSHOT` override.** Follows the repo's `CB_*` env convention; lets tests
  pin a deterministic date and lets users pin a specific snapshot.
- **Idempotent / re-config behavior.** Re-running `booth config` regenerates the
  Boothfile from templates+flags and re-stamps today's date (the prior `env` line is not
  carried through the adjust-command round-trip). The idempotency guard only matters
  within a single generation pass. *If sticky snapshots across re-configs are wanted
  later, read the existing `env APT_SNAPSHOT=` line in `readExistingBooth` and reuse it.*
- **Why a bare `=version` pin isn't enough.** The live archive pool keeps only the
  current version, so old pins rot; the snapshot is what makes them resolvable. Stated
  honestly in the Tier 1 notes.

## Why it still isn't perfect

1. Without a snapshot, transitive deps float and `=version` pins rot.
2. Snapshot horizon: nothing before 2023-03-01.
3. `APT_SNAPSHOT` covers only `install apt` lines; apt in custom setup scripts needs the
   global sources rewrite (documented as the Tier 2 "global alternative").
4. PPAs / third-party repos aren't covered by the Ubuntu snapshot service.

## Tests

- `cli/src/cmd/codingbooth/config_test.go`: `aptSnapshotID` (override + default format),
  `applyAptSnapshot` (prepend + ordering, no-op on empty/nil, idempotent).
- Verified manually: `booth config --dryrun --select go` shows the `env` line;
  `emit-dockerfile` produces `ENV` before `RUN apt--install.sh`; `apt` recognized,
  `aptt` warned.

## Sources

- [Ubuntu snapshot service — how-to](https://documentation.ubuntu.com/server/how-to/software/snapshot-service/)
- [snapshot.ubuntu.com](https://snapshot.ubuntu.com/)
