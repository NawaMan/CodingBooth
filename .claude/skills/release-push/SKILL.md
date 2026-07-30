---
name: release-push
description: Cut a release from the current --rc version — drop the rc suffix in version.txt and README.md, commit, push main to origin, then reopen the tree by bumping to the next minor --rc1 and committing that WITHOUT pushing. Use when the user says "release", "cut a release", "make the version non-rc", "/release-push", or asks to publish the current version.
---

# Cut a release and reopen the tree

Four steps, in order. Two commits, exactly one push.

```
version.txt/README.md: X.Y.Z--rcN → X.Y.Z   → commit "X.Y.Z"        → git push origin main
                       X.Y.Z      → X.(Y+1).0--rc1 → commit "X.(Y+1).0--rc"  → NO push
```

**Why push at all: the actual release runs in GitHub Actions, off the pushed non-rc version.**
Nothing is released from the workstation. Two workflows read `version.txt` out of `origin/main`, and
both **refuse to run on a `--rc` version**. So pushing the non-rc commit is what makes a release
possible; the workflows are then run to perform it. See *The GitHub Actions release* below.

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

Then say plainly **what has and has not happened**: the release version is on `origin/main`, and the
two GitHub Actions workflows are now *eligible* but have **not** run — they are manual dispatch. Ask
whether to trigger them (`gh workflow run "Release CodingBooth"` /
`gh workflow run "Publish docker images"`), or leave that to the user. Do not imply a release is in
flight when nothing has been dispatched. Then stop.

## The GitHub Actions release

Two workflows do the release. **Both are `workflow_dispatch` only — pushing does not start them.**
The push makes them *able* to run; someone still has to run them, from the Actions tab or
`gh workflow run`. Do not tell the user a release is underway just because the push succeeded.

| Workflow | File | Produces |
|----------|------|----------|
| **Release CodingBooth** | `release-binary-and-wrapper.yaml` | GitHub release: multi-platform binaries, the wrapper, examples, SHA256 checksums |
| **Publish docker images** | `publish-docker-images.yaml` | `nawaman/codingbooth:*` multi-arch images, cosign-signed, plus integration tests |

Both read `version.txt` from the checked-out `main`, and both **reject `--rc`** — the docker one via
a dedicated `guard-no-rc` job, the release one via a `Reject pre-release` step. That is the entire
reason the release commit has to reach `origin/main` before either can run.

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
