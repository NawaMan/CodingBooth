---
name: release-push
description: Cut a release from the current --rc version — offer to refresh catalog version pins, drop the rc suffix in version.txt and README.md, commit, push main to origin, then reopen the tree by bumping to the next minor --rc1 and committing that WITHOUT pushing. Use when the user says "release", "cut a release", "make the version non-rc", "/release-push", or asks to publish the current version.
---

# Cut a release and reopen the tree

Two version commits, exactly one push, and one dispatch that needs its own yes.
Catalog version bumps, if accepted, are extra commits **before** the first version
commit — they ride the same push.

```
0.  git preflight (must be main, clean, --rc)
0b. catalog version sweep — offer bumps; commit accepted ones (not the version commit)
0c. catalog item versions — build/check-catalog-versions.sh must pass; bump cb-version where it fails
0d. apt snapshot — pin apt-snapshot.txt a week back, move the examples to it → commit (not the version commit)
1.  version.txt/README.md: X.Y.Z--rcN → X.Y.Z    → commit "X.Y.Z"
2.                                                → git push origin main
3.  version.txt/README.md: X.Y.Z → X.(Y+1).0--rc1 → commit "X.(Y+1).0--rc1"  → NO push
4.  report
5.  offer to dispatch `Release everything`, wait for a yes, then watch it
6.  after a green release: offer to dispatch the tap's `Bump formulas`, wait for a yes, then watch it
```

Steps 1–4 are recoverable — two local commits and a push. **Step 5 is not**: it publishes Docker
images, cuts a GitHub release, and deploys the live site. Treat them as different kinds of act.

**Why push at all: the actual release runs in GitHub Actions, off the pushed non-rc version.**
Nothing is released from the workstation. The workflows read `version.txt` out of `origin/main` and
**refuse to run on a `--rc` version**. So pushing the non-rc commit is what makes a release
*possible*; step 5 is what performs it. See *The GitHub Actions release* below.

**That is also why step 3's bump is not pushed.** The workflows check out `main` at dispatch time and
read whatever `version.txt` says *then*. Push `X.(Y+1).0--rc1` before they have run and their
`--rc` guards reject the release. The local-only bump keeps `origin/main` sitting on the release
version for as long as the release needs it. The asymmetry is a constraint, not a style choice.

**"push" here means `git push origin main` — not a Docker image publish.** Both are called "push"
around this project and the two got genuinely confused once. If the user's wording is ambiguous, ask
which — do not infer from the word alone.

## 0. Preflight — git

```bash
cat version.txt                            # must be X.Y.Z--rcN; if already non-rc, stop and ask
git rev-parse --abbrev-ref HEAD            # must be main
git status --short                         # must be empty
git log --oneline origin/main..main        # what the push will publish
```

Four things stop the release:

- **Version is already non-rc.** Either a release is half-done or the user means something else. Ask.
- **Not on `main`.** Releases are cut from `main`. Stop.
- **Dirty tree.** The version commit must contain *only* `version.txt` and `README.md` (see step 1),
  so anything uncommitted either belongs in its own commit first or must not land. Report what is
  dirty and wait — never `git add -A` your way through this.
- **Unpushed commits you did not expect.** `origin/main..main` is what step 2 publishes, including
  everything landed earlier. Show the user the list before pushing; a release push is the moment
  unrelated local work escapes.

Do **0b** next, before asking for the go-ahead to drop the rc. Catalog commits (if any) have to
land first so the version commit stays two files, and so the push list you show is complete.

## 0b. Catalog versions — check, offer, commit if accepted

Defaults and fallbacks in `variants/base/setups/` and `templates/` go stale between releases, and
the script pin can disagree with the template pin. Catch that here so this release ships current
stable versions — not after, when the images are already built from the old pins.

This is an **offer**, same shape as the CHANGELOG promotion at the end: report, wait, apply only
what the user picks. "Cut a release" is not consent to bump Go.

### Inventory

Two surfaces; a pin that lives on only one of them is already a finding (script↔template drift).

```bash
# script defaults, *_DEFAULT*, and fallbacks (including FALLBACK_VERSION)
rg -n 'FALLBACK_VERSION=|_DEFAULT(_VER|_VERSION)?=|_VERSION="\$\{1:-' \
    variants/base/setups/*--setup.sh

# template version params (name contains VERSION — not PORT)
rg -n -A3 '\[params\.\w*VERSION' templates --glob '**/template.toml'
```

