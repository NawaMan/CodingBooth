# Config Web UI — product spec

**Status:** Spec only. Not implemented. Restart of the `config-web-ui` attempt,
which cloned the TUI in a browser and is not the direction.

**Design handoff:** [`config-web-ui-handoff/`](config-web-ui-handoff/) — HTML prototype
and catalog snapshot from 2026-09-06. Reference for look and behaviour, not
production code. It will not render from this folder alone: the zip did not
include `support.js` or the Nocturne `_ds/` stylesheet the HTML links.

**Starting an agent session:** [`CONFIG_MODERNIZATION.md`](CONFIG_MODERNIZATION.md).

**Audience:** a web designer (or an agent helping one) inventing a *native web*
experience for `booth config`. This file describes what the user must be able to
accomplish and how the domain relates. It does not prescribe layout or chrome.

**Source of truth:** current `booth config` TUI (`docs/BOOTH_CONFIG_TUI.md`),
CLI (`docs/BOOTH_CONFIG.md`), template schema (`docs/AGENT_TEMPLATE.md`),
compiler merge rules, and the live catalog under `templates/`. Items not encoded
in that source are marked **assumption**.

**Hard rules for anyone designing from this spec:**

- Do not name widgets or chrome. Speak in capabilities: select, filter, compare,
  preview, group, depend-on, confirm, persist, undo, share.
- Do not prescribe layout.
- Always keep prerequisites, cardinality, grouping, and co-visibility.
- Call out TUI habits that the web must replace.
- Prefer web strengths: glanceable overview, search, multi-select, preview
  without committing, deep links, undo, progressive disclosure, responsive use,
  keyboard and pointer.

Related: [booth config](../BOOTH_CONFIG.md), [config TUI](../BOOTH_CONFIG_TUI.md).
The in-booth overlay ([BOOTH_UI_OVERLAY](../BOOTH_UI_OVERLAY.md)) is a different
product — not this.

---

## 1. Product job

Help a developer (or an agent helping them) assemble a **coherent CodingBooth
environment for one project directory**: pick any number of catalog items,
attach only the add-ons that belong to those items, set the booth’s runtime
shape (how you reach it, what it publishes, what it persists), and leave with
generated project files they can review, reuse, reconfigure, and share. The web
version must make the catalog scannable, the parent/child and conflict rules
obvious, and the *effect* of a choice visible before anything is written — not a
sequence of full-screen lists that happen to run in a browser.

This is the same job as `booth config` today. It is **not** a running-booth
control panel, not an in-container editor, and not a Dockerfile authoring tool.

---

## 2. Domain objects

**Project (target directory)** — the folder being configured. Cardinality:
exactly one per session. Owns the `.booth/` tree. An existing project may
already hold a generated configuration, hand-written files, local templates,
and recipes.

**Catalog** — the set of templates the session can choose from. Built from the
product’s shipped templates, optionally a **specific release** of that catalog
(`templates version`), plus any **local templates** from this project’s
`.booth/templates/` (a local name overrides the stock one). Catalog size today:
190+ templates across seven categories.

**Category (template group)** — a named collection used to browse (Languages,
Middlewares, Tools, AI Tools, IDEs, Desktop, Education). A template belongs to
**exactly one** category in the current data model. Cross-cutting findability is
via **tags**, not multi-group membership.

**Template** — a named, selectable starting piece (language, tool, middleware,
IDE, …). Globally unique name. Contains: short and long description, tags,
prominence flag (`primary`), parameters, declared dependencies (`requires`
other templates), optional contributions to booth settings (variant, port,
timezone, docker-in-docker, sudo, commands, run-args, build-args, cache/shared
paths, files, startup/build segments). May have **zero or more extensions**. May
declare architectures it cannot install on, plus a note naming the substitute.
Selecting it is allowed even then; the tool is skipped at build time rather than
failing the booth.

**Extension** — an add-on that exists **only under one parent template**. Not
meaningful, and not offered as a global bag, until that parent is known. May
have its own parameters, dependencies (`requires` other *templates*), and an
**auto-select** flag (included when the parent is chosen, unless the user opts
out). Typical families: linters, package installs (`*-pkg`), credential mounts,
`vscode-ext`, server `autostart` / `expose`.

**Standalone package/template** — a catalog item that *looks* like an add-on but
is a top-level template because it must work without a specific parent.
Examples: `apt-pkg`, `brew-pkg`, `code-ext-pkg` (editor extensions by
marketplace id — the editor comes from the **variant**, not from a `codeserver`
template), `jetbrains-plugin-pkg`. Treat these as templates, not as extensions
of an IDE.

