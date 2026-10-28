# Booth on a Worktree: `booth --worktree <name>`

**Status:** planned, nothing built (2026-10-26).

## Problem

A booth on a git worktree already works: `cli/src/pkg/booth/git_worktree.go` mounts the main
clone's git folder, mirrors every worktree's `.git` file read-only, and heals an in-booth
`git worktree repair`. What is missing is the ceremony around it. Today a user runs
`git worktree add …`, `cd`s into it, runs `booth`, and afterwards removes the worktree and the
branch by hand. Nothing in the product does that; this repo only has it as agent skills
(`work-start` / `work-finish`).

There is also no standard place for a worktree. Seen in the wild: `<repo>/worktree/<name>`,
`../<project>_worktree/<name>`, `../.worktree/<name>`, `<repo>/.claude/worktrees/<name>`. A
command that picks one silently would put folders where users do not expect them.

## Goal

One command that owns the whole life of a worktree session, so nothing outside booth has to set it
up or clean it up:

```bash
booth --worktree fix-123 --push -- claude -p "fix issue 123"
```

1. Find the worktree, or create it (checking out or creating the branch).
2. Run the booth in it.
3. On exit, if the work succeeded and `--push` was given, push the branch.
4. Remove the worktree, the local branch and the booth's volumes. The pushed branch is all that
   remains.

**Mental model: booth leaves things the way it found them**, the same as it already treats its
container (removed at exit unless `--keep-alive`):

| At start | At exit |
| --- | --- |
| Worktree **created by this run** | Removed, when safe. `--keep-worktree` keeps it |
| Worktree **already existed** (the user's, or left over from an earlier run) | Always kept. Removing it is `git worktree remove`, not booth |

The branch follows the same rule: booth deletes only a branch this run created. `--keep-worktree`
is the only flag; it has meaning only when this run creates the worktree.

## Non-goals

- Creating worktrees *inside* a booth. In-booth `git worktree` commands write container paths into
  git's records, which is the breakage `git_worktree.go` exists to undo.
- Opening a PR. booth prints the compare URL; `gh pr create` is the user's step.
- Merging or landing into the default branch.
- This repo's own workflow rules (the `x.y.z--<name>` version stamp).
- Windows: the worktree `.git` mount already has an open TODO there.

## Decisions taken

| Question | Decision |
| --- | --- |
| Default mode | a worktree **this run created** is removed at exit when safe; `--keep-worktree` keeps it |
| Pre-existing worktrees | always kept, whoever made them, including a leftover from an earlier run. No `--remove-worktree` |
| Branch | deleted only if this run created it (`git branch -d`, never `-D`) |
| Marker file | none: "did this run create it" is known during the run, nothing is persisted |
| Push target | the branch's upstream; else `origin` (and set it as upstream) |
| Push trigger | `--push` given ⇒ push automatically on success, no prompt. No `--push` ⇒ never push |
| Who pushes | the **host**, after the container exits. The booth never needs push credentials |
| Location | never chosen silently (see *Where a new worktree goes*) |

## Design

### 1. The option and how it resolves

`--worktree <name>` is a bootstrap option, read with `--code`, `--config` and `--profile` before
the config loads (`cli/src/pkg/booth/init/initialize_app_context.go`), because it decides the code
path. Given together with `--code`, it is an error.

1. **Find the main clone.** `git rev-parse --git-common-dir` from the current directory, so it
   works from inside another worktree and never nests one in another. Not a repo, or a bare repo:
   error.
2. **Look it up.** `git worktree list --porcelain`. Match `<name>` against each entry's branch
   (`refs/heads/<name>`), then its folder name.
   - One match: that path becomes `--code`. A `prunable` entry (folder gone): error that suggests
     `git worktree prune`. booth never prunes.
   - Several: error listing their paths.
   - The main clone itself: error ("that is the main clone; run booth there").
3. **No match:** create it (§2).
4. Continue the normal run with `--code <path>`. The worktree's own `.booth/` applies, so a branch
   can carry its own booth. The existing worktree support in `git_worktree.go` is unchanged.

Because lookup goes through git's own list, worktrees made by any tool, in any layout, are found
with no configuration.

### 2. Where a new worktree goes

First rule that applies:

1. `--worktree-root <dir>`.
2. `worktree-root` in the **main clone's** `.booth/config.toml` (the worktree does not exist yet,
   so its config cannot be read). Relative values resolve against the main clone's root.
