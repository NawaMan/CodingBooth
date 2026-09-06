# Handoff: `booth config` Web UI

## Overview

A native-web replacement for the `booth config` TUI: assemble a coherent CodingBooth
environment for one project directory — pick any number of catalog templates, attach only the
extensions that belong to them, set the booth's runtime shape, preview the generated files, and
save. It is **not** a running-booth control panel, not an in-container editor, and not a
Dockerfile authoring tool.

This design answers the spec `docs/CONFIG_WEB_UI.md` (product job, co-visibility rules,
journeys A–H). It deliberately does **not** recreate the TUI or the discarded
`config-web-ui/static/index.html`.

## About the design files

The files in this bundle are **design references created in HTML** — a working prototype of the
intended look and behaviour, not production code to copy. The task is to **recreate this design
in the target codebase's own environment** (the Go binary serving a loopback UI, with whatever
front-end stack that service adopts), using its established patterns. The prototype's client-side
resolver is a *stand-in for the engine* — see "What the prototype fakes" below. Do not port it.

## Fidelity

**High fidelity.** Final colours, typography, spacing, density and interaction states, all taken
from a bound design system (see Design tokens). Layout is authored at 1440×900 and is the desktop
target. Copy in the prototype is final-quality and can be shipped as written.

Content fidelity is also high: the catalog in `catalog.js` was generated from the real
`NawaMan/CodingBooth@main` `templates/` tree — 153 templates in the repo's eight group ids, the
real extension lists from all 207 `*--extension.toml` files, real param names, defaults and
`suggests`, real `requires` edges, and `google-chrome`'s real `unsupported-arch` note. In the
implementation this data must come from `TemplateRegistry` as JSON, not from a hand-written list.

---

## Screens / views

There is **one screen** with three always-visible regions plus two overlays. That is the central
design decision: the spec's co-visibility constraint ("the package in peripheral vision the whole
time") is satisfied structurally, not by navigation.

### 1. Header (full width, 46px tall)

- **Purpose:** identify the session and carry the five always-in-view facts.
- **Layout:** flex row, `padding: 8.4px 16.8px`, `box-shadow: inset 0 -1px 0 var(--color-divider)`
  as the bottom rule, `gap: 11.2px`.
- **Contents, left to right:**
  - `booth config` — 16px, `--font-heading`, weight 500, `letter-spacing: -0.01em`.
  - Project directory chip — monospace 12.5px, `--color-neutral-400`, on `--color-surface`,
    `border-radius: 4px`, `padding: 3px 9px`, with a `ph-folder-open` icon in
    `--color-accent-400`. **This is the "you are configuring this directory" fact.**
  - Spacer (`margin-left: auto`).
  - Dirty chip — monospace 11.5px. `same as opened` in `--color-neutral-500` with a hollow
    `ph-circle`; `changed since open` in `--color-accent-300` with `ph-fill ph-circle`.
  - Compile chip — `compiles` + `ph-check-circle`, or `N blocking` + `ph-x-circle` in
    `--color-neutral-200`.
  - Hand-written warning — `.tag.tag-outline`, clickable, `ph-shield-warning`, text
    "Boothfile is hand-written". Only rendered when the project has drifted files.
  - `Undo last change` — `.btn.btn-secondary`, disabled (label becomes `Nothing to undo`) when
    the history stack is empty.
  - `Preview & save` — `.btn.btn-primary`, `ph-eye`.

### 2. Lens rail (196px, left, scrolls independently)

- **Purpose:** the axes that keep a 153-item catalog tractable, without being the IA.
- **Layout:** `padding: 16.8px 11.2px`, `box-shadow: inset -1px 0 0 var(--color-divider)`,
  three stacked groups with `gap: 16.8px`.
- **Group headings** use the `.lbl` style: 10px, `letter-spacing: 0.1em`, uppercase,
  `--color-neutral-500`.