**Parameter** — a named knob on a template or extension (version, vendor, port,
package list, …). Has a default, optional suggested values, and may be
**variadic** (open-ended list, e.g. packages). A default may **reference**
another parameter (`${SVC_PORT}`), so some values follow others until the user
pins them. Parameters exist only while their owner is in the selection.
Positional order in the template file is the mapping used by the shareable DSL.

**Dependency** — a hard `requires` edge from a template or extension to another
**template** (e.g. `kotlin` requires `java`). Selecting the depender pulls the
dependency (and *its* auto-select extensions) into the selection. Recursive.

**Auto-select inclusion / exclusion** — when a parent is selected, auto-select
extensions join the selection. The user may drop them; that opt-out is
first-class (`~name` in the DSL) and must survive save/reload, otherwise the
next resolve puts them back.

**Selection** — the user’s current package of choices:

- zero or more templates (polyglot is normal: `go` *and* `python` *and*
  `claude-code`)
- for each selected template, a subset of its extensions
- parameter values for those items
- explicit exclusions of auto-select extensions
- booth settings (below)

Zero templates is valid: an empty booth with only runtime settings.

**Booth settings** — the runtime shape written to `config.toml` (plus a few
session-only values). Grouped in the current product as: General (variant, port,
offset-base, name, templates version), Container, Egress, Build, Advanced,
Network & Volumes (user-owned expose / env / mount), Cache, Shared, Session,
Temp, Debug. Most people only need variant, port, and extra publish/env/mount.
Many fields are “unset = booth default”; some are tri-state (unset / on / off)
because the product default is *on* and a plain off/on would be unable to
persist “off”.

**Variant** — how the running booth is reached: base terminal, notebook,
codeserver, desktop-xfce/kde/lxqt/wayland, or a direct host-terminal session
(`terminal`). Independent of template selection, but some templates only pay
off on certain variants (JetBrains IDEs need a desktop; `vscode-ext` /
`code-ext-pkg` need an editor; kernels need notebook). That pairing is mostly
**documented convention**, not a hard `requires` on the variant. `codeserver`
exists as **both** a variant and a template (the template installs code-server
into a non-codeserver image).

**User-owned vs template-owned run-args** — templates contribute short-form
Docker flags (`-e`, `-v`, `-p`). The user’s extra env / mount / publish are
long-form (`--env`, `--volume`, `--publish`). Docker treats them the same; the
product uses the spelling to know what the user may edit. On reload, only
user-owned entries come back as editable extras; template contributions
reappear because the template is selected.

**Port roles (three knobs, three jobs)**

- **Booth port** — host port for the booth’s own UI.
- **Offset base** — what a `+OFFSET` publish counts from (defaults to the booth
  port so two local booths don’t collide).
- **Per-service publish** — a template’s `expose` extension: container listen
  port vs host publish port. Host may be a number, `+OFFSET`, or
  `${ENV:-default}`. A template `+expose` *moves* that service’s mapping; a
  user-owned extra publish *adds* another mapping and will double-bind if aimed
  at the same container port.

**Recipe** — a named, reusable selection in the same DSL, typically under
`.booth/recipes/`. Loadable by name, path, or URL; composable with further
picks.

**Generated configuration** — what save writes under `.booth/`: `Boothfile`,
`config.toml`, generated startups, setups/home/home-seed from templates,
`.generated` fingerprints, `.gitignore`. User-authored startups (no generated
header), setups, and home files **survive** regeneration. Save **rewrites**
Boothfile and config.toml from the selection; it does not edit them in place.

**Hand-written / drifted file** — a Boothfile or config.toml that config did
not write, or wrote and a human then changed. Detected via `.booth/.generated`
fingerprints (header alone is not enough). Regenerating would destroy work the
selection cannot reproduce.

**Shareable description** — the selection DSL plus the flags that become
settings (`--variant`, `--port`, `--env`, …). This is what the generated file
headers record, and what `--no-tui` accepts. It is the portable form of a
selection, independent of this machine’s last session.

**Architecture warning** — host (or build) architecture vs a template’s
`unsupported-arch`. Does not block selection. Must be visible at choose-time,
with the substitute named.

---

## 3. User jobs

Grouped by workflow, not by surface.

### Orient and browse

The user needs a way to:

- See the landscape of the catalog without committing — categories, prominence,
  and what a pick unlocks.
- Narrow by category, by “popular / primary”, by already-selected, by **local**
  (when the project has any), by tag, and by free-text over name, description,
  and extensions.
- Search the **whole catalog at once**, including items hidden by the current
  prominence filter, without starting over or visiting each group in turn.
  (TUI habit to replace: type-to-filter still lives inside one category; other
  groups only get a “has matches” mark.)
- Inspect a template enough to decide: purpose, constraints, parameters,
  extensions, dependencies, architecture note, which variant it assumes.
