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

The asymmetry is the point: the release lands on the remote, the reopening stays local so the next
cycle's first real commit carries it up.

**"push" here means `git push origin main` — not a Docker image publish.** Both are called "push"
around this project and the two got confused once already. Publishing images is
`./build/build-all.sh --push`, a separate ~1h act with its own decision (see *Images* below). If the
user's wording is ambiguous, ask which — do not infer from the word alone.

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

Commit message is **the bare version, nothing else** — that is the house convention
(`git log` shows `0.64.0`, `0.65.0--rc`). No prefix, no body.

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

Next **minor**, rc1 — `0.65.0` → `0.66.0--rc1`. (A patch-level reopen would be
`0.65.1--rc1`; only do that if the user says so.)

```bash
./build/set-version.sh 0.66.0--rc1
git add README.md version.txt
git commit -m "0.66.0--rc"
```

Note the message drops the `1`: history uses `0.65.0--rc` for version `0.65.0--rc1`. Match that.

**Do not push this one.** It ends the run one commit ahead of origin, deliberately. Say so
explicitly in the report, because "ahead 1" otherwise reads like an oversight.

## 4. Report

State the two commits, that the release was pushed and the bump was not, and the final
`ahead 1`. Then stop.

## Images — deliberately not part of this skill

Publishing `nawaman/codingbooth:*` is a separate act: `./build/build-all.sh --push` (add
`--no-cache` for a clean rebuild), roughly an hour for all seven variants.

**It must run while `version.txt` still says the release version**, i.e. between steps 2 and 3 — the
version is baked into the image tags. Running it after step 3 publishes `0.66.0--rc1` images, not
the release.

One behaviour worth knowing: `docker-build.sh` **skips cosign signing for `--rc` versions** but
still *requires* a signing key in preflight regardless (`needs_cosign` is true whenever `--push` is
given). So a non-rc release build is the one that actually signs, and it needs
`COSIGN_KEY_FILE`/`COSIGN_KEY` resolvable plus `COSIGN_PASSWORD` if the key is encrypted.

If the user wants images too, do it between steps 2 and 3 and say so; otherwise leave it alone.

## CHANGELOG — check, don't assume

`docs/CHANGELOG.md` keeps a `## Unreleased` section plus one `## X.Y.Z` per release, **but promoting
`Unreleased` to the released version is not part of the version commit.** Historically it happens
later, in an ordinary feature commit (`## 0.64.0` arrived in `2e503b4d "Put back shell-config"`).

So after a release, `Unreleased` still holds the shipped work. That is the existing pattern, not a
bug. Mention it to the user and offer to promote it — do not silently rename it, and do not add it
to the release commit, which would break the two-file rule in step 1.