3. **Existing habit:** the shared parent of the repo's other worktrees, if they share one.
   Entries under `.claude/worktrees/` (Claude Code's own) do not count.
4. **No signal:**
   - In a terminal, ask once, suggesting `../<project>.worktrees/`, and offer to save the answer
     with `booth config --set` so the generated files' fingerprint stays valid.
   - Without a terminal, stop and print the `--worktree-root` flag that fixes it.

For a disposable session (no `--keep-worktree`) with no signal from rules 1–3, the location
matters much less (the folder goes away), so it may default without asking. Where to is still
open; see *Open questions*. With `--keep-worktree`, rule 4 applies as written.

**Creating it**, always on the host:

- Branch `<name>` exists: `git worktree add <root>/<name> <name>`.
- Otherwise: `git worktree add <root>/<name> -b <name> [<from>]`, where `--worktree-from <ref>`
  sets the base (default: current `HEAD`).
- The target folder exists but is not a worktree of this repo: error, never overwrite.
- Remember, for this run only, that the worktree was created and whether the branch was too. §4
  acts on that; nothing is written to disk for it.
- Print one line: `Created worktree <path> on branch <name> (from <ref>)`.

**If the root is inside the repo:** add `/<root>/` to `.git/info/exclude` (local, never
committed; booth never edits a committed `.gitignore`), and warn when `.dockerignore` does not
exclude it, because it would inflate the main clone's build context.

### 3. Carrying `.booth` state over

A new worktree lacks everything gitignored: `.booth/.env`, `.booth/.<profile>--env`,
`.booth/.booth.password`, `cache/`.

- **Copy** `.booth/.env*` from the main clone when the worktree is **created** (never on reuse),
  and list what was copied.
- **Don't copy** `cache/` or the password file: a fresh password per booth is correct, and the
  cache rebuilds.
- Later, maybe: a `.booth/worktree-include` file, one glob per line, for more files to copy.

### 4. Ending a session

Runs only when **this run created the worktree** and `--keep-worktree` was not given. In every
other case booth leaves the worktree and branch as they are (it may still push, see below).

The rule: **clean up only what is safe.** booth decides from git's state, not the exit code alone,
and uses `git worktree remove` / `git branch -d` **without** `--force`. If git refuses, booth keeps
everything and says why. Whenever it keeps a worktree, it prints the path and the reason, so the
default removal is never silent either way.

| At exit | What happens |
| --- | --- |
| Success, clean tree, `--push` succeeded | Remove worktree and booth volumes; delete the branch if this run created it (`-d` passes: the branch matches its upstream) |
| Success, clean tree, no `--push` | Remove the worktree and volumes; **keep the local branch** (its commits live only there) |
| Uncommitted changes | Keep everything; print the path and the reason. No auto-commit, no stash |
| Failure | Keep it, don't push. `booth --worktree <name>` again resumes it (found by lookup) |
| Push rejected (no remote, auth, non-fast-forward) | Keep it; print git's error |
| No commits beyond the base, clean tree | Remove it, and the branch if this run created it: nothing to lose |
| booth killed / crashed | Nothing runs; it stays, and the next run with that name resumes it |

A worktree kept by any of these rows already exists on the next run, so from then on it is always
kept. Leftovers only happen when there was something to keep; the user ends them with
`git worktree remove`.

**Success** means:

- With `-- <command>`: that command exited 0, and the tree is clean.
- Interactive session: the tree is clean and the branch has commits beyond its base. (The
  session's exit code says little.)

`--push` on a success pushes automatically, no prompt, to the upstream or else `origin`
(`git push -u origin <name>` in that case), then prints the compare URL when the remote is a known
host.

**Constraints:**

- `--worktree` with `--daemon` or `--keep-alive`, when it would create the worktree and no
  `--keep-worktree` is given: error. No process would be left to clean up, and the message names
  `--keep-worktree`. On an existing worktree they are fine: nothing is removed anyway. (Later,
  maybe: `booth stop` runs the cleanup.)
- `--push` applies whenever given: on an existing worktree, or with `--keep-worktree`, it pushes
  on success and keeps the worktree.
- `--keep-worktree` on an existing worktree: accepted, no effect.

### 5. Running several at once

- Booth name = folder name, already unique per worktree. Same worktree name across two repos can
  still clash; the `{project}` name placeholders cover it.
- Ports: when the configured port is taken and `--port` was not given, fall back as `NEXT` does.
  (Check today's behaviour first.)
- Volumes: fresh per-name volumes per worktree. That is the isolation story; document it.
  Disposable sessions remove them at the end.

### 6. `booth worktree list` (optional)

`git worktree list` joined with booth status: path, branch, booth name, running/stopped, port.
Read-only.

## Phases

| Phase | Scope | Tests |
| --- | --- | --- |
| **P1: open existing** | §1 without creation. Pre-existing worktrees are never removed, so nothing to clean up yet | Go unit tests on the matcher (porcelain parsing, branch vs folder, ambiguous, prunable, main clone). A dryrun test: `--worktree x` gives the same mounts as `--code <path>` |
| **P2: create + clean up** | §2, §3 (`.env*` copy), §4. Ships together because removal is the default: creating without cleanup would leave folders behind | Unit tests on root choice (each rule, the `.claude/` exclusion) and on the end-state decision (each row of the table, plus created-vs-existing). A complex test on a temp repo: creates, reuses, refuses a foreign folder, writes `info/exclude`, copies `.env`; clean exit removes; dirty tree keeps; failure keeps, and the resumed run keeps it even when clean; `--keep-worktree` keeps; an existing worktree and an existing branch are never removed |
| **P3: push** | `--push` | A complex test with a local bare repo as `origin`: success pushes then removes the created branch and worktree; push on an existing worktree pushes and keeps; push rejected keeps; upstream vs `origin` fallback |
| **P4: comfort** | `booth worktree list`, `worktree-include`, port fallback, completion of names | dryrun + wrapper completion tests |

Docs per phase: new `docs/BOOTH_WORKTREE.md`, link from `docs/BOOTH_RUN.md`, CHANGELOG
Unreleased. Simplifying `AGENTS.md` / `work-start` to use the command waits until P3 has been in
use a while.

## Open questions

1. **Disposable default location** when rules 1–3 give nothing: still ask, or a hidden default
   such as `../.<project>.worktrees/` or `~/.cache/codingbooth/worktrees/<project>/`?
2. **Branch names with `/`** (`feature/x`): folder `feature-x`? Match on either form?
3. **`.env` copy:** always on create, with `--no-copy-env` to opt out? Or only at the prompt?

## Checkout

Implementation in worktree `worktree/booth-worktree`, branch `booth-worktree`, created when P1 is
green-lit.