- Contrast two close templates (what they include, which extension families
  they unlock, which variant they assume) without a prescribed comparison
  chrome — just the need to compare.
- Keep already-chosen items visible while browsing the rest, so reopening a
  booth never hides a current pick behind “popular”.

Success: someone who does not know template names can find “Go + linter + VS
Code in the browser” without walking seven isolated lists.

### Build a selection

The user needs a way to:

- Choose **any number** of templates as the base set (including none).
- Only **after** a template is in the selection, see and add/remove **that
  template’s** extensions.
- Understand why an extension is unavailable (wrong parent, parent not chosen,
  conflict, missing prerequisite).
- Add or remove extensions without losing the parent or the rest of the set.
- Have auto-select extensions join when a parent is chosen, and opt out of them
  without the next save putting them back.
- Have hard dependencies join automatically, with a visible explanation of
  *why* they appeared.
- Set parameters only while their owner is selected; get suggested values *and*
  a custom value; for package lists, add/remove many entries, paste several at
  once, and see the pin syntax that manager uses while typing.
- Change a parameter that others follow (service port → host port) and see the
  follower update until they pin the follower.
- Change the template set later and be told which extensions, parameters, and
  settings will drop or need re-picking **before** that change sticks.
- Deselect a template and have its extensions and their parameters drop with
  it.

Success: the selection is always explainable as “these parents, these children,
these pins,” and a bad combination is visible before accept.

### Shape the booth (settings)

The user needs a way to:

- Choose a variant and understand, in the context of the current selection,
  whether the IDEs / kernels / editor extensions they picked will actually have
  a home.
- Set the booth port and, if they publish services, understand offset-base vs
  per-service host ports.
- Add extra publishes, env vars, and mounts that are **theirs**, distinct from
  what templates already contribute — and see template-owned mappings as
  consequences of the selection, not as a second copy to edit.
- Reach the long tail of settings (egress, idle, cache/shared, build, debug)
  without those dominating the first encounter. (TUI habit to replace: every
  setting lives in one equal-weight scroll.)
- Leave a setting **unset** so the booth default applies; explicitly turn a
  default-on switch **off** (sudo, open-browser).
- Never be offered start-time-only exposure (`public` / TLS / password) as
  something this tool can persist. Those are not configuration; storing them
  would expose every clone.

Success: a typical “codeserver on a free port, app on 3000” is obvious; the
other forty settings are reachable without being the product.

### Review, preview, accept

The user needs a way to:

- Review the whole selection as **one package** (templates, extensions, pins,
  variant, user-owned extras) before accepting.
- Preview the **effect**: generated Boothfile, config.toml, and the shareable
  DSL — without writing files. (TUI habit to replace: the TUI has no live
  generated-file preview; `--dryrun` only prints after confirm.)
- See compile errors in selection terms (conflicting variant/port/param,
  duplicate host port, `--expose` that *adds* a mapping a `+expose` already
  owns) before save.
- Confirm destructive work (overwrite hand-written files; discard unsaved
  edits).
- Save and get the same artifacts `booth config --no-tui` would write.
- Optionally start the booth after a successful save (CLI `--start`).

Success: the user can answer “what will this do to my project?” before they do
it.

### Reconfigure, reuse, share

The user needs a way to:

- Open an existing project and see its current configuration as the baseline
  (header selection + config.toml + preserved pins).
- Change one thing without silently resetting unrelated version pins.
- Load a recipe, then add/remove on top of it.
- Export or copy the shareable description (DSL + settings).
- Name/keep a recipe so they can come back to it. (**Assumption:** creating
  recipes from the web session is in scope as export; today recipes are files
  the CLI can *read*. v1 recommendation: copy/export is enough; a recipe
  manager is out.)
- Bookmark or share the current draft selection so another person or agent can
  open the same state. (TUI habit to replace: no URLs; state is “whatever is in
  this terminal.”)

### Protect existing work

The user needs a way to:

- Learn **on open**, before they configure, that the project has hand-written
  Boothfile/config.toml — a heads-up, not a blocker; nothing is written until
  save.
- On save, choose **keep mine** (generated content written beside as `.new`,
  originals untouched) or **replace** (originals kept as `.bak`). Replacing must
  take deliberate confirmation, not a reflex. Keep-mine is the safe default.
- Leave without saving and only be asked if the session actually differs from
  how it opened (including a value still being typed). Selecting then
  deselecting the same item is not a change.
- Know that user startups/setups/home and unrecognized `config.toml` keys
  survive a save.

---

## 4. Selection and dependency rules

**Order of availability**

