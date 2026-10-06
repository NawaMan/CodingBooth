# Catalog Versioning

> **Status: versioning implemented** — every item is stamped, the manifest is generated, and the
> release check runs in `release-push` and CI. Integrity and the tested database are still open; see
> [TODO](#todo). This is the first step toward splitting the catalog from the variant images,
> without moving anything yet (see [UNDERSTAND_SETUPS.md](UNDERSTAND_SETUPS.md) for what the catalog
> is).

Every catalog item — setup script, install script, helper, template, extension — carries two
identities:

| Identity | Who sets it | Says | Proves |
| --- | --- | --- | --- |
| **`cb-version`** (semver) | the author, by hand | *what kind* of change happened | nothing on its own |
| **sha256** | generated | *that* something changed | exactly which content this is |

Neither is enough alone: a hand-kept version drifts silently, and a hash cannot say whether a change
breaks anyone. The [release check](#release-check) binds them — **a changed hash with an unchanged
version fails the release.**

The sha256 is also the foundation for supply-chain checks later (verified catalog downloads, signed
manifests); see [TODO](#todo).

---

## Where the version lives

One field name for every kind, so it greps uniformly and collides with nothing:

| Kind | Form |
| --- | --- |
| setup / install script, helper, `libs/*` | header comment, within the first 20 lines: `# cb-version: 1.2.0` (`// …` in `.js`, `<!-- … -->` in `.html`) — right after the license header |
| asset directory (`booth-web-preview/`, `logo-files/`) | a `.cb-version` file inside it — svg/ico/json cannot carry a comment |
| template / extension | top-level key, before any `[table]`: `cb-version = "1.2.0"` |

Not a bare `version`: in `config.toml` that already means the image version, and in a template a
top-level key reads like a config scalar.

- An **extension** is versioned on its own, independently of its parent.
- Inline `[files.setups]` / `[files.home*]` content is part of the template file, so the template's
  version covers it.
- `variants/base/setups/future/` (parked) is not part of the catalog. Category `meta.toml` files are
  display-only and not versioned.
- **Helpers and `libs/`** are versioned too. They are the API catalog setups build on, so a breaking
  change there matters more than anywhere else.

## What each bump means

| | **Major** | **Minor** | **Patch** |
| --- | --- | --- | --- |
| **Setup / install / helper** | a flag removed or renamed; installed command or path moves; a default behaves differently; a helper function removed or its contract changed | new flag; new default tool version; new helper function | fix with no behaviour change |
| **Template / extension** | a param removed, renamed, or **reordered** (positional `java:21,corretto` depends on order); a `requires` added; order band changed | a param appended; new `suggests`; new files | wording / display text |

`0.x` follows semver's own rule: anything may change. It marks items that have not settled.

## The manifest

`build/catalog-manifest.tsv` — generated, committed, one row per item, tab-separated, sorted by
kind then name:

```
kind       name                cb-version  sha256  path
setup      go                  1.0.0       9f2c…   variants/base/setups/go--setup.sh
install    npm                 1.0.0       41ab…   variants/base/setups/npm--install.sh
helper     cb-has-vscode.sh    1.0.0       c07e…   variants/base/setups/cb-has-vscode.sh
lib        skip-setup.sh       1.0.0       5d10…   variants/base/setups/libs/skip-setup.sh
assets     logo-files          0.1.0       a8b3…   variants/base/setups/logo-files/.cb-version
template   go                  1.0.0       77d1…   templates/languages/go/template.toml
extension  go+linter           1.0.0       e5a0…   templates/languages/go/linter--extension.toml
```

`path` is the file that carries the version. The sha256 is of that file — except for an asset
directory and for a template whose directory holds more than `template.toml` (home-seed, file-based
segments), where it covers every file in it: sorted `relpath<TAB>filehash` lines, hashed. A
template's hash never includes its extensions.

```bash
build/gen-catalog-manifest.sh           # regenerate — after any change under setups/ or templates/
build/gen-catalog-manifest.sh --check   # verify only (tests/config/catalog/test94)
```

- **Names are the names users write** — `setup go`, `install npm`, `go+linter` — so anything that
  reads a Boothfile or a `--select` string can join against it. That is what the
  [tested database](#todo) needs.
- The generator is `cli/src/cmd/catalog-manifest` (logic in `cli/src/pkg/catalog`), run through
  the `build/` wrappers above.
- `tests/config/catalog/test94-catalog-manifest-is-current.sh` fails when an item has no valid
  `cb-version` or the committed manifest is stale.
- Kept stable and machine-readable on purpose: it is attached to each release so later tooling can
  look up "what was `setup go` at release X".

## Release check

The baseline is the manifest **at the previous release tag** (`git show <tag>:<manifest>`), not the
previous commit — a file may change many times within one release cycle and needs one bump. The
previous release tag is the highest `X.Y.Z` tag **below** `version.txt` (so re-releasing an
already-tagged version still compares against the one before); the check warns when that tag is not
an ancestor of HEAD. A baseline with no manifest (any release before this one) means only the
`cb-version`s are validated.

```bash
build/check-catalog-versions.sh                    # blocking
build/check-catalog-versions.sh --report           # report only — during development
build/check-catalog-versions.sh --baseline 0.80.0  # any git ref
```

| Hash | Version | Result |
| --- | --- | --- |
| changed | same | ❌ fail — bump the version |
| same | changed | ⚠️ warn — bumped with no change |
| any | lower than baseline | ❌ fail |
| new item | — | must declare a `cb-version` |
| removed item | — | listed in the report |

One automatic check on the *kind* of bump: for templates and extensions, the params are compared
against the baseline — a param removed or moved fails unless the bump is breaking (a new major; a
new minor below 1.0.0). Everything else is the author's call.

It runs:

- in the **`release-push`** skill as step 0c, right after the catalog pin sweep, **blocking**;
- in **CI** on release (`release-binary-and-wrapper.yaml`), so a hand-dispatched release cannot
  skip it — which also publishes `catalog-manifest.tsv` with the release;
- as a **non-blocking report** during development, so pending bumps are visible early without the
  pre-commit hook getting in the way.

## Baseline — the one-off stamp

Every existing item gets a starting version from its history, because experimental status is not
reliably marked:

| Item | Starts at |
| --- | --- |
| first added **before 2026-08-04** (two months before the stamp) **and** not marked experimental | **1.0.0** |
| added on or after 2026-08-04, **or** marked experimental | **0.1.0** |

"Marked experimental" means the word appears in the template's or extension's display text (nine
files: `wayland`, `wails`, `clang+kernel`, `herdr+autostart`, `postgrest` and its two extensions,
`postgresql+pg-ext-pkg`, `penpot`), in a setup script's first 20 lines (`cpp-nb-kernel`), or that
the setup is emitted by an experimental template or extension (`penpot`, `postgrest`, `wails`,
`wayland`).

"First added" is the date of the commit that added the file at its current path, following renames
(`git log --follow --diff-filter=A`). Dates are those of the retimed history.

Result of the stamp (833 items):

| Kind | 1.0.0 | 0.1.0 |
| --- | --- | --- |
| setup | 212 | 82 |
| install | 20 | 2 |
| helper | 18 | 7 |
| lib | 2 | 3 |
| assets | — | 2 |
| template | 149 | 44 |
| extension | 195 | 97 |

New items after the stamp start at `0.1.0` and move to `1.0.0` when the author says they are stable.

---

## TODO

### Versioning (this design)

- [x] Generator: produce the manifest (`kind`, `name`, `cb-version`, `sha256`, `path`) for setups,
      installs, helpers, `libs/`, asset directories, templates and extensions.
- [x] Baseline stamp: add `cb-version` to every item per the [baseline rule](#baseline--the-one-off-stamp);
      commit the first manifest.
- [x] Release check: compare against the previous release tag's manifest; wired into
      `release-push` (step 0c, blocking) and CI; `--report` for development.
- [x] Template param check for breaking bumps.
- [x] Loader: accept `cb-version` in templates and extensions; `booth template show` prints it.
- [x] Attach the manifest to each GitHub release.
- [x] Docs: `BOOTH_SETUP.md`, `AGENT_TEMPLATE.md` and the `setup-work` skill tell authors to bump
      `cb-version`.
- [ ] First real run: the 0.80.0 release validates only (0.79.0 has no manifest); the release after
      it is the first to compare. Watch that one.

### Integrity (next, uses the sha256)

- [ ] Publish `templates.zip` with a manifest / `.sha256`; the CLI verifies before extracting and
      when reading from its cache (today it is a plain `http.Get`, unchecked).
- [ ] Sign the manifest (minisign or cosign); embed the public key in the CLI binary.
- [ ] Record the catalog hash beside `templates-version` in `.booth/.generated`; refuse a different
      download under the same tag.
- [ ] Separately: a `verify_sha256` helper in `libs/` for upstream downloads, plus a guard that
      warns when a setup downloads without verifying (13 of 293 verify today).

### Tested database (later — keep it possible)

Record which catalog items were sanity-tested with which release, starting with the
`tests/complex/` suite only.

- [ ] Each complex test's covered items are derived from its `.booth/Boothfile` (`setup` /
      `install` lines) and `config.toml` — no hand-kept list.
- [ ] A release run records rows of `release · test · result · item · cb-version · sha256`.
- [ ] Publish it per release (alongside the manifest) and surface it in `booth template show`.

**Nothing in the versioning work may block this.** Concretely: manifest names must match what a
Boothfile or `--select` writes; the manifest must stay machine-readable and be kept per release;
and the identity of an item is the `(name, cb-version, sha256)` triple, so a test result can name
exactly what it exercised.