- **Lens** — `Popular`, `All`, `Selected`, `Local to project`, each a full-width button
  (13px, `padding: 5px 8px`, `radius 4px`) with a leading Phosphor icon and a trailing count in
  monospace 11px at 60% opacity. Active: background `--color-accent-900`, text
  `--color-accent-200`. Hover: `color-mix(in srgb, var(--color-text) 7%, transparent)`.
  - **`Local to project` must only appear when the project actually has `.booth/templates/`.**
  - **Default is `All`,** not `Popular`: only 6 of 153 templates carry `primary = true`, so a
    prominence-first default shows an almost empty catalog. Popular remains a lens, and its
    meaning is *primaries **plus** everything already selected* — a reopened booth must never
    hide a current pick.
- **Groups** — `Every group` plus the repo's eight (`Languages`, `Databases`, `Tools`,
  `AI Tools`, `IDEs`, `Desktops`, `Browsers`, `Education`), same button treatment, counts
  recomputed against the active search.
- **Tags** — the union of all template tags, as `.tag` chips (11px, `padding: 3px 10px`),
  outline when inactive (`--color-neutral-800` border) and accent-filled when active. Multi-select
  is single-tag toggle in the prototype; N-tag AND is a reasonable extension.

### 3. Catalog (fluid centre column, scrolls independently)

- **Purpose:** the landscape. Scan by group, find by intent.
- **Layout:** `padding: 0 22.4px 22.4px`. A sticky search bar (`position: sticky; top: 0`,
  background `--color-bg`, `z-index: 3`), then one `<section>` per group.
- **Search bar:** `.input` at `min-height: 40px` with a `ph-magnifying-glass` at
  `left: 11px`, placeholder "Search every template, description and extension". Beside it a
  `.seg` toggle for card / row density (`ph-squares-four` / `ph-rows`).
- **Result line** under it, 12px `--color-neutral-500`: either
  `Showing N of 153 templates · <lens> · <group> · tag <tag>` or, while searching,
  `N templates match across all eight groups, hidden names included`. A `clear lens` ghost button
  appears whenever a lens/group/tag is narrowing the view.
  - **Search must bypass the prominence filter** and match name, `display-disc`, tags **and
    extension names** across the whole catalog. A hidden name stays findable.
- **Group header:** `<h5>` 15px + monospace 11px meta (`N shown of M`) + a rule that fades to
  transparent (`linear-gradient(to right, var(--color-divider), transparent 60%)`).
- **Pinned first group — `In your package`,** meta "never hidden by a lens". Selected templates
  are lifted out of their categories and shown first (suppressed while searching, where the
  result set is the point).
- **Card grid:** `repeat(auto-fill, minmax(320px, 1fr))`, `gap: 11.2px`.

#### Template card (collapsed)

- Container: `border-radius: 8px`, `padding: 11.2px`, `gap: 5.6px`.
  - Unselected: background `color-mix(in srgb, var(--color-surface) 55%, var(--color-bg))`,
    edge `box-shadow: 0 0 0 1px var(--color-neutral-900)`.
  - Selected: background `--color-surface`, edge `0 0 0 1px var(--color-accent-700)`.
- Title row: monospace 14.5px name (`--color-accent-200` when selected, else `--color-text`),
  then the display name at 12px `--color-neutral-500`, then `ph-fill ph-star` 10.5px
  `--color-accent-500` for `primary`, a `local` tag, and any non-default param pin in
  monospace 11px `--color-accent-300` (e.g. `GO_VERSION 1.24.13`).
- `display-disc` at 12.5px `--color-neutral-400`, `text-wrap: pretty`.
- Actions, right-aligned, `gap: 5px`:
  - Unselected: one `add` button (`ph-plus`), `.btn` with `--color-divider` border.
  - Selected: a caret button (`.btn.btn-secondary`, `ph-caret-down` / `-up`) that expands the
    card, **and** a `remove` button (`ph-x`) in accent (`--color-accent-300` on
    `--color-accent-900`). Both affordances are required — an expand-only control reads as a
    dead toggle.
