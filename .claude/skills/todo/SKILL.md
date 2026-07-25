---
name: todo
description: Add an item to this project's docs/TODO.md, in the house style. Use when the user says "add to TODO", "/todo <thing>", "note this for later", or otherwise wants an idea recorded rather than built. Records only — never implements.
---

# Add a TODO item

`$ARGUMENTS` is the thing to record. Write it into **`docs/TODO.md`** (or a specialized
`docs/TODO-*.md` when the topic clearly belongs there — e.g. binary companions →
`docs/TODO-BINARY_COMPANIONS.md`). Record only: no source edits, no marking anything `[x]`.

**Not an implementation skill.** Recording a TODO does not require the full Problem · Diagnostic ·
Approach wait gate. Do still refuse to *build* the idea here — if the user actually wants it
implemented, point them at building it (or `pick-todo`) and follow `AGENTS.md` Rule 0 there.

## 1. Check it isn't already done

`docs/TODO.md` mixes open items, completed writeups, and abandoned notes — and it lags the code.
Before writing:

```bash
grep -n "^## \|^- \[ \] \*\*\|^- \[ \] " docs/TODO.md
grep -rn "<keyword>" docs/TODO.md docs/TODO-*.md cli/src variants templates 2>/dev/null | head
```

If it exists, **update that entry instead of adding a duplicate**. If it's already built, say so and
stop. If it's *partly* built, say which half is missing and write only that.

## 2. Place it

Pick the section by kind, not by excitement. In `docs/TODO.md` the usual homes are:

- **Code Features** — launcher / pipeline / architecture
- **Features** — user-facing product work
- **Problems** — bugs and behavioural gaps
- **Additional Setups** / **Code Extensions** — catalog gaps
- Or a specialized file when one already owns the domain

Put new items next to related ones.

## 3. Write it in the house shape

```markdown
- [ ] **Name** — one-line summary of what it is.
      Why it's worth doing / the use case it unblocks.
      Approach: name the real mechanism it would reuse (pkg, setup, template, wrapper path).
      Open questions: what must be decided before line one.
```

Keep the approach **grounded in this repo**, not generic:

- CLI → existing `cli/src/pkg/…` packages and commands
- In-container tools → `variants/base/setups/*--setup.sh` + `templates/`
- Config surface → config schema / TUI fields / Boothfile segments
- Wrapper → root `booth` + `docs/implementations/WRAPPER.md`
- Prefer extending an existing pattern over new dependencies or parallel systems

A proposal that reads "rewrite the orchestrator" or "pull in library Y" for a small gap is usually
the wrong proposal — say so when recording if the user is only capturing an idea.

## 4. Record decisions with their reason

When the user settles a question (a label, a name, a tradeoff), write **the decision and why**, plus
what it costs. That's what stops it being re-litigated later, and it's the part a bare checkbox loses.

Prefer the user's own framing; if you think it's wrong, say so once and defer. Then confirm what you
wrote in a sentence or two — don't paste the whole entry back.