1. Catalog and settings are always available.
2. Extensions of template T are available only while T is in the selection (or,
   if search lands on an extension, choosing it **implies** T — the parent must
   come along and become visible). Extensions must not be offered as a global
   flat list.
3. Parameters of an item appear only while that item is selected.
4. Egress sub-settings only apply while egress is on.
5. Editor-extension ids (`code-ext-pkg`) need *an* editor variant (codeserver
   or a desktop). They must not require the `codeserver` *template*; desktop
   variants already have an editor.

**Cardinality**

- Templates in a selection: 0..N. Names unique; selecting the same template
  twice is invalid.
- Extensions per template: 0..N, each at most once.
- One variant, one booth port, one offset-base.
- User-owned expose/env/mount: 0..N each.

**Implications of a pick**

- Selecting T selects T’s `requires` (recursively) and T’s auto-select
  extensions. Those implications must be visible, not silent.
- Selecting an extension selects its parent if missing, then that parent’s
  dependencies and auto-selects, then the extension’s own `requires`.
- Deselecting T deselects all of T’s extensions and clears their parameters.
- Opting out of an auto-select extension must be stored as an exclusion, not
  merely “unchecked until next resolve.”
- **v1 rule (TUI gap closed):** keep a required dependency until every depender
  is gone. If the user insists on dropping it, offer to drop the dependers too,
  or show that save would pull the dependency back. Do not silently re-add on
  save with no explanation. (Today the live TUI lets you deselect `java` while
  `kotlin` stays selected; save-time resolve then pulls `java` back.)

**Invalid together (must be visible before accept)**

- Two selected items setting the same scalar to different values: variant,
  port, timezone, dind, sudo, cmds, or the same parameter name. Merge is
  **match-or-error**. Arrays (run-args, build-args) combine and dedupe.
- Two publishes on the **same host port** (including landing an offset on the
  booth port). Two publishes of the same *container* port on *different* host
  ports are legal.
- User-owned extra publish aimed at a container port a selected `+expose`
  already publishes: it **adds** a second mapping, it does not move the first.
  The user needs a way to learn that and to move the host port on the extension
  instead.
- Param values containing DSL separators (`/`) must be quoted in the shareable
  form; the UI should not require the user to know that, but the exported DSL
  must be valid.
- `public` / TLS / password cannot be part of the saved configuration.

**Switching / dropping**

- Dropping a template is potentially destructive to its extension set and pins;
  that cost must be visible before it sticks.
- Changing variant does not drop templates, but it can make some picks
  pointless (JetBrains on `base`, `code-ext-pkg` on `notebook`). That mismatch
  should be visible as a **warning, not invalid**. Do not auto-change variant
  (templates may also *set* variant, and two templates setting different
  variants is a hard conflict).
- Changing **templates version** recompiles against a different catalog;
  missing names and changed defaults must be surfaced.

**Prominence vs availability**

- `primary` only affects default browsing, not whether an item can be chosen.
- Search bypasses the prominence filter so a hidden name is still findable.
- Popular default = primaries **plus anything already selected** (and parents
  of selected extensions), so a reopened booth doesn’t hide kotlin because it
  isn’t primary.

---

## 5. Grouping, filtering, comparison

- Templates must be groupable by category (current catalog: seven groups, one
  membership each). Do not invent overlapping groups the catalog does not have.
  Tags and search are the cross-cutting axes.
- Additional axes that must stay usable on a catalog this size: prominence
  (primary), local-vs-stock, already-selected, tags, free-text intent
  (“linter”, “postgres”, “jetbrains”).
- The user must move between “browse by group” and “find by name/intent”
  without losing the selection or starting over. (TUI habit: one group at a
  time is the only view; search does not produce a catalog-wide result set.)
- Related things should stay in context: a template together with its
  extensions, parameters, dependencies, and architecture note. (TUI habit:
  highlight a row to learn anything; the rest of the selection lives on other
  groups.)
- When two templates are close, the user should be able to contrast them
  (includes, extension families, variant assumptions, architecture) — need to
  compare, not a prescribed widget.
- Settings should be groupable the same way the TUI already groups them, but
  with progressive disclosure: common (variant, port, extras) vs the long tail.
- Template-owned publishes/env/mounts should be reviewable **next to** the
  template that contributed them, not mixed into the user-owned lists.

---

## 6. Feedback and safety

**Preview without committing**

- Preview the effect of adding/removing a template or extension (what else will
  join, what will drop, what settings it contributes).
- Preview generated Boothfile and config.toml, and the shareable DSL, before
  write.
- Preview architecture skip: choosing `google-chrome` on arm64 is allowed, but
  the user must see that it will **not** install and what to use instead, at
  choose-time — not in a later failed (or silently incomplete) build.

**Confirm destructive work**