- Consequence lines, each 11.5px with a leading icon:
  - **Why it is here** (`ph-git-fork`, `--color-accent-300`): `Pulled in by kotlin — kept until
    they go.` / `Auto-select children joined: vscode-ext. Untick to opt out; the exclusion is
    saved.` / before selection, `Requires java — it will join.` or, on a search hit against a
    child, `Matched on extension linter — choosing it brings go along.`
  - **Architecture skip** (`ph-warning` on a `--color-neutral-900` plate): `No arm64 build — on
    this host it will be skipped at build time, not fail. Use chromium … .` **This must be
    readable at choose-time, not a glyph and not a footer flash.**
  - **Variant assumption** (`ph-monitor`): `Assumes a desktop variant. You are on codeserver.`
    A warning, never a block.
- Collapsed footer: monospace 11px `3 extensions — visible once it is in the package` (or
  `— open to choose` when selected), then the tag chips.

#### Template card (expanded — only possible while selected)

Separated by `box-shadow: inset 0 1px 0 var(--color-divider)`, three labelled blocks:

1. **`Extensions of <name>`** — one full-width button per extension:
   `ph-fill ph-check-square` / `ph-square` at 15px (`--color-accent-400` when on), monospace
   12.5px name, 11.5px note, and a right-hand tag: `default on` (`--color-accent-800` /
   `--color-accent-100`) or, once opted out, `opted out — saved as ~<name>`
   (`--color-neutral-800`). Selected rows get a `--color-accent-800` border on
   `--color-accent-900`.
2. **`Parameters`** — only for items in the selection. Per row: monospace 12px key, an `on <ext>`
   qualifier when the param belongs to a child, and a note in `--color-accent-300`:
   `following CLOUDBEAVER_PORT (8978) — type to pin` / `pinned — no longer follows` /
   `host port — container side is the literal 5432`.
   - Scalar: a 132px `.input` plus suggestion chips from the template's `suggests` (active chip =
     accent border + `--color-accent-900`). `+OFFSET` is offered as a suggestion on host ports.
   - Variadic: existing entries as removable monospace chips (`ph-x` at 10px), an `.input` that
     commits on Enter (splitting on whitespace or commas, so a paste of several works), and
     **the manager's own pin syntax shown while typing** — e.g. `pip syntax — ruff==0.6.9`,
     `apt pin syntax — htop=3.0.5-7`, `Open VSX id, @version pins one`.
3. **`Contributes to the booth`** — the template's effects as monospace 11.5px lines with a
   `ph-arrow-elbow-down-right` marker: `-p 8978:8978  (from expose)`, `sets variant = notebook`,
   `startup segment: … starts with the booth`, credential mounts. **Effects, never a second
   editable copy of the user's own lists.**

### 4. Package rail (392px, right, scrolls; sticky footer)

- Background `color-mix(in srgb, var(--color-surface) 45%, var(--color-bg))`,
  `box-shadow: inset 1px 0 0 var(--color-divider)`, `padding: 16.8px`, `gap: 16.8px`.
- **Header:** `The package` (`<h5>` 15px) + monospace meta
  `N templates · N children · <variant>`, and under it the baseline line — `Differs from how this
  session opened. Closing now asks first.` / `Matches the configuration on disk. Closing writes
  nothing.`
- **Issue list:** one plate per problem, 12px, `text-wrap: pretty`.
  Errors: `ph-x-circle`, background `--color-accent-900`, edge `--color-accent-700`.
  Warnings: `ph-warning`, background `--color-neutral-900`, edge `--color-neutral-800`.
- **`Runtime shape`:** the eight variants as monospace chips; the selected one's meaning in
  11.5px underneath (`code-server is the primary service on the booth port. Editor extension ids
  have a home; desktop apps do not.`). Then `booth port` and `offset base` as a two-column
  `.field` pair — **both must accept empty as "unset = booth default"**, with the offset base
  placeholder reading `follows booth port (8722)`. Below, the three-knob explanation:
  `Three knobs: booth port 8722, offset base following it, and 2 per-service publishes below.
  Moving the booth port moves any +OFFSET publish unless you pin the base.`
