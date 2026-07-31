---
name: work-finish
description: Land a worktree's feature branch into main — preflight (gap audit: missing tests, stale docs, unfinished experiments, accidental changes), wait for close-gaps vs land-as-is, rebase, tests, --no-ff merge (fast-forward allowed for a single-commit branch), then delete the worktree/branch. Use when the user says "land this", "merge the branch", "merge into main", or asks to finish a worktree session. Never pushes.
---

# Land a worktree's branch into main

The prose version is `AGENTS.md` → *Landing a worktree's branch into main*. This is the executable
form. `$ARGUMENTS` is the branch (default: the branch checked out in the worktree you are in).

**Merging is a deliberate act — Rule 8.** Only run this when the user asks to land/merge, never on
your own initiative, and never because "the change is done". **Never push** — the merge in step 4
only ever touches the local `main`; pushing is its own explicit ask. Cleanup (worktree + branch) is
different: it now runs automatically as the final step, once the merge itself has made the work
safe — see step 7.

**This skill's own Proposal before code gate** (replaces the generic `AGENTS.md` form — do not
stack both): after the read-only preflight below (including the **gap audit**), report as
**Problem · Diagnostic · Approach** — git shape, **any gaps** (owner definition below), and the
exact rebase→test→merge plan, naming which merge form step 4 will use (or "close gaps first, then
land") — and **wait** before stash /
rebase / merge / gap-closing edits. The user's original "land this" is not enough once preflight
can change the plan (conflicts, dirty main, branch behind, open gaps).

## 0. Preflight — establish the shape before touching anything

Every command here is read-only. Run them all, then report what you found.

```bash
git worktree list                     # where is the branch checked out?
git -C <main-clone> status --short    # is main clean? (empty = yes)
git log --oneline main..<branch>      # what is being landed
git log --oneline <branch>..main      # is the branch behind? (non-empty ⇒ rebase needed)
git merge-tree --write-tree main <branch> >/dev/null; echo $?   # 0 = clean, 1 = conflicts
```

`merge-tree` is a genuine dry run — it writes nothing to the index or working tree.

**Check where the worktree actually lives.** It must be `<repo>/worktree/<name>` — a linked
worktree whose `.git` is a *file* containing `gitdir: …`. If an agent CLI put it somewhere else
(`.claude/worktrees/<name>`, `~/.grok/worktrees/<name>`), it is invisible to GitKraken. Fix it
*before* landing, per `AGENTS.md` → *Session = linked worktree + branch*:

```bash
# from the main clone, with the work already committed on the branch
git worktree remove <stray-path>              # no --force; commit or remove scratch files first
mkdir -p worktree
git worktree add worktree/<name> <branch>     # same branch, documented location
test -f worktree/<name>/.git && echo OK       # a FILE, not a directory
```

**Land process (not a "gap"):** if the worktree has intentional uncommitted work and
`main..<branch>` is empty, say clearly that a **commit on the feature branch is required before
merge** — separate from the gap audit. If there is nothing to land (no commits and no intentional
work), stop and do not invent a merge.

### 0b. Gap audit (read-only, then tell the user)

**Owner definition of a gap at land time** — only these four. Do not redefine "gap" as "not yet
committed" or as a full polish wishlist.

Against the branch diff (`git diff main...<branch>` and any uncommitted work intended to land),
mark each **ok**, **gap**, or **n/a** (one line why):

| Gap | Meaning | How to look |
| --- | --- | --- |
| **1. Tests that should have been added but were not** | Behaviour changed and no matching test (or no plan in re-verify) would catch the bug class. | Diff touches CLI / setup / wrapper / logic → expect Go and/or shell test under `tests/` or `*_test.go`. Rule 1. |
| **2. Documents that have not been updated** | User-visible behaviour changed but product docs / CHANGELOG / TODO checkbox lag. | `docs/BOOTH_*.md`, `docs/CHANGELOG.md` Unreleased, example READMEs if the change is about an example; TODO `[x]` if the work came from TODO. Rule 3. |
| **3. Experiments that were not concluded** | Scratch, spike, half-wired path, or open design left in the tree as if finished. | `experiments/`, WIP comments, disabled tests, "parked" branches of code, TODO/FIXME that block the claim of done, half-added templates/setups with no way to use them. |
| **4. Accidental changes** | Diff noise not part of the feature. | Unrelated file churn, debug prints, local paths, commented-out experiments, drive-by renames, mixed-in work from another task, secrets, generated junk that should not land. |

**Also list, but not as gaps:** pure process notes (must commit first; branch behind main; main
dirty with *other* work that must not be merged by accident).

**Do not** auto-fix gaps.

**Reporting gaps — keep it short:**

- **No gaps** → say only **`No gaps.`** (or “No gap.”). Do **not** walk the four rows, do not
  justify each “ok”, do not restate the checklist.
- **One or more gaps** → list each gap in plain language (what / why it counts). Skip categories
  that are fine; no full matrix of ok/n/a.

In **Approach**, if there **are** gaps, offer both paths and **wait**:

1. **Close the gaps** — user says e.g. "close the gaps", "fix tests/docs", "finish experiments",
   "drop the accidental bits"; then edit/commit on the feature branch, re-check, and only then
   continue from step 1.
2. **Land as-is** — user says e.g. "land as-is", "finish as is", "merge anyway", "skip gaps";
   then proceed with known gaps left in place (re-mention only if re-verify fails).

If **no gaps**, Approach is only the land plan (commit if needed → rebase → test → merge); still
**wait** for green light on that plan (git shape may still need a decision).

Fold git verdict **and** the gap line into **Problem · Diagnostic · Approach**, then **wait**
before step 1.

## 1. Stash main only if it is dirty

Skip entirely when step 0 showed main clean — and say that you skipped it.

The stash stack is **shared across every worktree and every parallel session**, so a bare
`git stash` / `git stash pop` can swallow or discard someone else's work. Tag it and address it by
SHA:

```bash
git -C <main-clone> stash push -u -m "land-<branch>"
git -C <main-clone> stash list --format='%H %gs' | grep "land-<branch>"   # capture the SHA
```

## 2. Rebase the branch onto main

```bash
git -C worktree/<name> rebase main
```

Resolve conflicts as they come. Run **git on the host**.

## 3. Re-verify in that worktree

A rebase that touched covered code invalidates whatever you ran before it. Prefer the **smallest
suite that matches the diff**:

```bash
cd worktree/<name>

# Always safe baseline for CLI changes:
./build/cli-build.sh
(cd cli && go test ./...)

# If the diff touches shell tests, wrapper, or setups, also run the matching scripts, e.g.:
#   tests/wrapper/030-shell-config.sh
#   tests/complex/test-boothfile-…/test--….sh
#   tests/unit/…
```

Do **not** rebuild every Docker variant unless the change requires a new image to prove the fix.
Do **not** merge on a red suite — report the failures and stop.

Never stop or reuse a long-lived booth you did not start (`./booth list` first).

## 4. Merge, from the main clone

```bash
cd <main-clone>
git merge --no-ff <branch>
```

A real merge commit, so the branch's history is kept. **Never** `--squash` — squashing is what
destroys that history.

**Single-commit exception.** If `git log --oneline main..<branch>` (step 0) shows exactly **one**
commit, a plain fast-forward is fine — there is no multi-commit history to preserve, and a merge
commit would only wrap a single commit in a second one:

```bash
git rev-list --count main..<branch>    # 1 ⇒ fast-forward is allowed
git merge <branch>                     # plain merge; after the rebase this fast-forwards
```

Two or more commits ⇒ back to `--no-ff`, no judgement call. When you take the exception, say so in
the step 6 report ("single commit, fast-forwarded") so the missing merge commit is never a surprise.

For the `--no-ff` path, write the message to a file and pass `-F <file>`; `-F -` (heredoc on stdin)
fails with `could not read file '-'` in some environments.

## 5. Restore the stash, if step 1 took one

```bash
git -C <main-clone> stash apply <sha>    # apply, NOT pop
# eyeball the working tree, then:
git -C <main-clone> stash drop <sha>
```

`apply`-then-`drop` keeps the stash recoverable if restoring onto the just-merged main conflicts.
`pop` would already have discarded it.

## 6. Report the merge

Show the graph and where main now sits:

```bash
git -C <main-clone> log --oneline --graph -5
git -C <main-clone> status --short --branch | head -1    # "ahead N" — nothing is pushed
```

Confirm the "ahead N" line out loud — that is the proof nothing was pushed.

## 7. Clean up the worktree and branch

The merge already made the work safe in `main`, so this is no longer a separate ask — it's the
last step. Stop any booth you started for this worktree first (skip if you never started one;
never stop one you did not start):

```bash
./booth list                          # confirm it's yours before stopping it
./booth stop --name <name>            # skip if you never started this worktree's booth
```

Then, **from the main clone** (never from inside the worktree being removed):

```bash
git worktree remove worktree/<name>   # NO --force — refuses on any uncommitted change
git branch -d <name>                  # NO --force/-D — refuses to drop unmerged work
git worktree list                     # confirm it is gone
```

**A refusal here is the feature, not a bug to route around.** `-d` (lowercase) only ever drops a
branch git can already see is fully merged; `worktree remove` only ever refuses when there is
something uncommitted it would otherwise discard. If either refuses, **stop** — report exactly
what is unmerged or uncommitted and let the user decide. Never reach for `--force` / `-D` to push
past that refusal.

Then **stop**. Say explicitly that nothing was pushed, and that the worktree/branch are gone.

## 8. Session close line (required when the land is complete)

When **all of** the following are true:

1. **Gaps** — there were **no open gaps** at land time, **or** every gap was **closed** before
   merge (not “land as-is” with known leftovers), and
2. **Merge** — the merge succeeded (`--no-ff`, or a fast-forward under the single-commit
   exception), and
3. **Cleanup** — worktree remove + branch `-d` succeeded (or the user already had no worktree),

…end the report with an **explicit done signal** so the user knows they can walk away. Use plain
language, for example:

> **All done.** Gaps closed, branch merged into local `main`, worktree/branch removed. Nothing
> was pushed. **You can close this session.**

Optional one-liners after that (push still pending, unrelated dirty files on main) are fine; do
**not** bury the “session can be closed” line.

**Do not** use that line if: re-verify failed; merge failed; cleanup refused; or the user chose
**land as-is** with remaining gaps (say what is left instead).