The regex is a net. Also open any setup whose template has a concrete default — some pins are
bare assignments (`JDK_VERSION="21"`, `NODE_MAJOR=20`) that `${1:-}` / `_DEFAULT` miss.

Skip `variants/base/setups/future/` (abandoned). Skip example Boothfiles — they are snapshots, not
the catalog.

**Not a version pin** — leave them alone:

- channel defaults: `latest`, `stable`, `recommended`, `apt`, empty (distro latest)
- ports and other non-version params
- VS Code / JetBrains extension IDs, apt package names

**Still check** when the template default is `latest` / `stable`:

- the script's fallback (`FALLBACK_VERSION`, `*_DEFAULT_VER`, "fallback when latest cannot be resolved")
- the first concrete (non-`latest`) entry in `suggests`
- script default vs template default disagreeing — report as **drift** even if both look current enough

### Look up current stable

Use the same source the setup already uses. If it curls `api.github.com/repos/<owner>/<repo>/releases/latest`, that is the lookup; otherwise the vendor page it downloads from (go.dev/dl, nodejs.org/dist, python.org, Adoptium, …). Skip prereleases, RCs, nightlies unless the tool itself is a rolling prerelease (roc `alpha4-rolling`).

```bash
gh api repos/<owner>/<repo>/releases/latest --jq '.tag_name'
```

If lookup fails (rate limit, unknown source), put `?` in the table — do not invent a version.

Propose:

| Kind | Target |
| --- | --- |
| CLI tools / single binaries | latest stable |
| Languages / runtimes | current stable or current LTS. Prefer **N−1** (previous stable/LTS) when the newest major is brand-new or is not the LTS — Node current LTS not the odd Current; Python current 3.x that is not a just-cut `.0` |
| Fallbacks for a `latest` default | the same number as latest stable, so a rate-limited build still gets something current |

### Report, then wait

Table: **tool · kind** (`default` / `fallback` / `suggests` / **drift**) **· current · proposed · source**.

No stale pins and no drift → say **No catalog version bumps.** and go to the go-ahead below.

Otherwise wait. Apply only the rows the user picks.

### Apply

How to edit: **`setup-work` §1b**.

Same commit also needs:

- no test edits — a test that breaks on a bump is spelling out a version it should read from the
  catalog; fix it per `tests/README.md` → *Versions are catalog data, not test data*
- a `docs/CHANGELOG.md` Unreleased bullet

One commit for the accepted set (not one per tool unless the user asks). Tree must be clean before
step 1. Re-list `git log --oneline origin/main..main` so the push preview includes these commits.
Do not mix catalog files into the version.txt commit.

## 0c. Catalog item versions — blocking

Every catalog item carries a hand-written `cb-version` and a generated sha256
(`docs/CATALOG_VERSIONING.md`). This step proves the two agree with what shipped last time. It runs
**after** 0b on purpose: a pin bump changes a setup or template, and that change needs its bump.

```bash
build/gen-catalog-manifest.sh          # refresh build/catalog-manifest.tsv
build/check-catalog-versions.sh        # baseline = manifest at the previous release tag
```

The baseline is the highest `X.Y.Z` tag below `version.txt`. A warning that it is not an ancestor
of HEAD means main was never rebased onto that release — stop and find out why.

| Result | Do |
| --- | --- |
| `changed … bump cb-version` | Bump it per the table in `docs/CATALOG_VERSIONING.md` — patch for a fix, minor for something added, major (or a new minor below 1.0.0) for a break. Ask the user when the kind is not obvious from the diff (`git diff <baseline> -- <path>`). |
| `params removed or reordered` | Breaking for `--select` users — a major bump, or restore the order. Ask. |
| `version went down` | A mistake — restore at least the baseline version. |
| `manifest is stale` | Run `build/gen-catalog-manifest.sh` and include the file. |
| `WARN bumped with no change` | Harmless; mention it. |

Commit the bumps plus the regenerated manifest as one commit (`Bump catalog item versions for
X.Y.Z`), separate from the version commit, then re-run the check until it reports `0 fail`. CI runs
the same check on release and refuses to publish when it fails.

## 0d. Apt snapshot — pin it, move the examples to it