- **`Selected — parents and children`:** one plate per template (`--color-surface`, edge
  `--color-neutral-800`, `padding: 8px 9px`). Monospace label with its pins (`go:1.24.13`), a
  `kept by kotlin` note when it is someone's dependency, an `ph-x` remove, and the chosen children
  as small monospace chips — accent for included, `--color-neutral-900` / `--color-neutral-500`
  and `~`-prefixed for exclusions. Clicking the label reveals that template in the catalog
  (clears the search, switches to the All lens, expands the card).
  Empty state: `No templates. A settings-only booth is valid — pick a variant and save.`
- **`From your templates — effects, not yours to edit`:** monospace `-p host:container` +
  provenance (`from postgresql/expose (host port; container side is the literal 5432)` /
  `(follows service port)` / `(pinned)`) + a `move host port` ghost button that jumps to the
  owning extension's param. **This is how the user learns that their own `--publish` would add a
  second mapping rather than move this one.**
- **`Yours — long-form run-args, distinct from template contributions`:** three sections —
  `Extra publishes` / `Environment variables` / `Mounts` — each with its `--publish` / `--env` /
  `--volume` flag in monospace 10.5px, a count, its own entry list, its own empty note, and its
  own Enter-to-commit input with a format-specific placeholder (`3000:3000, or +10:3000 relative
  to the offset base`; `KEY=value`; `/host/path:/in/booth[:ro]`).
- **`The long tail — 41 more settings`:** collapsed disclosure rows (`Egress`, `Container`,
  `Build`, `Cache & shared`, `Session & idle`) with a caret, a label, and a monospace summary
  (`all unset` / `2 set`). Expanded, each key gets a three-state `.seg`: `unset (on)` / `on` /
  `off` — **tri-state is required**, because a plain toggle cannot persist "off" for a setting
  whose product default is on (`sudo`, `open-browser`).
- **Sticky footer:** the compile line (first blocking reason, or `Compile is clean. Save writes
  .booth/ — a running booth is not live-updated.`), then `Preview & save` (primary, flex 1) and
  `Copy DSL` (secondary, `ph-link`, becomes `Copied` + `ph-check` for 2.6s).

### Overlay A — Preview & save (right sheet, `min(760px, 88vw)`)

- Backdrop `color-mix(in srgb, var(--color-neutral-900) 62%, transparent)`; clicking it closes.
- Header: `Preview — nothing is written yet` plus a target line that tracks the write mode
  (`Would write .booth/Boothfile.new and .booth/config.toml.new beside your originals` /
  `Would replace … keeping .bak copies`), a `.seg` of three monospace tabs
  (`.booth/Boothfile`, `config.toml`, `shareable`), and a ghost close button.
- Body: a `<pre>` on `--color-surface`, edge `--color-neutral-800`, monospace 12px,
  `line-height: 1.65`, `white-space: pre-wrap`.
- Hand-written block (only when files have drifted): a `--color-accent-900` plate with a
  `ph-shield-warning`, the sentence "config did not write this project's `.booth/Boothfile` — a
  human did. Choose what save does with it.", then two radio-style option buttons:
  - **`Keep mine — write generated files as .new`** — "Your Boothfile and config.toml are
    untouched; .new is merge scratch and gitignored. The safe path." **This is the default.**
  - **`Replace mine — originals kept as .bak`** — arms a confirmation input; save stays disabled
    until the word `replace` is typed. **A stray pointer action must never be enough.**
- Footer: a note (`User startups, setups, home files and unrecognised config.toml keys survive.
  Saving does not restart a running booth.`), `Back to composing`, and the save button —
  `Save as .new` / `Replace and save` / `Blocked — N conflicts` when disabled.

### Overlay B — Drop confirmation (centred `.dialog`, 440px)

Two cases, both offering exactly two outcomes:

- **Dependency:** title `java is required by kotlin`; body "Keeping it is the default: resolve
  would pull java back on save anyway. Drop kotlin too and it can go."; actions `Keep it` /
  `Drop kotlin, java`.
