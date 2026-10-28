# Booth on a Git Worktree

> Run a booth on a git worktree by name: `booth --worktree <name>`. booth finds the worktree, or
> creates it, and leaves the repository the way it found it when the booth exits.

Back to [README](../README.md) · [booth run](BOOTH_RUN.md)

---

## Quick start

```bash
booth --worktree fix-123 -- claude -p "fix issue 123"
```

1. No worktree `fix-123` yet, so booth creates one on a new branch `fix-123`, starting at your
   current commit, in `../<project>.worktrees/fix-123`.
2. The booth runs there: `/home/coder/code` is the worktree, with a working git.
3. When the booth exits, booth removes the worktree again, if nothing would be lost. Commits stay
   on the branch `fix-123`.

On a worktree that already exists, `booth --worktree <name>` just opens it, and leaves it in place.

Add `--push` to push the branch when the run succeeds; then only the pushed branch remains:

```bash
booth --worktree fix-123 --push -- claude -p "fix issue 123, and commit the fix"
```

## The rule: booth leaves things the way it found them

The same as booth's own container, which is removed at exit unless `--keep-alive`:

| At start | At exit |
| --- | --- |
| The worktree was **created by this run** | Removed, when nothing would be lost. `--keep-worktree` keeps it |
| The worktree **already existed**: yours, another tool's, or kept by an earlier run | Left in place. Remove it with `git worktree remove` |

The branch follows the same rule: booth deletes only a branch this run created, and only when it
has no new commits.

### When a created worktree is kept

booth removes a worktree only with `git worktree remove` and `git branch -d`, never `--force`, and
checks first. It keeps the worktree, and prints its path and the reason, when:

| At exit | What happens |
| --- | --- |
| Clean, no new commits | Worktree and the new branch removed |
| Clean, with new commits | Worktree removed; **branch kept**, with its commits |
| Uncommitted changes or untracked files | Worktree kept |
| The booth exited non-zero | Worktree kept |
| No longer on its branch (switched inside the booth) | Worktree kept |
| `--keep-worktree` | Worktree kept |

