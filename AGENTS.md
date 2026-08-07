# AGENTS.md — Working on CodingBooth

Guidance for an AI agent (Claude Code, Grok, or similar) helping develop **this repository** —
the CodingBooth launcher, templates, variants, tests, and site.

Read `README.md` for the user-facing product overview. This file is the *operator's manual* for
agents working on the codebase.

**Not the same as:**

| Doc | Audience |
| --- | --- |
| **This file (`AGENTS.md`)** | Agents editing *this* git repo |
| `docs/AGENT.md` | Agents running *inside* a booth container |
| `docs/AGENT_SETUP.md` | Helping *users* stand up a booth in their own project |

**Authoring the catalog** — setups, templates, and extensions — has its own set of references. They
describe `variants/base/setups/` and `templates/` in *this* repo, so they are repo work, not user
docs. Start from the **`setup-work`** skill, which is the workflow; these are what it draws on:

| Doc | Covers |
| --- | --- |
| `docs/BOOTH_SETUP.md` | setup script conventions — the startup/profile/starter trio, LEVEL ordering, shared helpers (`skip-setup`, `cb-has-*`, `cb-*-icon`) |
| `templates/README.md` | template *patterns* — Boothfile order bands, arg style, run-args and volumes, autostart + expose, per-order catalogue |
| `docs/AGENT_TEMPLATE.md` | template *schema* — every `template.toml` / `*--extension.toml` key, params, merge rules, catalog guards |
| `docs/AGENT_RECIPE.md` | recipe files (`--select @name`) |

---

## Quick start for agents (read this first)

Get the environment and git shape right before editing. Wrong branch / wrong checkout wastes a
whole session.

**Two hard stops before any feature edit (Rules 0 and 0b):**

1. **Proposal before code** — post Problem · Diagnostic · Approach, then wait (Rule 0).
2. **Linked worktree** — feature work is **not** edited on `main`. Before the first substantive
   write: either you are already under `worktree/<name>/`, or you create that checkout and work
   **only** there. **"Yes" / "go ahead" / "Let's go" authorises the *work*, not the *checkout*.**
   It is never permission to edit the main clone. Full text: Rule 0b and *Session = linked
   worktree + branch* below.

### Proposal before code — study, discuss, then edit

**Default for any change that is not pure Q&A.** Research is fine (read files, search, run
read-only commands). **Writing is not** — no source edits, no scaffolding, no "I'll start while
I explain" — until you have posted a short proposal and the user has replied.

Post **three headings, a few sentences each**, then **stop and wait**:

1. **Problem** — restate what the user wants in plain language, so a mismatch surfaces before
   code.
2. **Diagnostic** — what you found in the tree: what already exists, what is the outlier, which
   constraint bites. Put 1–2 clarifying questions *here* when something is still ambiguous.
3. **Approach** — how you intend to do it, including deliberate non-goals and open choices the
   user should pick. **When the change will touch source**, Approach **must** name the checkout
   in one explicit line — either:
   - **Worktree:** `worktree/<name>` + branch `<name>` (this is the default for feature work), or
   - **Main / here:** only if the user already opted out ("here", "on main", "no worktree") or
     the change is a pure docs/typo one-liner they want on main.

   A proposal that describes the code change but **omits the checkout** is incomplete — fix it
   before asking for a green light. After green light, if you are still on the main clone and
   Approach said worktree, **create the worktree first**; do not start writing on main.

Proceed only when the user agrees, picks an option, or explicitly green-lights
("do it", "implement", "yes", "go ahead"). One approval covers that plan — not every later
surprise; if the approach has to change, re-propose the delta.

**Skip the gate when:**

- Pure questions / orientation with **no** code change
- The user already approved this approach in the **same thread**
- They explicitly skip it ("just implement", "no plan", "don't discuss")
- Mechanical follow-through of an **already-agreed** plan (the next step of work already green-lit)
- A skill's **own** gate already covers the same wait — but **not every skill menu is enough**.
  - `todo-add`: recording an idea is not implementation; no proposal gate (but do not build).
  - `todo-pick`: the menu only chooses *which* feature. After the pick you **still** post
    Problem · Diagnostic · Approach and wait — a one-line pitch is not a plan.
  - `work-start`: its step 2 *is* the form, posted before the worktree exists (replaces a second
    copy of it).
  - `work-finish`: preflight report *as* Problem · Diagnostic · Approach, then wait (replaces a
    second copy of the form).