- **Cost:** title `Dropping python drops its children`; body "4 chosen extensions and their
  pinned parameters go with it. Undo restores them."; actions `Keep it` / `Drop it and its
  children`.

### Toast

Centred, `bottom: 26px`, `--color-surface` on `--shadow-md`, 12.5px with `ph-check-circle` in
`--color-accent-400`. Used for `Copied`, `Wrote .booth/Boothfile.new and config.toml.new.`,
`Wrote .booth/ — originals kept as .bak.`

---

## Interactions & behaviour

- **Add a template:** selects it, then recursively its `requires`, then each newly-selected
  item's `auto-select = true` extensions (unless a stored exclusion says otherwise), and expands
  the card. Every implication is stated on the card — nothing silent.
- **Remove a template:** if any selected template requires it, the drop dialog offers to drop the
  dependers too; keeping it is the default, because resolve would pull it back on save anyway
  (this closes a real TUI gap). If it has more than one chosen child, the cost is named before it
  sticks. Otherwise it drops immediately, taking its extensions and their params.
- **Toggle an extension:** turning off an `auto-select` child **writes an exclusion** (`~name`),
  which must survive save/reload; turning it back on clears the exclusion.
- **Params:** exist only while their owner is selected. A default that references another param
  (`${CLOUDBEAVER_PORT}`) displays as a live derived value and keeps following until the user
  types, which pins it.
- **Validation as you compose, not at save:** duplicate host ports (including an offset landing
  on the booth port), two selected templates setting the same scalar differently
  (`variant` — match-or-error), a user `--publish` aimed at a container port a selected `+expose`
  already publishes, variant mismatches, architecture skips. Errors block save and name the first
  blocking reason in the footer; warnings never block.
- **Undo:** a snapshot stack (last 20) covering selection, extensions, exclusions, params and
  settings. Every mutation pushes; the header button pops.
- **Dirty:** a JSON snapshot compared against the baseline captured at open. Select-then-deselect
  is *not* a change. Only a real difference should prompt on close.
- **Save:** writes `.booth/` (or `.new` beside it), then resets the baseline so the session reads
  clean. It is **not** a live reload of a running container — the copy says so.
- **Responsive:** authored for 1440. Under ~1100 the three columns need to collapse — the rail
  becomes a bottom sheet or drawer, and the phone target is only "search, inspect, toggle a small
  set, save", not a pleasant full-catalog landscape.
- **Keyboard:** pointer and keyboard are both first-class. Focus is the design system's
  `:focus-visible` 2px accent ring at 2px offset — never the browser default. `/` to focus search
  and Enter-to-commit on every list input are the prototype's conventions.

## State management

Session state, all client-side in the prototype:

| Key | Shape | Notes |
| --- | --- | --- |
| `sel` | `string[]` | template names, insertion-ordered; 0..N, unique |
| `exts` | `{ [template]: { [ext]: 1 } }` | chosen children |
| `excl` | `{ "<template>/<ext>": 1 }` | opt-outs of `auto-select` children — **must persist** |
| `params` | `{ "<t>.<PARAM>" \| "<t>/<ext>.<PARAM>": string }` | absent = default; a variadic list is space-joined |
| `variant`, `port`, `offset` | `string \| null` | empty = unset = booth default |
| `extras` | `{ kind: 'publish'\|'env'\|'volume', v: string }[]` | user-owned long-form run-args |
| `tri` | `{ [key]: 'unset'\|'on'\|'off' }` | long-tail settings |
| `history` | `string[]` | JSON snapshots for undo |
| UI-only | `q`, `lens`, `cat`, `tag`, `view`, `open{}`, `tail{}`, `preview`, `tab`, `writeMode`, `confirm`, `dropAsk`, `toast` | not persisted, not shared |

Baseline is the same snapshot shape, captured when the session opens from
`.booth/Boothfile` + `config.toml`.

### What the prototype fakes — and must not be ported

The prototype resolves, compiles and generates in the browser so the design could be judged. In
the real product these all belong to the existing engine, and **the UI must not grow a second
generator**:

- DSL parse and resolve (auto-select, `requires`, positional param mapping, overrides from
  existing `arg` lines).
- Compile: segment order bands, match-or-error scalars, combine-and-dedupe arrays.
- Write, fingerprint/drift detection, keep-mine vs overwrite.
- Host-port collision checks; `+OFFSET` and `${ENV:-default}` expansion (the latter at **start**,
  not config time — preview shows the literal that will be stored).
- Package-list canonicalisation (dedupe + sort) on save.
- Local template merge (name override + warning).

The web client should be another way to produce a `ConfigResult` (DSL + settings + keep-mine vs
overwrite) against the same session object the TUI drives. Deployment frame: host-side, loopback
bind, one-shot token on every mutating request, browser opened by the CLI, process waits until
Save or Quit, refuses to listen if the booth port is taken. **Never persist `--public`, TLS paths
or passwords.**

### Generated output the design commits to

The shareable tab is a first-class output, in the grammar `docs/AGENT_RECIPE.md` documents —
templates joined by `/`, params comma-separated positionally after one `:`, extensions with `+`,
opt-outs with `~`, an extension's pinned param as `+expose:19000`:

```
booth config --no-tui ~/src/atlas-api \
  --select "go:1.24.13+vscode-ext/python:3.13+uv/postgresql+expose:15432" \
  --variant codeserver \
  --port 8722 \
  --publish 3000:3000
