---
name: work-start
description: Open a session for a sizable piece of work — judge that it really is "work", post the Problem · Diagnostic · Approach proposal, wait, then create the linked worktree + branch and move into it. Use when the user says "start work on X", "new session", "make a worktree", or asks to begin a feature. The closing bookend is work-finish.
---

# Start a worktree session for a sizable piece of work

The prose version is `AGENTS.md` → *Session = linked worktree + branch* and Rules **0** / **0b**.
This is the executable form, and the opening bookend to **`work-finish`**. `$ARGUMENTS` is the task
(and optionally a name for the worktree).

**Work is not "a change" — it is a change big enough to need its own room.** The test:

> **If you stopped halfway, would the tree be in a state that gets in someone else's way?**

If yes, it's work: it gets a worktree and a branch, so half-done is *contained*. If no, it's a
casual modification — do it in place and don't invent ceremony around it.

**This skill performs the Rule 0 gate; it does not skip it.** Step 2 *is* the
Problem · Diagnostic · Approach proposal. Don't post a second copy later, and don't start editing
because the user said "start work on X" — that names the task, not the plan.

## 1. Decide: is this actually work?

**Usually the user has already decided** — "start work on X", "new session", "make a worktree".
Take them at their word and go to step 2; don't re-litigate a call they've made.

The test earns its keep in the *other* direction: **nobody said "work", and a casual change is
turning into one.** You're three files deep in a "quick fix", or the change is about to leave the
tree half-migrated. That's the moment to stop and say so — *"this is becoming work; want me to move
it to a worktree?"* — rather than quietly carrying on and leaving `main` mid-surgery. Step 4 exists
precisely to rescue the edits you've already made.

The table below is for that judgement call. Getting it wrong costs the user in either direction.

| It's **work** — worktree + branch | It's **not** — just do it here |
| --- | --- |
| Multi-file behaviour change; anything `todo-pick` would offer | Pure Q&A, reading, orientation |
| Leaves the tree un-shippable partway through | Docs/typo one-liner the user wants on main |
| Needs its own booth, image rebuild, or test run to prove | A one-line fix they explicitly want in place |
| You expect several rounds of review before it lands | A change already scoped to a file the user has open |
| Touches the CLI, variants, setups, or templates together | Editing a skill, a TODO entry, a comment |

**When it was your call rather than theirs, say which way you called it in one line** before doing
anything else. If it isn't work, stop here: tell the user you're doing it in place and get on with
it — Rule 0b explicitly says *do not* invent a worktree for Q&A, docs nits, or a one-liner.

**Already inside a linked worktree?** Then the session exists. Don't nest a second one. Confirm the
branch name matches the folder (`git branch --show-current`), fix it if not, and go straight to
step 2 for the proposal.

## 2. Propose, then wait (Rule 0)

Research read-only first — read the files, search the tree, run read-only commands. Then post
**three headings, a few sentences each**, and **stop**:

1. **Problem** — restate what the user wants in plain language, so a mismatch surfaces before code.
2. **Diagnostic** — what you found in the tree: what already exists, what's the outlier, which
   constraint bites. Put 1–2 clarifying questions here if something is still ambiguous.
3. **Approach** — how you intend to do it, deliberate non-goals, and open choices for the user.
   **Approach must name the checkout in one explicit line** — here that is
   `worktree/<name>` + branch `<name>`, plus your verdict from step 1.

Proceed only on agreement or an explicit green light. One approval covers *that plan* — if the
approach has to change later, re-propose the delta.

## 3. Name it

Prefer a short mnemonic from the task, matching the house style (`volume-bind-filter`,
`mnemonic-underline`). **Folder name = branch name** — that is what makes the session legible in
`git worktree list` and GitKraken. Check it's free:

```bash
git worktree list                    # is there already a worktree/<name>?
git branch --list <name>             # is the branch taken?
```

## 4. Rescue in-progress edits on main (only if there are any)

Common case: the user started hacking on `main`, then realised it's work. Those edits belong in the
new worktree. `git worktree add` won't move them — a new worktree is a clean checkout.

```bash
git -C <main-clone> status --short           # empty? skip this whole step, and say you skipped it
```

If it's dirty, decide *whose* changes they are — unrelated edits should stay on main. To move them:

```bash
git -C <main-clone> stash push -u -m "start-<name>"
git -C <main-clone> stash list --format='%H %gs' | grep "start-<name>"   # capture the SHA
```

Address the stash **by SHA**, never bare `git stash pop` — the stash stack is shared across every
worktree and parallel session, so a bare pop can swallow someone else's work. You'll apply it in
step 6.

## 5. Create the linked worktree

From the **main clone root**:

```bash
mkdir -p worktree
git worktree add worktree/<name> -b <name>    # branch + linked checkout in one step
```

Then prove it's the real thing — a *linked* worktree, visible to GitKraken:

```bash
test -f worktree/<name>/.git && echo OK       # a FILE containing "gitdir: …", not a directory
git worktree list                             # must list <repo>/worktree/<name>  [<name>]
```

**Do not use the agent CLI's own worktree feature** — not Claude Code's `EnterWorktree`, not an
agent spawned with `isolation: "worktree"`, not `grok -w` / Ctrl+W. Those put the checkout under
the tool's home or a temp dir (Grok's is a standalone clone, not even a linked worktree), where
it is **invisible** to GitKraken's worktree list for the main repo — which is the entire point of
this recipe. Run `git worktree add` yourself, at the path above.

`/worktree/` is already in `.gitignore` (it's nested under the main clone, so it must be). Leave
that alone.

## 6. Move in

```bash
cd worktree/<name>
```

If step 4 stashed something, bring it across now — `apply`, then `drop` only once you've eyeballed
the result:

```bash
git stash apply <sha>       # apply, NOT pop — keeps it recoverable if it conflicts here
# check the working tree, then:
git stash drop <sha>
```

**Pre-edit self-check — fail closed. Both boxes must pass before the first substantive write:**

- [ ] `pwd` is under `…/worktree/<name>/`
- [ ] `git branch --show-current` is **not** `main` / `master`

If either fails: **do not write.** Fix the checkout first.

## 7. Report and begin

Tell the user, plainly:

- the **path** (`worktree/<name>`) and the **branch** (`<name>`);
- that the branch is created but **nothing is committed** — committing is still its own ask
  (Rule 8; creating the worktree branch is the one exception);
- that they can open `worktree/<name>` in GitKraken or an editor, and that if they'd rather run a
  fresh agent inside the session they can start one from that folder;
- that the session ends with **`work-finish`**, which rebases, tests, merges (`--no-ff`, or a
  fast-forward if the branch is a single commit), and removes the worktree and branch.

Then start the approved work — in that folder, and only there.

## Rules
- **Judge first, ceremony second.** A worktree for a typo wastes the user's time as surely as
  editing main for a feature risks their tree.
- **"Go ahead" authorises the work, not the checkout.** It is never permission to edit the main
  clone. Neither is "start work on X".
- Never `git commit` / `push` / open a PR here (Rule 8). This skill creates a branch; that's all.
- One session, one worktree, one branch. Don't nest, and don't reuse another session's folder.
- Booths are per-folder, so this worktree gets its own booth name. Check `./booth list` before
  starting anything long-lived, and never stop a booth you didn't start.