This is Rule 0 under *Rules you must follow*. **Rule 0b (worktree isolation) is not skipped by a
green light** — it is a separate pre-edit check. Skills that implement things restate both at the
top so they are hard to miss when a skill is loaded alone.

### How to run things (this product repo)

CodingBooth is a **Go CLI + Docker variants + shell setups + templates**. Agents develop it on the
**host** (Go toolchain + Docker). That is different from consumer projects that *use* a booth for
Node/pnpm — here the product *is* the booth tooling.

| Goal | Command |
| --- | --- |
| Build the CLI | `./build/cli-build.sh` |
| Go unit tests | `(cd cli && go test ./...)` |
| Focused package tests | `(cd cli && go test ./src/pkg/booth/ -count=1)` |
| Shell automate suite (subset / as needed) | `tests/run-automate-tests.sh` (long; prefer targeted tests under `tests/…`) |
| Why did a booth call return nothing? | `tests/logs/complex-booth-calls.log` — the complex suite traces every booth call's command, exit code, and stderr (tests themselves discard stderr). Set `CB_DIAG_LOG=<path>` to trace any suite; `CB_DIAG_LOG=/dev/null` to opt out. |
| Rebuild base/variant images | `./build/docker-build.sh base` (or listed variants) — only when the change needs a new image |
| Wrapper smoke tests | scripts under `tests/wrapper/` |
| Blog (`blog/` is GeekPresent) | follow `blog/AGENTS.md` if present; otherwise treat as a nested site |

**Prefer the smallest verification that matches the change.** A pure Go fix should not rebuild
every Docker variant. A setup/script change may need a targeted complex test or a local booth
rebuild — say so in Approach.

**Booths you start while verifying.** Integration tests and manual checks often create Docker
containers named after the project folder. Rules:

- Check `./booth list` (or `docker ps`) before starting something long-lived.
- **Never stop or remove a booth you did not start** — it may be the user's running session.
- Tear down **your** short-lived verification containers when the check is done
  (`./booth stop --name …` / `./booth remove --name …`, or the test harness cleanup).
- Do not invent host fallbacks when the failure is "Docker is down" — stop and tell the user.

**A second booth from the same folder** may get a port suffix on the name. Worktrees are separate
folders, so each worktree gets its own booth name (the folder name). When multiple booths share a
code path, `booth exec` may require `--name` — pick the one you started, or ask.

### Session = linked worktree + branch (GitKraken-visible)

**This is the only setup for isolated agent sessions on this project.** One session folder, one
branch, registered with the main clone so GitKraken lists it.

```bash
# from the main clone root, e.g. ~/dev/git/CodingBooth
mkdir -p worktree
git worktree add worktree/<name> -b <name>    # branch + linked checkout in one step
cd worktree/<name>
claude                                        # or grok / your agent CLI — start it HERE, from inside
```

Start the agent **inside** the folder git already made. Do not use an agent CLI's own worktree
feature to create it (see below).

| Piece | Value | Notes |
| --- | --- | --- |
| Working tree | `<repo>/worktree/<name>/` | Open this in the editor / agent CLI / GitKraken |
| Branch | `<name>` (same as the folder) | Created by `-b <name>`; already checked out |
| Git bookkeeping | `<repo>/.git/worktrees/<name>/` | Auto; **never** open or check out files here |
| Gitignore | `/worktree/` in `.gitignore` | Nested under main → must be ignored |

Check that GitKraken will see it (open the **main** repo, not only the worktree path):

```bash
git worktree list
# …/CodingBooth                      […] [main]
# …/CodingBooth/worktree/<name>      […] [<name>]
```

A healthy linked worktree has a **file** `.git` pointing at the main repo (not a `.git/` directory):

```text
gitdir: /…/CodingBooth/.git/worktrees/<name>
```