- Hand-written files: heads-up on open; on save, keep-mine (`.new`) vs replace
  (`.bak`). Replace requires typing a confirmation word in the TUI today; the
  web intent is the same *deliberateness*, not the same keystroke. A stray
  pointer action must not be enough.
- Discarding the session: ask only if the draft differs from the open baseline.
  Looking around is not editing.
- Overwriting a previously generated (non-drifted) config is normal
  reconfigure; do not treat it as hand-written destruction.

**Recover mistakes**

- Revert the last meaningful change to the selection (TUI has no undo; cancel
  is all-or-nothing).
- Closing the session without save leaves the project untouched.
- After replace, `.bak` exists; after keep-mine, originals are intact and
  `.new` is merge scratch (gitignored).

**Status of long or fallible work**

- Catalog load, compile, and write can fail. Show progress and a clear
  success/failure with the error in selection terms.
- Save is not a live reload of a running container. The next `booth` run (or
  rebuild) picks the files up. Don’t imply the running booth just changed.
  **Assumption:** if a booth is already running on this project, say so; don’t
  steal its port.

**Validity while editing**

- Incomplete typing is allowed; accept is not, until compile would succeed — or
  accept is blocked with the reason.
- Duplicate host ports and scalar conflicts should appear as the user composes,
  not only at save.

---

## 7. Persistence and sharing

**What is saved (on accept)**

- Regenerated `.booth/Boothfile` and `.booth/config.toml` from the selection
  (or `.new` beside them).
- `.booth/.generated` fingerprints of what config wrote.
- Generated startups/setups/home/home-seed from the selected templates.
- User-owned expose/env/mount as long-form run-args; template contributions as
  short-form (re-derived from selection).
- Non-default parameter pins as `arg` lines; defaults omitted so a later
  catalog bump can move them.
- Unrecognized existing config.toml keys pass through.
- User startups/setups/home without a generated header are not touched.
- Session-only: templates version (header, not a setting); debug dump (this run
  only); booth-version lock file.
- Never saved: `public`, password, TLS paths; which directory was configured.

**What survives refresh / reopen**

- **Assumption (match TUI):** an in-progress draft does not have to survive a
  killed session; the source of truth after save is `.booth/`. A web draft that
  survives refresh *during the session* is a web strength and should, if it
  exists, restore the same selection.
- Reopening the project reloads the Boothfile header (selection, variant, port,
  cmds, sets) plus config.toml (user-owned run-args, cache/shared). Flags
  passed at launch override that baseline. List flags replace the whole list
  (that is how an entry is removed).
- Version pins in the Boothfile are preserved across reconfigure unless the new
  selection overrides them. Derived ports (host following service) re-derive; a
  real pin survives.

**What is bookmarkable / shareable**

- The selection DSL + settings flags are the portable form (already written
  into file headers). The web UI should be able to express the current draft
  that way so it can be copied, turned into a recipe, or opened as a deep link
  (**assumption / web strength**).
- **v1 draft identity:** stateless share form = DSL + settings. Live session =
  one-shot token until Save or Quit, matching today’s TUI process. Do not
  invent a cloud draft.
- Recipes are the named, reloadable form. Loading `@name` / a path / a URL is
  current product behavior. v1: export/copy is enough; a recipe manager
  (list/edit/delete) is out.

**What is exportable**

- Generated Boothfile and config.toml (preview or write).
- The DSL equivalent of the current selection (including `~` exclusions and
  quoted params).
- **Assumption:** a downloadable recipe file from the current selection.

---

## 8. Anti-patterns (do not copy from the TUI — or from `config-web-ui`)

The existing web attempt recreated the TUI: exclusive category partitions,
config as a sibling of Languages, one list plus a detail pane, prominence
chips, check-then-save. That is the thing not to do.

| TUI habit | Web intent that replaces it |
|---|---|
| Isolated lists: Config, then Languages, then Middlewares, … with no selection in view | Glanceable overview of the **whole package** plus search; groups are a way to scan, not a forced path |
| One group visible at a time; search only filters that group | Catalog-wide search and scan; grouping without losing context |
| Extensions listed under every parent even when the parent is unselected; picking an extension is just another row | Extensions only in the context of their parent; availability computed from the current template set |
| Hide the parent once you start looking at extensions (or bury it on another group) | Parent stays visible with its children |
| Full-screen (full-tab) forms; open a row to learn anything | Summary and detail coexist; inline validation |
| Every config.toml key in one equal scroll | Progressive disclosure: common runtime shape vs long tail |
| User-owned and template-owned run-args distinguished only by who remembers the convention | Template contributions shown as effects of the selection; user extras clearly theirs |
| No generated-file preview until after confirm (`--dryrun`) | Preview without committing |
| No URLs; state is this terminal process | Shareable description / deep-linkable draft |
| No undo; discard is all-or-nothing | Revert last meaningful change; confirm only when there is something to lose |
| Keyboard-linear focus as the main path (with mouse bolted on) | Search, scan, and pointer as first-class; keyboard still works |
| Architecture skip as a mark and a footer flash | The skip and the substitute stay readable at choose-time |
| Hand-written guard as a blocking full-screen then a type-the-word full-screen | Same deliberateness and the same two outcomes (keep / replace); not a clone of the dialog flow |
| Popular/All/Selected as the only way the catalog is tractable | Those *meanings* matter (especially “don’t hide current picks”); the chip row does not |