`apt-snapshot.txt` is the one apt date a release has. Three things read it, and they must agree:

- **The images.** `build/docker-build.sh` pins every image's own `apt-get` to it (see
  `build/apt-snapshot--source.sh`). In CI, `publish-docker-images.yaml` reads it **once**, in
  `guard-no-rc`, and threads it through `build-base` and `build-variants` as `CB_APT_SNAPSHOT`, so
  the amd64/arm64 matrix jobs cannot drift apart. CI only reads it: a missing file stops the
  release. It no longer picks a date or pushes a commit of its own.
- **The CLI.** `build/cli-build.sh` stamps it into the binary (`aptsnapshot.Release`); it is the
  snapshot `booth config` freezes a **new** booth to, so a fresh booth starts at its image's
  snapshot and never older.
- **The examples.** Their Boothfiles' `env APT_SNAPSHOT=` must be at or after it.

That is why the date is chosen **here**, in a commit, and not in CI: the release binaries are
built from the pushed commit, so a date picked after it would ship a CLI and examples one release
behind the images.

**Why "not older" matters.** The base is built at its snapshot, so its installed packages are that
day's. An example pinned earlier asks apt for an older `-dev` package whose exact-version dependency
the base already has newer, and apt will not downgrade. It reads like a broken archive:

```
libssl-dev : Depends: libssl3t64 (= 3.5.5-1ubuntu3.5) but 3.5.5-1ubuntu3.7 is to be installed
```

(Real: `elixir-example` pinned `20260916` and `systemlib-example` `20260930` on a `20261004` base.)

**Pin a week back, not today.** A snapshot id names a UTC day, and the day it is here can be one the
snapshot service has not published yet. Seven days back exists everywhere — the same rule as
`today` in `booth config` and the build fallback.

```bash
# GNU date, then BSD (macOS)
day="$(date -u -d '7 days ago' +%Y%m%d 2>/dev/null || date -u -v-7d +%Y%m%d)"
echo "${day}T000000Z" > apt-snapshot.txt
./build/cli-build.sh                       # not required for the bump, but keeps ./codingbooth in step
examples/sync-apt-snapshot.sh              # moves every example pinned older, via booth config
examples/ensure-config.sh | tail -1        # must report STALE-APT 0
```

`sync-apt-snapshot.sh` bumps through `booth config --apt-snapshot`, never `sed`, so each example's
`.booth/.generated` fingerprint stays valid. Only older pins move; an empty pin (no freeze) is
kept. Reconfiguring also re-copies template-owned files (`.booth/startups/`, `.booth/setups/`,
seeds under `.booth/shared/`) — **look at the diff and keep only `Boothfile` and `.generated`**
unless a refresh of those is wanted; a `.booth/setups/` copy of a built-in shadows it.

Commit `apt-snapshot.txt` and the examples together (`Pin apt snapshot to <id> for X.Y.Z`),
separate from the version commit. If the pin did not move (re-running a release the same week),
there is nothing to commit.

**Local images built before this commit are older than the new pin.** That is fine — an example
newer than its image installs; only older fails. The next `./build/docker-build.sh` reads the new
pin.

### Go-ahead to drop the rc

Report the version transition, the commit list step 2 will publish (catalog bumps included), and
wait for the go-ahead. Pushing is outward-facing and this project has a private-repo →
retimed-public-history concern, so never push on inferred consent.

## 1. Drop the rc, commit

Use the script — it edits **both** files and validates the format. Do not hand-edit them.

```bash
./build/set-version.sh 0.65.0      # X.Y.Z, no suffix
git diff                           # expect exactly 2 files, 1 line each
git add README.md version.txt
git commit -m "0.65.0"
```

Commit message is **the bare version, nothing else, verbatim** — no prefix, no body. `0.65.0` for a
release, `0.66.0--rc1` for a bump. Copy the string `set-version.sh` was given, suffix and all.

The commit touches **only** `version.txt` and `README.md`. Verified against history: `1eb2846d`
(`0.64.0`) and `27a3eab6` (`0.65.0--rc`) are both exactly those two files. If `git diff --cached`
shows anything else, stop — something got swept in.

## 2. Push main

```bash
git push origin main
git status --short --branch | head -1     # expect "## main...origin/main" with no "ahead"
```