**Do not let an agent CLI create the isolation for this project.** Most of them ship a worktree
feature that puts the checkout somewhere *outside* `<repo>/worktree/` — under the tool's own home
directory, or a temp dir:

- **Grok** — `grok --worktree=…` / `grok -w` / Ctrl+W → often a **standalone clone** under
  `~/.grok/worktrees/…` (a full `.git/` directory, not a linked worktree)
- **Claude Code** — `EnterWorktree`, or an agent spawned with `isolation: "worktree"` → a linked
  worktree, but in a scratch location of its choosing

Either way the checkout is **invisible** to GitKraken's worktree list for the main repo, which is
the whole point of the recipe above. Use `git worktree add worktree/<name>` yourself and start the
agent inside it.

If one already exists and the user wants GitKraken: move work aside, `git worktree add
worktree/<name> <branch>` from main, re-apply any uncommitted edits, delete the stray checkout.

Optional: an agent CLI's home-dir bucket can be redirected so accidental paths resolve under the
repo (this does **not** convert a standalone clone into a linked worktree):

```bash
# from main clone — only if you want the path alias
ln -sfn "$(pwd)/worktree" ~/.grok/worktrees/git-codingbooth
```

When the user asks for “a session”, “a worktree”, or a feature checkout: run the recipe above
(or confirm `worktree/<name>` already exists and is linked), then work **inside** that folder.
Prefer the **`work-start`** skill — it judges whether the task really is *work*, folds in the
Rule 0 proposal, and ends with you inside the worktree. Keep `/worktree/` in `.gitignore`.

