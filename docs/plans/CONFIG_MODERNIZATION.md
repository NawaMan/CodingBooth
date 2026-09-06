# Config modernization — briefing for agent sessions

How to start (and continue) work on the **booth config Web UI**. This is the
note you hand a new agent. The product spec and design handoff are the source
of truth; this file is only the session recipe.

| Doc | Role |
|---|---|
| [`config-web-ui.md`](config-web-ui.md) | Product spec |
| [`config-web-ui-handoff/`](config-web-ui-handoff/) | Design handoff (look and behaviour, not production code) |
| [`../BOOTH_CONFIG.md`](../BOOTH_CONFIG.md) | Current CLI |
| [`../BOOTH_CONFIG_TUI.md`](../BOOTH_CONFIG_TUI.md) | Current TUI |

---

## Open the session folder first

Feature work is **not** edited on `main`. Create a **linked** worktree from the
main clone, then start the agent **inside that folder**. Do not use the agent
CLI’s own worktree (`grok -w`, `isolation: "worktree"`, Claude EnterWorktree) —
those checkouts are invisible to GitKraken for this repo.

Do **not** reuse `worktree/config-web-ui`. That branch is the discarded TUI
clone. A new branch from `main` is the restart.

From the main clone:

```bash
cd /home/nawa/dev/git/CodingBooth   # or wherever the main clone is
mkdir -p worktree
git worktree add worktree/config-web -b config-web
cd worktree/config-web
```

Then start grok / Claude from `worktree/config-web`.

A healthy linked worktree has a **file** `.git` pointing at
`.git/worktrees/config-web`, and `git worktree list` (from the main clone)
shows both trees.

---

## First message to paste (new session)

```text
Start work on the booth config Web UI. Follow work-start, then implement.

This is a native-web booth config, same job as the TUI, not a TUI port.

Read, in this order:
1. docs/plans/CONFIG_MODERNIZATION.md  — this briefing
2. docs/plans/config-web-ui.md         — product spec (source of truth)
3. docs/plans/config-web-ui-handoff/README.md — design handoff
4. docs/BOOTH_CONFIG.md and docs/BOOTH_CONFIG_TUI.md — current behaviour
5. cli/src/pkg/boothinit/  — engine you must reuse (selection, compiler, output)

Do not:
- Recreate the TUI (tabs, one category at a time, list+detail).
- Port worktree/config-web-ui/cli/src/pkg/boothinit/configweb/static/index.html
  or the handoff’s in-browser resolver / catalog.js / x-dc markup.
- Edit the main clone. Stay in this worktree.
- Persist public/TLS/password. Don’t live-reconfigure a running booth.

Do:
- Host-side loopback UI, one-shot token, same ConfigResult → write path as the TUI.
- Catalog from TemplateRegistry JSON, not a hand-written list.
- Groups = the seven meta.toml categories (not the prototype’s eight).
- Default lens = All (Popular still means primaries + current picks).
- Recreate the handoff’s behaviour and density (package always visible,
  extensions only in parent context, preview before save, keep-mine vs
  type-to-replace, undo, tri-state settings).
- Salvage from branch config-web-ui only the server ideas (listen, token,
  session → ConfigResult). Rebuild the client.

First slice: journey A from the spec — pick go + python, codeserver, a
user-owned publish, preview Boothfile/config/DSL, save. Prove it with the
smallest honest test (Go unit + a config/config-tui-style check as needed).

Post Problem · Diagnostic · Approach (name this worktree) and wait if
work-start requires it; I already want this built.
```

The last sentence is the green light so the agent does not stall on Rule 0
after this plan has already been chosen.

---

## Locked decisions (v1)

- **Many templates, not one.** Polyglot is normal.
- **Groups** = the seven `templates/*/meta.toml` categories. Do not invent
  Databases / Browsers as extra groups; tags and search cover that.
- **Default lens** = All. Popular remains a lens and means primaries **plus**
  anything already selected (a reopened booth never hides a current pick).
- **Same compile/write pipeline** as `--no-tui` / TUI. Produce a `ConfigResult`.
  Do not grow a second generator. Do not port `catalog.js`.
- **Host-side** loopback + one-shot token. Not in-container `/config`. Save
  writes files; it does not live-reload a running booth.
- **Hand-written files:** keep-mine (`.new`) is the default; replace requires
  typing a confirmation word. A stray pointer action must not replace.

---

## Later sessions (same branch)

Start the new agent in `worktree/config-web` again. First message:

```text
Continue the config Web UI on this worktree/branch (config-web).
Read docs/plans/CONFIG_MODERNIZATION.md, then the spec and handoff.
Don’t port the old TUI clone. Next unfinished journey in the spec after
whatever is already working. Stay on this branch; don’t commit unless I ask.
```

If the tree might be dirty, add: run `git status` and `git log --oneline -15`
before touching files.

---

## Do not parallelize the UI

One worktree, sequential slices (journey A → preview/save safety → rest of the
catalog). Two agents on the same client will fight. A second session is useful
only for tests or docs after the first slice exists.

Landing this branch into main is **`work-finish`**, and only when asked. Never
push as part of landing.