Confirm the absence of an "ahead" marker out loud — that is the proof the release reached the
remote. This is the only push in the skill.

## 3. Bump to the next rc, commit, do NOT push

**Order matters:** the release workflows must have been dispatched (or at least the user must be
done with `origin/main` on the release version) before this is pushed — see the asymmetry note at the
top. Committing locally is always safe; pushing is what would break the guards.

Next **minor**, rc1 — `0.65.0` → `0.66.0--rc1`. (A patch-level reopen would be
`0.65.1--rc1`; only do that if the user says so.)

```bash
./build/set-version.sh 0.66.0--rc1
git add README.md version.txt
git commit -m "0.66.0--rc1"
```

The message is the **exact version string**, `1` included — `0.66.0--rc1`, not `0.66.0--rc`.
(Some older history shows a truncated `0.65.0--rc`. That is not the convention; do not copy it.)

**Do not push this one.** It ends the run one commit ahead of origin, deliberately. Say so
explicitly in the report, because "ahead 1" otherwise reads like an oversight.

## 4. Report

State the two commits, that the release was pushed and the bump was not, and the final `ahead 1`.

Then say plainly **what has and has not happened**: the release version is on `origin/main`, so the
`Release everything` workflow is now *eligible* — but nothing has run, because it is manual dispatch.
Do not imply a release is in flight when nothing has been dispatched.

## 5. Offer to dispatch `Release everything` — then watch it

**Never dispatch without an explicit go-ahead.** Steps 1–4 leave a state that is recoverable: two
local commits and one push. This step is not — it publishes Docker images, creates a GitHub release,
and deploys the live site. Offer it, name what it will publish, and wait. "Cut a release" earlier in
the conversation is not consent for this; ask again here.

Preconditions (steps 1–2 establish them; step 3 preserves them by not pushing):

```bash
git show origin/main:version.txt      # must be the non-rc release version
```

Every job guards on that, so a `--rc` here fails the run rather than publishing something wrong.

```bash
gh workflow run "Release everything" --ref main
sleep 5                                # dispatch is async; the run is not queryable instantly
RUN=$(gh run list --workflow="Release everything" --limit 1 \
        --json databaseId --jq '.[0].databaseId')
gh run watch "$RUN" --exit-status      # non-zero if the run fails
```

`gh workflow run` does **not** print the run id, hence the look-up. Prefer
`gh run watch --exit-status` over polling `gh run list`: it is the only form that lets you tell a red
run from a green one instead of merely reporting "dispatched".

Because `release-all.yaml` calls local reusable workflows, the whole chain is pinned to the commit it
was dispatched against. Pushing the step-3 bump while it runs cannot break it — but there is still no
reason to, so leave it local.

**If the run fails, say which job died and what is already public.** The chain is
`images → release → site` with `needs:`, so a failure stops what follows but does not undo what
preceded:

| Failed job | Already published | Notes |
|------------|-------------------|-------|
| `images` | possibly some image tags | It pushes per-arch by digest, then merges and signs. A late failure (e.g. its integration tests) means signed multi-arch tags are already on Docker Hub. |
| `release` | all images | GitHub release absent or partial. Re-dispatching republishes the images too — harmless but slow. |
| `site` | images + GitHub release | Only the site is stale. Dispatch `Deploy Site to codingbooth.io` alone instead of the whole chain. |

Never re-dispatch on the user's behalf after a failure. Report and ask.

**Do not push the step-3 bump as part of this step.** Reopening the tree stays a separate act, so the
release and the next cycle never collapse into one irreversible command.

## 6. Offer to dispatch the tap's `Bump formulas` — then watch it

Only after step 5's run is **green**: the workflow looks for the newest published release, so a
missing GitHub release just means "nothing newer". It lives in `NawaMan/homebrew-tap`, not here, and
is deliberately **not** part of `Release everything` while the release process matures
(docs/HOMEBREW.md, Phase 3) — so it gets its own offer and its own explicit yes. It pushes to the
public tap, which every `brew upgrade` then picks up. It also bumps the tap's other formulas
(`folio`, `viewmd`) if their projects have newer releases — say so in the offer.

```bash
gh workflow run "Bump formulas" -R NawaMan/homebrew-tap      # add -f dry_run=true to only look
sleep 5
RUN=$(gh run list -R NawaMan/homebrew-tap --workflow="Bump formulas" --limit 1 \
        --json databaseId --jq '.[0].databaseId')
gh run watch "$RUN" -R NawaMan/homebrew-tap --exit-status
```