With `--push`, the push happens first, and only on success: the local branch then matches the
remote, so it is deleted too (see [Pushing the branch](#pushing-the-branch)).

**A restart is not an exit.** The Restart button or `booth--restart` starts a fresh container on the
same worktree; cleanup happens only when the booth really exits.

A kept worktree already exists on the next run, so from then on it is left in place:
`booth --worktree <name>` resumes it, and `git worktree remove` ends it.

**Ignored files do not keep a worktree.** git removes them with the folder, so build output and
`node_modules` go away with it, and so would anything written to an ignored path. Commit what you
want to keep. booth's own runtime files (`.booth/.tmp/`) never count as work.

**Not covered:** if booth itself is killed, or the booth fails before it starts (a config error),
nothing runs at exit and the new worktree stays, as an existing one from then on.

## Pushing the branch

`--push` pushes the branch when the booth exits, **from the host**: the booth never needs your push
credentials. There is no prompt.

- **Where:** the branch's upstream, if it has one. Else `origin`, which becomes its upstream
  (`git push --set-upstream origin <name>`). With neither, nothing is pushed.
- **When:** only if the run succeeded: the booth exited 0, nothing is uncommitted, and the worktree
  is still on its branch. Otherwise booth says why it did not push, and keeps the worktree.
- **Then:** a worktree this run created is removed as usual, and its new branch is deleted (`git
  branch -d`), since the remote has it. A new branch with no commits is not pushed at all.
- **Existing worktree, or `--keep-worktree`:** booth pushes, and leaves the worktree in place.
- **Exit code:** when `--push` was given and booth did not push (uncommitted work, a rejected push,
  no remote), booth exits 1 even though the booth exited 0. A script can tell. A branch with nothing
  new is not a failure.

Any hint the remote sends back, such as GitHub's link to open a pull request, is printed. booth
does not open the pull request itself.

`--push` needs the booth to end within the command, so it does not combine with `--daemon` or
`--keep-alive`. (`booth build --push <registry>` is a different option: it pushes an image.)

## How the name is matched

booth asks git for its worktrees (`git worktree list`), so it finds one wherever it lives:
`worktree/<name>` inside the repository, `../<project>_worktree/<name>`,
`.claude/worktrees/<name>`, or anything else. There is nothing to configure.

1. **By branch:** the worktree that has branch `<name>` checked out (`--worktree feature/x`).
2. **Else by folder name:** the worktree whose folder is called `<name>`.
3. **Else:** create it (below).

It works from the main checkout or from inside any other worktree of the same repository.

| Case | Result |
| --- | --- |
| More than one matches by folder name | Error listing their paths; use `--code` with one |
| `<name>` is the main checkout | Error: run booth there without `--worktree` |
| The worktree's folder was deleted | Error: `git worktree prune` drops git's stale record |
| Given together with `--code` | Error: both choose the code path |

## Creating a worktree

`<name>` is the branch. If the branch exists (and no worktree has it), booth checks it out; if not,
booth creates it at `--worktree-from <ref>`, default your current `HEAD`. A branch with `/` gives a
nested folder: `feature/x` goes in `<root>/feature/x`.

**Where it goes,** first rule that applies:

1. `--worktree-root <dir>`.
2. **Where your worktrees already are:** the folder the repository's other worktrees share, if they
   share one. Claude Code's `.claude/worktrees/` does not count.
3. `../<project>.worktrees/`, beside the main checkout.

booth prints the path it created. A root inside the repository is added to `.git/info/exclude`
(local, never committed), so it does not show in `git status`. booth never edits `.gitignore`.

**`--daemon` and `--keep-alive`** outlive the command, so nothing would be left to remove the
worktree: on a worktree booth would create, they need `--keep-worktree`.

**`--dryrun`** prints where the worktree would go and stops; it creates nothing.

## The booth's name

The booth is named after the worktree's branch, with `/` turned into `-`: `--worktree feature/x`
and `--worktree x` (by folder) open the same booth, `feature-x`. A detached worktree is named after
its folder. A `name` in `config.toml`, or `--name`, still wins.

## Options

| Option | Meaning |
| --- | --- |
| `--worktree <name>` | The worktree to run on: found by branch or folder, else created |
| `--worktree-root <dir>` | Where a new worktree goes |
| `--worktree-from <ref>` | Where a new branch starts (default `HEAD`) |
| `--keep-worktree` | Keep the worktree this run creates |
| `--push` | Push the branch when the run succeeds (to its upstream, else `origin`) |

They are bootstrap options, read before the config file, like `--code`. `booth express` does not
take them.

## Git inside the booth

A booth on a worktree has a working git: booth mounts the main clone's git folder at the path the
worktree's `.git` file points to, and keeps an in-booth `git worktree prune` or `git worktree
repair` from breaking your other worktrees. Run `git worktree add`, `remove` and `prune` on the
host, not in the booth.

## Not yet

- **Untracked local files**, such as `.booth/.env`, are not in a new worktree: `git worktree add`
  brings only committed files. A booth on a new worktree starts without them.
- **Volumes** the booth used (`booth-pgdata-{name}`) are not removed with the worktree.

## Listing worktrees

`booth worktree list` shows every worktree of the repository, with the booths running on each, so
you can see which worktree has which booth:

```text
$ booth worktree list
BRANCH     BOOTH      STATUS   PORT   PATH
main       -          -        -      /home/me/proj  (main checkout)
feature/x  feature-x  Running  11000  /home/me/proj.worktrees/feature/x
fix-123    -          -        -      /home/me/proj.worktrees/fix-123
```

A booth belongs to a worktree when its code path is that worktree's folder. `--json` prints the
same as an array, each worktree with its `booths`. Shell completion offers the names `--worktree`
takes: the worktrees, then the local branches that have no worktree yet.

## Several booths at once

Each worktree gets its own booth name, and its own per-booth volumes. Ports do not clash by
default either: booth's default port is `NEXT`, so a second booth takes the next free one. A
project that pins a fixed `port` in `config.toml` gets an error for the second booth, saying the
port is in use; give that run `--port NEXT`.