```

…plus the same selection as a one-per-line `.booth/recipes/<name>.recipe` body. Variadic package
lists are **not** in the select string — they travel as `arg` lines. Generated files carry the
repo's own two-line header (`# Generated by:` / `# Adjust with :`).

## Design tokens

From the bound **Nocturne** system (`_ds/nocturne-…/styles.css`). Take every value from the
variables; do not hard-code.

- **Colours:** ground `--color-bg` `#161826`; surface `--color-surface` `#232532`; text
  `--color-text` `#e9e9ed`; accent `--color-accent` `#9184d9`; divider
  `color-mix(in srgb, #e9e9ed 16%, transparent)`. Two 100–900 OKLCH ramps are in use —
  neutral (`#f3f5fe` … `#292b31`) and accent (`#f5f4ff`, `#e7e5fe`, `#d2cefd`, `#b5abfc`,
  `#968ae0`, `#796cbf`, `#5d5294`, `#423a6a`, `#2b2741`). On this dark ground: 700–900 for tinted
  fills and borders, 500 as base, 100–300 for text on those tints.
- **Type:** Inter (`--font-heading` / `--font-body`), headings at weight 500 and never bolder.
  Body 15px/1.55. In-app sizes used: 15px h5, 14px controls, 12.5px card copy, 11.5px notes,
  11px meta, 10px `.lbl` uppercase with `letter-spacing: 0.1em`. Every identifier — template
  names, params, flags, ports, file paths, generated output — is monospace.
- **Spacing** (density 0.70×): 2.8 / 5.6 / 8.4 / 11.2 / 16.8 / 22.4px.
- **Radius:** 4 / 8 / 14px. **Shadows:** `--shadow-sm/md/lg` only.
- **Rules** fade to transparent at their ends rather than stopping cleanly; the accent is a line
  and a glow, never a flood.

## Assets

- Icons: **Phosphor** (`@phosphor-icons/web` 2.1.1, regular + fill), CDN-linked in the prototype;
  vendor it in the real build.
- Fonts: Inter via the design system's stylesheet.
- No images. Nothing to export.

## Files

| File | What it is |
| --- | --- |
| `Config Web UI.dc.html` | The prototype — one component, streaming HTML. Markup at the top; the session model, resolver, validators and file generators in the class below it. |
| `catalog.js` | Catalog data generated from the repo (`window.BOOTH_CATALOG`: `templates`, `cats`, `variants`). Replace with `TemplateRegistry` JSON. |
| `github.md` | The source-repo association and what was read from it. |

The prototype needs the Nocturne stylesheet at
`_ds/nocturne-dfcc87c9-0034-40af-ad1c-43521ad29c14/styles.css` to render; open it from the project
root rather than from this folder.