Also do not:

- Walk groups → templates → extensions as three disconnected steps.
- Present extensions before a parent exists.
- Imply that exactly one template is the “base.” This product is a **set**.
- Treat `code-ext-pkg` as a child of the codeserver template.
- Persist start-time exposure settings.
- Live-edit a running container and call it save.
- Recreate ncurses layout in CSS.

---

## 9. What must stay visible together

This is the information-architecture constraint. It still does not prescribe
layout.

**Always in view while composing (the “package”):**

- That this session is configuring **this project directory**.
- The **current selection as a set**: each chosen template, its chosen
  extensions, notable pins (non-default params), variant, booth port.
- Whether the draft **differs** from how the session opened.
- Whether save would **touch hand-written files**.
- Whether the draft **would compile** (or the first blocking reason).

**Together when inspecting or changing one template T:**

- T’s identity (name, short purpose, category, primary/local, architecture skip
  + substitute).
- T’s **extensions**, clearly children, only if T is selected (or about to be,
  if search landed on a child).
- T’s **parameters**, only while T is selected.
- T’s **requires** and anything already pulled in because of T.
- What T contributes to settings (run-args, variant, ports) as *effects*, not
  as a second copy of the user-owned lists.
- Auto-select children, marked as default-on, with opt-out preserved.

**Together when changing variant or port:**

- The variant meaning (how you will reach the booth).
- Templates/extensions that **assume** a variant (desktop IDEs, kernels,
  editor-extension ids) and whether they have a home.
- Booth port, offset-base, and per-service publishes — three knobs, so the user
  can see that moving the booth port moves `+OFFSET` publishes unless
  offset-base is pinned.

**Together when editing a package-list parameter:**

- The list of entries.
- That manager’s pin syntax (from the item’s description) **while typing**.
- The parent template (you are not “in a package form”; you are still on `go`
  / `python`).

**Together when save is offered:**

- The package summary.
- Preview of generated Boothfile + config.toml + shareable DSL.
- Hand-written choice if relevant (keep-mine vs replace).
- That a running booth is **not** live-updated.

**May be disclosed on demand (must not dominate):**

- The other forty config.toml settings.
- Long `display-detail` text.
- Template file/segment guts (`booth template show --detail` / `cat`).
- Debug JSON of the resolved selection.

**Must not be co-mingled:**

- User-owned extras vs template-owned run-args.
- Catalog items vs booth settings (related, but different jobs — don’t hide one
  behind the other; don’t pretend they are the same list).
- Start-time exposure (`public` / TLS / password) vs saved configuration.

---

## 10. User journeys (success criteria)

Still capabilities, not surfaces.

### A. First booth, known stack

Someone wants “Go + Python, VS Code in the browser, app port 3000.”

1. See that Languages / IDEs / tools exist without committing.
2. Find `go` and `python` by search or by group; choose both.
3. See auto-select `vscode-ext` (and similar) join, and that they can drop them.
4. See `linter` / `uv` as optional children of those parents — not as a global
   tool bag.
5. Pin Python’s version from suggestions or a custom value.
6. Set variant to codeserver and booth port (or leave port unset for the
   default).
7. Add a **user-owned** publish `3000` and understand it is extra, not a
   language’s `+expose`.
8. Preview Boothfile/config/DSL; accept; `.booth/` exists; next `booth` run
   uses it.

### B. “I don’t know the names”

Someone wants a Postgres they can reach from the host, plus a GUI.

1. Search “postgres” / “database” and land on the middleware, not on a random
   `*-pkg`.
2. Inspect enough to see `start` and `expose` are **children**, off by default
   (server convention).
3. Choose the parent, then those children; see the host port follow the service
   until they pin it.
4. Search “dbeaver” or “database gui”; see that DBeaver wants a **desktop**
   variant (warning if still on base/codeserver).
5. Contrast DBeaver vs CloudBeaver (web) without starting over.
6. Review publishes: template-owned mapping from `+expose` vs anything they
   added themselves.

### C. Reopen and add one thing