Report the result from the run's summary: which formulas moved to which version, or "already the
newest". If it fails, nothing is pushed and the release is already out — report and ask; do not
re-dispatch on your own. By hand instead, in a tap clone: `bin/bump-formula.sh
Formula/codingbooth.rb [X.Y.Z]`, then commit and push the tap.

## The GitHub Actions release

**Everything here is `workflow_dispatch` only — pushing does not start any of it.** The push makes
them *able* to run; step 5 runs them. Do not tell the user a release is underway just because the
push succeeded.

| Workflow | File | Produces |
|----------|------|----------|
| **Release everything** | `release-all.yaml` | Nothing itself — sequences the three below with `needs:`, so each waits on the previous succeeding. **Dispatch this one.** |
| **Publish docker images** | `publish-docker-images.yaml` | `nawaman/codingbooth:*` multi-arch images for all 7 variants, cosign-signed, plus integration tests |
| **Release CodingBooth** | `release-binary-and-wrapper.yaml` | GitHub release: multi-platform binaries, the wrapper, examples, SHA256 checksums |
| **Deploy Site to codingbooth.io** | `deploy-site.yaml` | The site, over SSH to DreamHost |
| **Bump formulas** | `bump-formulas.yaml` in `NawaMan/homebrew-tap` | Not in the chain, not in this repo — step 6, by hand after a green release: every tap formula → its newest release |

The three are each still individually dispatchable — `release-all.yaml` only sequences them, and is
the right thing to dispatch for a release. Reach for an individual one when re-running a single
failed step (see the table in step 5).

The image and release workflows read `version.txt` from the checked-out `main` and both **reject
`--rc`** — the docker one via a dedicated `guard-no-rc` job, the release one via a
`Reject pre-release` step. That is the entire reason the release commit has to reach `origin/main`
first.

Two details that make step 1 non-negotiable:

- **`Release CodingBooth` verifies `README.md` matches `version.txt`** and fails on a mismatch. This
  is why `set-version.sh` (which writes both) is mandatory and hand-editing one file is not an option.
- **`Publish docker images` builds natively per-architecture** — amd64 and arm64 each on their own
  runner, pushed by digest, then merged into the multi-arch tag and signed. A local
  `./build/build-all.sh --push` cannot match that: it cross-builds arm64 under QEMU, which is both
  slower and the reason extension installs get deferred there. **Do not publish images from the
  workstation as part of a release.** Local `--push` is for pre-release/RC smoke testing only.

Its variant matrix is `notebook, codeserver, desktop-xfce, desktop-kde, desktop-lxqt,
desktop-wayland` — the same seven images `build/build-all.sh` produces locally, base included. If
that ever diverges again, a release will quietly publish fewer variants than were tested; the matrix
appears twice in `publish-docker-images.yaml` (build and merge) and both must list the same set.

Disk headroom on the runners is the thing most likely to bite a desktop variant: the images are
4–5.7GB and only `desktop-kde`, `desktop-lxqt` and `desktop-wayland` get the "Clean up disk space"
step. `desktop-xfce` is excluded despite being *larger* than lxqt, so that list is reactive rather
than principled — if a desktop build starts failing on space, that condition is the first thing to
widen.

Should you want a local publish anyway (outside a release), one behaviour to know:
`docker-build.sh` skips cosign signing for `--rc` versions but still *requires* a signing key in
preflight whenever `--push` is given (`needs_cosign` is true on push regardless), so it needs
`COSIGN_KEY_FILE`/`COSIGN_KEY` resolvable plus `COSIGN_PASSWORD` if the key is encrypted.

## CHANGELOG — check, don't assume

`docs/CHANGELOG.md` keeps a `## Unreleased` section plus one `## X.Y.Z` per release, **but promoting
`Unreleased` to the released version is not part of the version commit.** Historically it happens
later, in an ordinary feature commit (`## 0.64.0` arrived in `2e503b4d "Put back shell-config"`).

So after a release, `Unreleased` still holds the shipped work. That is the existing pattern, not a
bug. Mention it to the user and offer to promote it — do not silently rename it, and do not add it
to the release commit, which would break the two-file rule in step 1.
