---
name: release-push
description: Cut a release from the current --rc version — drop the rc suffix in version.txt and README.md, commit, push main to origin, then reopen the tree by bumping to the next minor --rc1 and committing that WITHOUT pushing. Use when the user says "release", "cut a release", "make the version non-rc", "/release-push", or asks to publish the current version.
---

# Cut a release and reopen the tree

Two commits, exactly one push, and one dispatch that needs its own yes.

```
1. version.txt/README.md: X.Y.Z--rcN → X.Y.Z    → commit "X.Y.Z"
2.                                               → git push origin main
3. version.txt/README.md: X.Y.Z → X.(Y+1).0--rc1 → commit "X.(Y+1).0--rc1"  → NO push
4. report
5. offer to dispatch `Release everything`, wait for a yes, then watch it
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

## 0. Preflight — read-only, then report

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

Report the version transition, the commit list step 2 will publish, and wait for the go-ahead.
Pushing is outward-facing and this project has a private-repo → retimed-public-history concern, so
never push on inferred consent.

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