A project already has `go:1.25` + codeserver. They want Playwright.

1. Open config on that directory; baseline is the existing selection and pins.
2. Current picks remain visible even if Playwright-level browsing is “popular
   only.”
3. Add `playwright` (and its params); **Go’s 1.25 pin stays**.
4. Preview the delta (what files change); save over generated files (not
   hand-written).
5. Unrelated `arg` lines and unrecognized config.toml keys survive.

### D. Hand-written Boothfile

Someone edited `.booth/Boothfile` by hand.

1. On open, they learn the files are protected **before** they change anything.
   Looking around does not write.
2. They still compose a selection.
3. On accept they get two outcomes: keep theirs and take generated `.new` to
   merge, or replace and keep `.bak`.
4. Replace is deliberate; keep-mine is the easy path. Pointer-reflex must not
   replace.

### E. Architecture skip

Someone on Apple Silicon wants Chrome.

1. `google-chrome` is findable and choosable.
2. At choose-time they see: no arm64 build, it will **not** install, use
   Chromium/Firefox/Playwright instead.
3. The rest of the booth still builds. Save is allowed.

### F. Empty / settings-only

Someone wants a codeserver booth with no extra templates.

1. Selection of zero templates is valid.
2. They set variant (and maybe port) only.
3. Preview shows a minimal Boothfile + config.toml; save works.

### G. Agent or teammate reuse

Someone wants to give another person or agent the same stack.

1. From a finished (or draft) selection, copy the shareable DSL + settings.
2. That string is what `--no-tui --select …` and the file headers already
   speak.
3. Optional: write it as a recipe file in the project.

### H. Quit without wrecking

1. Open, browse, close → no prompt, no writes.
2. Select go, deselect go, close → no prompt.
3. Select go, close → confirm discard.
4. Mid-edit of a version pin, close → confirm discard (in-progress typing
   counts).

---

## 11. Non-goals (v1)

- Recreating the TUI’s chrome in a browser (the failed attempt).
- In-container `/config` or `--writable-booth` as the way to configure. Config
  is host-side on purpose (no chicken-egg with Docker; `.booth/` is read-only
  in the container by default).
- Live reconfigure of a running container. Save writes files; the next
  run/rebuild picks them up.
- The **booth overlay** (messages, idle chip, restart/shutdown, proxy pane).
  Different product, different process.
- Authoring templates (`template.toml`) or Boothfile-by-hand. This UI
  *selects* the catalog; it does not replace `docs/AGENT_TEMPLATE.md`.
- Persisting `--public` / TLS / password.
- Multi-user / accounts / cloud drafts.
- A marketplace that installs templates from arbitrary URLs at browse-time
  (recipes-from-URL as `--select @@url` already exists as a **launch** input,
  not an in-session store).
- Explaining Docker, or teaching the Boothfile language, beyond what preview
  already shows.
- Starting, stopping, or listing booths (except: don’t steal a running booth’s
  port; don’t imply save restarted it).
- A recipe manager (list/edit/delete many recipes).

**Deployment frame (v1):** host-side local editor, same job as the TUI. The CLI
serves it on loopback with a one-shot token, writes this project’s `.booth/`,
and does not need Docker. A hosted catalog on codingbooth.io that only emits a
DSL is a later, separate product.

---

## 12. What to salvage from `config-web-ui` — and what to throw away

The branch `config-web-ui` (`worktree/config-web-ui`) is one commit: *Give booth
config a Web UI on the booth port*. It is useful as a **host and pipeline**
sketch, not as a UI.

**Keep the idea (re-implement against this spec, don’t ship the HTML):**

- Host-side `booth config --web` (or auto-open when there is a display but no
  TTY).
- Loopback bind, one-shot token, browser open, process waits until Save or
  Quit.
- Refuse to listen if the booth port is already taken.
- One session object that mutates selection/params/settings and returns the
  same `tui.ConfigResult` the TUI returns, so write/hand-written/keep-mine stay
  one path.
- Catalog JSON derived from `TemplateRegistry` (not a hard-coded list).
- Field table from the same schema the TUI uses (`ConfigKeys` + display
  metadata).
- Token on every mutating request.

**Throw away:**

- `static/index.html` as a product. It is the TUI: header count, search +
  chips, category partitions, list | detail, config as sibling of Languages,
  footer Save/Quit, dialogs for warning/overwrite. That is the recreation this
  spec exists to stop.
- Any requirement that the web client mirror `activeTab`, `listFilter` digits,
  or “highlight row → right pane.”
- Treating the web client as a renderer of TUI state blobs (`selected` maps,
  `stringFields`, …) without a **package** model. The server can keep that
  state; the experience should not be “draw the maps.”

**Rebuild, don’t copy:**