**Default for feature work: use a linked worktree** (`worktree/<name>` + branch `<name>`) — this
is **Rule 0b**, not a soft preference. Unless the user says otherwise ("here", "on main", "no
worktree") or you are **already** inside one, **stop before the first substantive edit** and create
the checkout from the main clone root:

```bash
mkdir -p worktree
git worktree add worktree/<name> -b <name>
cd worktree/<name>
```

Prefer a short name from the task (`mnemonic-underline`). Tell the user the path and branch. Do
**not** use the agent CLI's own worktree feature (see above). `todo-pick` asks, and defaults the
answer to worktree — hand the setup itself to `work-start`. Do **not** invent a worktree for pure
Q&A, docs-only nits the user wants on main, or a one-line fix they explicitly want in place.

**Pre-edit self-check (feature work) — fail closed:**

- [ ] `pwd` is under `…/worktree/<name>/` **or** the user opted out of isolation
- [ ] `git branch --show-current` is **not** `main` / `master` (unless the user opted out)
- If either box fails: **do not write**. Create or enter the worktree first, then continue.

### Landing a worktree's branch into main

Merging is a deliberate act, same bar as any commit/push (Rule 8) — only when the user asks to
land/merge a worktree's work, never on your own initiative. Prefer the **`work-finish`** skill.
Summary of the procedure:

0. **Preflight (read-only), including a gap audit** — git shape (clean main, behind/ahead,
   merge-tree) **and** land-time **gaps** only: (1) tests that should exist but do not,
   (2) docs not updated for user-visible behaviour, (3) experiments not concluded,
   (4) accidental changes. If none: say **`No gaps.`** only — no checklist walkthrough. If
   some: list them plainly and **wait** (close gaps vs land as-is). Do not auto-fix.
   "Not yet committed" is a process step, not a gap. Full text: `work-finish` skill step 0b.
1. **In the main clone**, stash anything uncommitted so main is clean before the merge
   (`git stash push -u -m "land-<branch>"` — skip if main is already clean).
2. **In the worktree**, rebase the feature branch onto main: `git rebase main`. Resolve conflicts.
   If the rebase touched covered code, re-run the relevant tests (Go unit tests and/or targeted
   shell tests) in that worktree **before** merging.
3. **From the main clone**, `git merge --no-ff <branch>` — a real merge commit, so the worktree's
   commit history is kept. **Never squash.** *Exception:* if the branch is exactly **one** commit
   (`git rev-list --count main..<branch>` = 1), a plain fast-forward `git merge <branch>` is fine —
   there is no history to preserve. Two or more commits ⇒ `--no-ff`.
4. If step 1 stashed anything, `git stash apply <sha>` (not `pop`), confirm, then `git stash drop
   <sha>`.
5. **Clean up the worktree and branch** as part of landing: stop any booth *you* started for that
   worktree, then from the main clone `git worktree remove worktree/<name>` and `git branch -d
   <name>` — both **without** `--force`.

**Never push** as part of landing. The merge in step 3 only ever touches the local `main` —
pushing is its own explicit ask (Rule 8).

### Cleaning up after a session

**Clean up only what you created, and only when the user says the work is done.** A worktree holds
real work — an unmerged branch and possibly uncommitted edits — so removing one is destructive and
is the user's call, never a tidy-up you do on your own initiative. **Exception:** *Landing a
worktree's branch into main* runs worktree/branch removal automatically as the last step of a
successful merge — the merge itself is what makes that removal safe.

Most one-shot test containers need no manual teardown. Persistent `--keep-alive` / `--daemon`
booths pile up:

```bash
./booth list                        # what is actually running, and from which CODE PATH
./booth stop   --name <booth>       # stop a booth you started (add --force if it will not)
./booth remove --name <booth>       # then remove the container if it lingers
```

Then, **from the main clone** (never from inside the worktree you are deleting):

```bash
git worktree remove worktree/<name>   # refuses if there are uncommitted changes — do NOT --force
git branch -d <name>                  # -d only; refuses to drop unmerged work
git worktree list                     # confirm it is gone
```

`--force` on either command silently discards work. If git refuses, that refusal is the point:
stop and tell the user what is unmerged or uncommitted, and let them decide.

**A verification booth you started only for your own check is yours to tear down** when the check
is done. Leave up anything the user asked you to run *for them*. **Never stop a booth you did not
start.** When in doubt, ask.

### Already in a worktree → stay on the feature branch

If this checkout is an **isolated line of work** (not the long-lived main clone), the branch
should already match the folder (`git worktree add … -b <name>`). If you are still on `main` /
`master` inside `worktree/<name>/`, fix that **before the first substantive edit**:

How to tell you are in a worktree (any one is enough):

- Path is `…/worktree/<name>/…`, or `.git` is a file with `gitdir: …/.git/worktrees/…`
- `git rev-parse --git-dir` and `--git-common-dir` resolve to different paths
- The user said this is a worktree / feature session

Then:

1. Prefer branch name = folder name (`…/worktree/volume-bind-filter` → `volume-bind-filter`). Reuse
   that branch if it exists; otherwise `git checkout -b <name>`.
2. Tell the user the branch name so they can push / open the PR when ready.

Still **do not** `git commit`, `git push`, or open the PR unless the user asks (Rule 8). Creating
or switching the branch is the exception.

If you are on a normal day-to-day clone of `main` (no `worktree/<name>` path) and the change is
**feature work** (multi-file behaviour, anything `todo-pick` would offer), **Rule 0b applies** —
create the worktree recipe above before the first write; opt out only when the user says so. Skip
isolation for pure Q&A, tiny docs/typo fixes, or an explicit "do it here / on main". **"Go ahead"
on a plan is not an opt-out.**

---

## Skills — the executable half of this file

The recurring jobs are also shipped as **skills** in `.claude/skills/`, each a checklist that ends
in a working, tested artifact. Prefer the skill when one matches; come back here for the prose and
the background. Implementation skills still obey **Proposal before code** (Rule 0) and **feature
work in a linked worktree** (Rule 0b) — restate both at the top when a skill is loaded alone.
`todo-pick`'s menu is only the first gate (which feature); after the pick it still requires the full
form. `work-start` and `work-finish` are the bookends of a session and each *performs* the form
rather than skipping it — `work-start` as its proposal step, `work-finish` as its preflight report.

| skill | use it when |
| --- | --- |
| `blog-add` | start a blog post under `blog/` as an unpublished draft — reachable by URL, listed nowhere |
| `blog-publish` | make a draft the latest post — rename to the publish date, wire prev/next, index + front page |
| `setup-work` | add, modify, or fix a setup / template / extension — with a workspace to try it in |
| `setup-add` | thin pointer to `setup-work` (kept so the old name still resolves) |
| `todo-add` | record an idea in `docs/TODO.md` only — never implement |
| `todo-pick` | "what's next?" — shortlist open `docs/TODO.md` items, user picks, then build |
| `work-start` | beginning a sizable task — judge it *is* work, propose, then create the worktree + branch |
| `work-finish` | merging a worktree's branch into main — preflight, rebase, tests, `--no-ff`, cleanup |

---

## Rules you must follow

0. **Proposal before code.** For any change that is not pure Q&A: research read-only, post
   **Problem · Diagnostic · Approach** (a few sentences each), and **wait** for the user before the
   first substantive edit. Full text and skips are under *Quick start* → *Proposal before code*.
   Approach must name the **checkout** (worktree vs main) when source will change.
0b. **Feature work runs in a linked worktree — never on main by default.** Before the first
   substantive edit of feature work:
   1. If path is already `…/worktree/<name>/` (or `.git` is a `gitdir:` file), stay there; ensure
      the branch name matches the folder.
   2. Else if on the main clone: from the **main clone root**,
      `mkdir -p worktree && git worktree add worktree/<name> -b <name>`, then **cd into that
      folder** and only edit there. Prefer a short name from the task. Tell the user the path and
      branch.
   3. Do **not** use the agent CLI's own worktree (`grok -w` / `isolation: "worktree"` / Claude
      EnterWorktree) — those checkouts are invisible to GitKraken for this repo.

   **Skip isolation only when:** pure Q&A; docs/typo one-liners the user wants on main; the user
   said "here" / "on main" / "no worktree"; or you are already inside a linked worktree.

   **"Go ahead" on a plan is not permission to edit main.** It authorises the *work*, not the
   *checkout*. Full recipe: *Quick start* → *Session = linked worktree + branch*; executable form:
   the **`work-start`** skill, which also folds in the Rule 0 proposal.
