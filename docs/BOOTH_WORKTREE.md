# Booth on a Git Worktree

> Run a booth on one of your repository's git worktrees by name: `booth --worktree <name>`.

Back to [README](../README.md) · [booth run](BOOTH_RUN.md)

---

## Quick start

```bash
git worktree add ../myproj.worktrees/fix-123 -b fix-123   # once, any layout you like
booth --worktree fix-123                                   # from anywhere in the repository
```

`--worktree fix-123` finds the worktree and runs the booth with it as the code path, exactly as if
you had run `booth --code ../myproj.worktrees/fix-123`. The worktree's own `.booth/` is used, so a
branch can carry its own booth setup.

## How the name is matched

booth asks git for its list of worktrees (`git worktree list`), so it finds a worktree wherever it
lives: `worktree/<name>` inside the repository, `../<project>_worktree/<name>`,
`.claude/worktrees/<name>`, or anything else. There is nothing to configure.

1. **By branch:** the worktree that has branch `<name>` checked out (`--worktree feature/x`).
2. **Else by folder name:** the worktree whose folder is called `<name>`.

It works from the main checkout or from inside any other worktree of the same repository.

| Case | Result |
| --- | --- |
| No worktree matches | Error: see `git worktree list` |
| More than one matches by folder name | Error listing their paths; use `--code` with one |
| `<name>` is the main checkout | Error: run booth there without `--worktree` |
| The worktree's folder was deleted | Error: `git worktree prune` drops git's stale record |
| Given together with `--code` | Error: both choose the code path |

`--worktree` is a bootstrap option, read before the config file, like `--code`. `booth express`
does not take it; express uses `--code`.

## Git inside the booth

A booth on a worktree has a working git: booth mounts the main clone's git folder at the path the
worktree's `.git` file points to, and keeps an in-booth `git worktree prune` or `git worktree
repair` from breaking your other worktrees. See the CHANGELOG entry *"git works in a booth opened on
a git worktree"*. Run `git worktree add`, `remove` and `prune` on the host, not in the booth.

## Several booths at once

The booth name defaults to the folder name, so each worktree gets its own booth, and its own
per-booth volumes. Two booths need two ports: give each its own, or use `--port NEXT`.