- Preview of generated files (the attempt had no live Boothfile preview).
- Catalog-wide search results.
- Co-visible package vs contextual children.
- Undo of last change.
- Shareable DSL as a first-class output, not only as what save writes into a
  header.

---

## 13. Traceability (TUI/CLI capability → web job)

| Current product | Web must still accomplish | Do not copy |
|---|---|---|
| Category partitions | Group and scan the catalog | Exclusive full-view per category |
| Popular / All / Selected / Local | Those *meanings* (especially “don’t hide current picks”; Local only when present) | The chip row as the main IA |
| Search filters current group; stars other groups | Find across the whole catalog; parent shown if a child matches | Per-group type-ahead as the only search |
| Toggle with auto-select + requires | Same rules, visible implications | Footer flash as the only explanation |
| Edit params in the detail pane | Params while the owner is selected; suggests + custom; variadic lists; paste many | “Focus the other pane to edit” |
| Config field table (schema-joined) | Every persistable setting reachable; unset vs on vs off; extras vs template run-args | One undifferentiated scroll of ~40 keys |
| Dry-run flag | Preview without write | Preview only after confirm |
| Hand-written heads-up + keep/overwrite | Same two outcomes, same deliberateness | The exact dialog choreography |
| Dirty = snapshot vs baseline | Same definition of “changed” | A sticky dirty bit that forgets handlers |
| `--select` DSL, recipes, flags as pre-fill | Launch can pre-fill; export DSL | Requiring the user to type DSL to use the UI |
| `--start` after save | Optional start after successful write | Start implied by save |
| Arch skip + note | Choose-time skip + substitute | Glyph-only warning |
| `booth template list/search/show` | Inspection is in-session; no need to leave for the CLI to learn what a template is | A separate “docs mode” |

---

## 14. Designer brief

Invent a native web experience that:

1. Puts the **package** (set of templates + children + pins + variant/port) in
   the user’s peripheral vision the whole time.
2. Makes the catalog **scannable and searchable** as a landscape, with groups
   as an optional lens.
3. Reveals **extensions only in parent context**, with auto-select and requires
   as visible consequences.
4. Treats settings as **runtime shape**, progressively, with template
   contributions as effects.
5. Lets the user **preview, then persist**, with hand-written files protected.
6. Speaks the same language the CLI already speaks (DSL, recipes, `.booth/`
   files) so agents and humans can round-trip.

Do not start from `config-web-ui/static/index.html`. Start from journeys A–H
and the co-visibility rules.

Responsive: a phone must still **search, inspect, toggle a small set, and
save**; it does not need to make the full catalog landscape pleasant. Pointer
and keyboard are both first-class on desktop.

The following are product rules the engine already implements. The web UI must
**expose** them, not re-specify their algorithms:

- DSL parse, resolve (auto-select, requires, param mapping, overrides from
  existing `arg` lines), compile (segment order, match-or-error scalars,
  combine-and-dedup arrays), write, fingerprint/drift, keep-mine vs overwrite.
- Host-port collision check and `+OFFSET` / `${ENV}` expansion (the latter at
  **start**, not at config time — preview should show the literal form that will
  be stored).
- Package-list canonicalization (dedupe + sort) on save.
- Local template merge (name override + warning).

If the UI and the engine disagree, the engine wins — then fix the UI. Same
compile/write pipeline as `--no-tui` / TUI. The web UI is another way to
produce a `ConfigResult` (DSL + settings + keep-mine vs overwrite). It must not
grow a second generator.

---

## 15. Assumptions

Not in the TUI source; stated so they can be rejected:

- Host-side local editor as the v1 deployment frame (loopback + token).
- Undo of last change.
- Catalog-wide search results.
- Live preview of generated files.
- Deep-linkable / copyable draft as DSL + settings.
- Recipe export from the session (not a recipe manager).
- Progressive disclosure of settings.
- Showing template-owned run-args as effects rather than hiding them.
- Variant mismatch as a warning, not a hard error.
- Keep a `requires` dependency until every depender is gone.
- One category membership each + tags (no overlapping groups).
- If a booth is already running on this project, say so; don’t steal its port.
- In-progress draft need not survive killing the CLI process (TUI parity);
  refresh during the session may restore.

---

## 16. Open questions (only what is still actually open)

The original six questions are decided for v1 in this spec (deployment frame,
recipe authoring, draft identity, variant mismatch, deselecting dependencies,
grouping). Remaining:

1. **When to start building.** This file is the spec. Implementation is a
   separate session (linked worktree, not the discarded TUI-clone HTML).
2. **Smallest honest slice.** Journey A (known stack → preview → save) is the
   smallest slice that is still the product; browsing-only without persist is
   not.