1. **Prefer the smallest honest verification.** Match tests to the change (Go unit tests vs a
   targeted shell test vs a full image rebuild). Do not claim "done" without the check that would
   catch the bug class you touched.
2. **Do not kill the user's booths or long-lived containers.** Only stop/remove what you started
   for your own verification, unless the user asks otherwise.
3. **Keep product docs coherent with behaviour.** When behaviour changes, update the relevant
   `docs/BOOTH_*.md` / CHANGELOG Unreleased section when the change is user-visible. Do not invent
   docs churn for pure internal refactors.
8. **No commit / push / PR / merge unless the user asks.** Landing a branch is only on explicit
   "land" / "merge into main". Never push as part of landing. Creating a worktree branch is allowed
   as part of Rule 0b without a separate commit request; committing still needs an ask.

---

## Orient yourself (30 seconds)

- **CLI:** Go under `cli/src/` (`pkg/booth`, lifecycle, config TUI, …). Built via `./build/cli-build.sh`.
- **Wrapper:** root `booth` shell script (install, shell-config, create, pin binary).
- **Variants:** `variants/{base,codeserver,notebook,desktop-*}/` — Docker images; base holds most
  `setups/*--setup.sh`. Conventions: `docs/BOOTH_SETUP.md`.
- **Templates:** `templates/**/**.toml` — declarative pieces for `booth config` / Boothfile
  generation. Extensions are `<name>--extension.toml` beside a parent `template.toml`. Patterns:
  `templates/README.md`; schema: `docs/AGENT_TEMPLATE.md`.
- **Tests:** `tests/` (unit, config, complex, wrapper, …).
- **Examples:** `examples/workspaces/`.
- **Product TODOs:** `docs/TODO.md` plus specialized lists (`docs/TODO-BINARY_COMPANIONS.md`,
  `docs/TODO-BOOTH-CONFIG.md`, …).
- **Site / blog:** `site/`, `blog/` (GeekPresent static blog).

When unsure where a feature lives, search setups + templates + `cli/src/pkg` before inventing a new
layer.
