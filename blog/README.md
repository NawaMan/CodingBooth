<div align="center">

# 📽️ GeekPresent

**Slides for people who'd rather write HTML than wrestle a slide editor.**

Build presentations with HTML, CSS, and Svelte components — each slide is a route,<br/>
the whole presentation is a static site, and it deploys to GitHub Pages.

`SvelteKit` · `Static site` · `1920×1080 canvas, auto-scaled` · `Deploys to GitHub Pages`

</div>

---

## Why this project exists

If you do any front-end work you already know HTML + CSS + JS, and you've probably wished you could just *use* that to make slides instead of fighting a WYSIWYG tool. GeekPresent lets you do exactly that — and takes care of the tedious parts:

- **No manual paging or navigation.** List your slides once in `pages.ts`; arrow keys, the on-screen nav bar, and the Table of Contents are wired up for you.
- **Fixed canvas, automatic scaling.** You design on a fixed **1920×1080** canvas and position things with normal CSS — including absolute positioning at exact pixels — and the framework scales the whole slide to fit any screen. You think in one size; it handles the rest.
- **Colocation, your choice.** Global CSS/JS/assets work, but each page can also keep its *own* assets (images, etc.) right next to it. Pick whatever keeps cognitive load low.
- **Real componentization.** Svelte is excellent at components, so reusable slide pieces (boxes, code viewers, notes…) are just imports.
- **Navigation built in.** Arrow keys, on-screen buttons, a Table of Contents, and an **Overview Page** grid (press <kbd>O</kbd> to see every slide at once) — no wiring required.
- **FITTED / SCALED modes.** Present fit-to-window, or switch to an exact zoom (1:1 and beyond) you can pan, with a minimap; speaker notes show below when zoomed out.
- **It's just text.** Slides are Svelte files, so they diff cleanly, version-control nicely, and hot-reload while you edit.

## What makes it unique

HTML-based slides aren't new — reveal.js, Slidev, Spectacle and Marp all exist. What no mainstream tool focuses on is the particular set of choices GeekPresent combines:

- **One slide = one route = one folder.** Slides aren't sections of a single giant document or fenced blocks in one markdown file — each slide is its own SvelteKit route folder (`src/routes/<name>.html/`). So slides diff cleanly one file at a time, each slide can **colocate its own assets** (images, QR codes) right next to it, and every slide is independently URL-addressable and prerendered to its own HTML.
- **A fixed 1920×1080 canvas with pixel-exact positioning *and* auto-scaling.** You design against one fixed size — `left: 960px` means the same thing on every screen — and the framework scales the whole canvas to fit any window (FITTED) or shows it at an exact zoom you can pan (SCALED), with speaker notes below when zoomed out. Most HTML-slide tools push you toward responsive flow; GeekPresent deliberately gives you a fixed pixel coordinate space and does the scaling math for you.
- **Slides that are their own documentation — and editable under `pnpm dev`.** Under **`pnpm dev`**, ☰ → **SOURCE** and **EDIT** work on **every** slide (the shell loads `+page.svelte` via a vite-dev endpoint). Drop `ViewSource` when you also want SOURCE on a *built* site, or the classic Text-mode corner control: it registers `?raw` bytes for the in-slide Monaco `CodeBox`. **EDIT** opens an *unscaled* popup at `/_source-edit` (Monaco's caret is not under the slide's CSS scale). In that window: **Ctrl/Cmd+S** SAVE, **Ctrl/Cmd+Shift+R** REFRESH, **Esc** CLOSE (confirms if dirty); **Alt+.** then **r**/**s**/**c** is the mnemonic path (one letter ends arm mode). SAVE answers **NOT ALLOWED** on a static host. (`SourceView` is the same idea with Shiki for client-side-navigation decks; its panel also offers **EDIT** into the same popup.)
- **Appendices — a slide you jump *into* and return *from*.** The deep-dive a talk only sometimes needs: a proof, a full API table, a backup demo. `AppendixLink` jumps in and stamps the calling slide into the URL as the return address, so the same appendix returns to whichever slide asked; `AppendixPage` gives it its way back. It behaves like a real book's appendix — several contiguous slides are one chapter you page through, and walking forward off the end *is* the return. Mark it `hidden` and it leaves the deck's forward march entirely (→/Space step over it, the TOC omits it); leave `hidden` off and it is ordinary back matter you can also page into.
- **Two artifact types from one component set.** The same `$lib` components compile into either a click-through **presentation** or a long-form, scrollable **Text** — give the talk, then publish the reader-friendly version with no rewrite. A mode flag (`setMode`) lets shared components adapt (e.g. the nav bar collapses to a single TOP button).
- **Multiple independent presentations in one project.** Navigation and the Table of Contents are scoped *per presentation* via Svelte context (`setPages` / `getPages`), not a single global config. Sibling route folders (`slides/`, `portrait/`, `geeklight/`) each carry their own slide list, theme, fonts, background, and favicon, and coexist without interfering.
- **Genuinely portable, lean static output.** Every route prerenders with **relative** asset paths, so the build runs from GitHub Pages, any sub-path, S3, or straight off disk. `build-static.sh` can emit the whole site *or a single presentation*, and skips precompressed `.br`/`.gz` files by default (~170 files instead of ~490).
- **Visual placement that stays "just text."** Pixel-exact positioning doesn't mean guessing numbers. Wrap an element in a `Block` (or `ImageBlock`) and flip on **ADJUST mode** — an in-browser authoring aid (on in `pnpm dev`; on a built site via a sticky `?adjust` flag) — to drag and resize it on the canvas, with snapping, aspect-lock, and global undo/redo. Then either **Copy** the tag with its final `x`/`y`/`width`/`height` to paste back into source, or — in `pnpm dev` — hit **SAVE** to write every moved `Block` straight back into the slide's `.svelte` file (matched by `name`, or by its old geometry), and let hot-reload show the result. The write is dev-only — a static site has no server to write files, so there SAVE looks like an ordinary button and *refuses when pressed*, answering **NOT ALLOWED** with a tooltip explaining why; Copy is the way back. Either way the slide stays plain, diffable Svelte and nothing is guessed — a tag it can't confidently place is reported so you paste that one by hand. ADJUST is off in production, but an individual slide can offer it (`adjust: true` in `pages.ts`), so the slides that *teach* authoring can demonstrate the whole loop live in the deployed deck — this project's own deck does exactly that.
- **A pen that draws on the live slide — and remembers.** Flip on **ANNOTATE** and the speaker can mark the slide up mid-talk with a bar of icon tools: a **pen** to circle the term freehand, a **line** and an **arrow** to point dead straight at the line of code, a **rectangle** to ring a whole region, a **highlighter** to swipe over the sentence someone just asked about, a **text** tool to drop a typed label (click to place, then re-edit or drag it), and an **eraser** that lights up the mark under it and lifts it whole. Hold **Shift** and the pen, line, or arrow snaps to a dead-straight horizontal or vertical — the underline or plumb line a wrist can't hold on stage — while the highlighter comes out *level* however wobbly your hand was, because a highlight belongs on the row you swiped rather than sloping across it. The ink is **kept, per slide, across reloads** — so a deck you marked up while rehearsing arrives at the podium marked up — and it mirrors to the audience window automatically. Keeping ink is also what makes it dangerous, so a slide whose marks are more than a day old *says so when you arrive* and offers to clear them; **RESET** / **RESET ALL** sit on the pen's bar and in the presenter console. Crucially the pen eats the *pointer*, never the *keyboard*: arrow keys keep paging, because a speaker who can't advance is worse off than one with a stray scribble.
- **Capture a slide as a PNG at its *true* size.** Press **CAPTURE** and the slide downloads as a full **1920×1080** image — not a screenshot of your window, but the canvas *re-rendered*, so the file is identical whether you were presenting on a projector or squinting at a laptop (`captureScale={2}` gives you 3840×2160, still crisp, because it's re-rendered rather than upscaled). Your **annotations come with it** and the deck's chrome doesn't — capture reuses the same `.no-print` rule that already keeps the nav bar out of a printout. And it's honest about its one real limit: a slide holding a live `<iframe>` (a `WebSite`, `WebPage` or `YouTube` embed) is a separate document whose pixels the page may not read, so rather than hand you a PNG with a hole in it, CAPTURE *refuses when pressed* and names the embed in the way — the same bargain SAVE makes.
- **Kiosk / auto-advance for booths and lobbies.** ☰ → **KIOSK** (or a sticky `?kiosk` link) runs the deck unattended: step pace for builds and note lines, page pace between slides, loop at the end. Optional **speaker notes** step **one `<Note>` child at a time** in a single draggable panel that also holds pause / progress / stop — not a wall of text. Exit is explicit only so a touch on the glass does not kill the loop. The panel needs no mouse either: **Alt+. K** reveals/hides it and **Alt+. U** pauses/resumes, so its idle opacity can go all the way to invisible (`--kiosk-idle: 0`, per slide/deck/site-wide) without becoming unfindable — hovering it also freezes the countdown, without touching the play/pause mode itself.
- **…and every slide to a PNG, offline.** `utils/capture-slides.sh` renders the whole deck to images (thumbnails, a contact sheet) by driving a headless Chrome against a `?shot` URL — a render mode that puts the canvas at exactly 1:1 with no frame, no chrome and no letterbox, so the viewport *is* the slide and the PNG needs no cropping. Because a real browser does the drawing, this path captures what the in-app button can't: iframes, video, Monaco code blocks, all of it.
- **Social cards that are the actual slide.** Share a slide's URL and the preview *is that slide*, not a generic site card. `utils/capture-slides.sh --og` captures every slide into `static/og/` and wires the PNGs into the deck's `pages.ts` `image:` field — and CI does it for you on every deploy (build → capture → build, since `og:image` is baked into each slide's prerendered HTML). The PNGs are gitignored build output, so nothing bloats the repo, and a slide added since the last run gets its card automatically. It never overwrites an `image` you set by hand.
- **Presenting-specific touches.** A helper (`utils/prepare-youtube.sh`) fetches a video's thumbnail and generates a QR code into a slide folder, so the `YouTube` component shows a scannable QR overlay linking to the video.
- **Chrome bars that tuck away — until you pin them (or raise them from the keyboard).** The top tool bar (PRESENT / ANNOTATE / ADJUST / …) and bottom control bar (TOC / pager) auto-hide to a peek strip; hover, focus, or **Alt+.** (**⌥.** on macOS) brings both fully up for a few seconds so letter mnemonics work (**a**/**j**/**z**/**p**/**m**/**t**). When the letter lives in the word it is **underlined** there (`PRESENT`, `ANNOTATE`, `ADJUST`, Table of Contents); when it does not, a trailing chip remains (`FITTED (Z)`, `☰ (M)`). A **pin** on each bar (independent, remembered) locks that bar open. Opt out of a whole bar with `<SlideDeck toolBar={false}>` or `controlBar={false}`.

> **The design note:** slide-to-slide navigation is a full page load, not client-side routing. Animations live *within* a slide — and *cross-slide* transitions work too, via the platform's cross-document **View Transitions API** (`@view-transition { navigation: auto; }`), which is possible precisely *because* each slide is its own document (see the `transition/` deck: slide, flip, zoom, cross-fade, and shared-element morph). The route-per-slide design paying off rather than costing.

## Quick start

```bash
pnpm install
pnpm dev        # http://localhost:5173/slides/title.html
```

```bash
pnpm build      # static site -> docs/
pnpm preview    # preview the build
pnpm deploy     # publish docs/ to GitHub Pages
```

```bash
./build-static.sh ./dist        # build the static site into any folder you choose
./build-static.sh ./dist geeklight   # ...or just one presentation/text
```

---

## Use GeekPresent in another project

GeekPresent is **copy-and-own**, not an npm dependency: you drop it into your repo as a
subfolder and author your docs / slides / promo site there, building to a static site you host
on GitHub Pages. The `adopt-geekpresent.sh` script bootstraps that in one step.

From the **root of the project you want to add it to**:

```bash
# interactive — asks for the subfolder, sample handling, etc. (works through the pipe):
curl -fsSL https://raw.githubusercontent.com/NawaMan/GeekPresent/main/adopt-geekpresent.sh | bash

# non-interactive — pass flags after `bash -s --`:
curl -fsSL https://raw.githubusercontent.com/NawaMan/GeekPresent/main/adopt-geekpresent.sh \
  | bash -s -- --dir docs-site --mode minimal --keep slides --yes

# clean slate — an empty deck instead of sixty demo slides to delete:
curl -fsSL https://raw.githubusercontent.com/NawaMan/GeekPresent/main/adopt-geekpresent.sh \
  | bash -s -- --mode skeleton --kind deck --name slides --yes

# a docs site, not a talk — a long-form Text page instead of a deck:
curl -fsSL https://raw.githubusercontent.com/NawaMan/GeekPresent/main/adopt-geekpresent.sh \
  | bash -s -- --mode skeleton --kind text --name guide.html --yes
```

It clones GeekPresent into a subfolder, removes its `.git` (so it becomes part of *your* repo),
optionally trims the sample decks, and can scaffold a GitHub Actions workflow that builds the
subfolder and deploys it. **Nothing is committed** — review, then `git add` what you want.

Three ways to handle the samples — they differ only in what you start editing:

- **`skeleton`** — the clean slate. Every sample deck moves to `.samples-ref/`, and an **empty
  starting point** is scaffolded in its place. You begin by writing, not by deleting.
- **`minimal`** — keep one sample deck as your starting template, move the rest.
- **`full`** — keep everything; trim it yourself later.

`minimal` and `skeleton` both **move** the samples rather than delete them: `.samples-ref/` is
gitignored but stays on disk, so you (and your coding agent) can still read every component demo.

Skeleton then asks what to start you off with (`--kind`):

- **`deck`** *(default)* — an empty slide deck: one title slide, ready to present.
- **`text`** — a long-form **Text** page instead. GeekPresent builds two kinds of artifact, and a
  deck is dead weight if you adopted it for a docs site rather than a talk.
- **`none`** — nothing at all. The framework, an empty tree, and a landing page that spells out the
  files to write by hand. For people who want to shape it entirely themselves.

Either way the landing page becomes a short getting-started page, matched to what was scaffolded —
which you then delete along with the rest of the scaffolding.

### Where the built site lands

`--dist` (prompted) says where the static build is written, **relative to where you run the
script** — the same frame as `--dir`:

- **`<dir>/dist`** *(default)* — inside the adopted folder, already gitignored. The usual answer.
- **`site`** — a `site/` at your **repo root**, beside `<dir>`. This is the answer when the built
  site is what you publish and commit — say, an existing hand-written `site/` that you're adding a
  deck to.

One answer settles both consumers: the build you run, and what CI uploads. Nothing gets clobbered —
the build refuses to overwrite a non-empty folder it didn't create, so pointing it at a real `site/`
stops and tells you rather than deleting your files. (Worth knowing: the booth mounts only the
subfolder, so it can't write to a `site/` outside it — the script says so, and that build runs on
the host.)

The script **never builds for you.** Adopting is a file operation; the build command is the first
thing it prints when it's done, for you to run when you're ready.

### The docs you end up with

`minimal` and `skeleton` also sort out the documentation, because a clone carries *GeekPresent's*
docs — and in your repo, most of them are about the wrong project:

- **A generated `README.md`** lands in the adopted folder: what this folder is, where your deck
  lives, and the exact build command for the answers you gave.
- **`AGENTS.md` stays.** It's the *authoring* manual — the one thing an AI agent most needs.
- **This README, `AGENT.md` and `TODO.md` move** to `.samples-ref/`. This file remains GeekPresent's
  introduction and full reference, readable at `.samples-ref/GeekPresent-README.md` — it just isn't
  *your* project's README.
- **The `/todo` and `/pick-todo` skills move too.** They read `TODO.md` — *this* project's backlog —
  so left in place they'd offer your agent a menu of GeekPresent features to go implement.

`full` keeps all of it (full means full) and warns you about those two skills instead.

### The build environment: bring the booth, or use your own toolchain

GeekPresent develops itself inside a [CodingBooth](https://codingbooth.io/) — a container that
carries the whole toolchain — and both the `booth` wrapper and `.booth/` are tracked, so the clone
hands you a working one. The script asks whether to keep it:

- **`booth`** *(default)* — keep it. `cd <dir> && ./booth -- ./build-static.sh ./dist` builds your
  deck with **nothing installed on the host but Docker or Podman** — no Node, no pnpm, no version
  drift. `./booth` on its own opens VS Code in the browser with the toolchain already in place.
- **`host`** — remove `booth` and `.booth/`, and build with your own `node` + `pnpm`.

The booth is used as it comes — the script never reconfigures or re-pins it, because being *the same
environment GeekPresent is built in* is the entire point. The wrapper finds its `.booth/` next to
itself, so the copy in your subfolder is self-contained and won't collide with a booth your own repo
may already have at its root.

| Flag | What it does | Default |
| --- | --- | --- |
| `--dir <name>` | subfolder to create | `geekpresent` |
| `--mode <mode>` | `skeleton` \| `minimal` \| `full` — see above | `minimal` |
| `--keep <deck>` | which deck to keep in minimal mode | `slides` |
| `--kind <kind>` | what skeleton scaffolds: `deck` \| `text` \| `none` | `deck` |
| `--name <name>` | what to call the scaffolded deck/page | `slides` / `guide.html` |
| `--booth` / `--no-booth` | keep the CodingBooth, or remove it and build on the host | `--booth` |
| `--dist <path>` | where the built site lands, relative to **here** — e.g. `site` | `<dir>/dist` |
| `--base </path>` | GitHub Pages base path for a project site | none |
| `--ci` / `--no-ci` | scaffold the deploy workflow | prompted |
| `--yes`, `-y` | accept defaults, skip prompts (for CI / `curl … \| bash`) | off |

> **Deploy at a domain root** (user/org Pages or a custom domain). A project sub-path (`--base`)
> currently breaks prerender, because the SEO wiring emits a root-absolute `/sitemap.xml`. See
> [`AGENT.md`](AGENT.md) for the full adoption + authoring guide (and the base-path details).

---

## How to use

### Slides: define the order, then add files

List your slides, in order, in the presentation's `pages.ts` (`src/routes/slides/pages.ts`):

```ts
export const pages = [
    { path: "title.html", title: "Title" },
    { path: "intro.html", title: "Introduction" },
    { path: "demo.html",  title: "Demo" },
];
```

Each entry is a folder under `src/routes/slides/<name>.html/` with two files:

```
src/routes/slides/intro.html/
  +layout.js      # export const prerender = true; export const trailingSlash = "never";
  +page.svelte    # your slide content
```

> **Multiple presentations:** `slides/` is just one presentation — its route folder. To add another, create a
> sibling folder (e.g. `src/routes/talk2/`) with its own `pages.ts`, `+layout.svelte`, and slides.
> Navigation and the Table of Contents are scoped per presentation, and each presentation can have its **own
> theme** (fonts, colours, background image, favicon) in its `+layout.svelte`. See the `geeklight/` presentation
> (`/geeklight/title.html`) for a fully independent, differently-themed example.

### Title and content pages

Two templates cover most slides.

**TitlePage** — for title slides and section dividers; three named slots:

```svelte
<script>
  import TitlePage from '$lib/templates/TitlePage.svelte';
</script>

<TitlePage>
  <span slot="title">GeekPresent</span>
  <span slot="subtitle">How to Build Presentations</span>
  <span slot="subsubtitle">Your Name</span>
</TitlePage>
```

**ContentPage** — for everything else; `title` + `subtitle` props and a default slot:

```svelte
<script>
  import ContentPage from '$lib/templates/ContentPage.svelte';
</script>

<ContentPage title="Introduction" subtitle="What we'll cover">
  <ul>
    <li>First point</li>
    <li>Second point</li>
  </ul>
</ContentPage>
```

Both templates add the navigation bar automatically.

### Positioning & size

Every slide lives on a fixed **1920×1080** canvas. Lay out with whatever CSS suits the slide:

- **Normal flow** — `ContentPage` centers your content; just write HTML.
- **Absolute positioning** — when you want pixel-precise placement, position elements absolutely within the 1920×1080 canvas. Because the size is fixed, `left: 960px` means the same thing on every screen.

You never write scaling code: in **FITTED** mode the framework transforms the whole canvas to fit the window (keeping the aspect ratio); in **SCALED** mode it shows the canvas at an exact factor (1:1 and beyond), centered and pannable.

### Interactivity (it's just Svelte)

Slides are Svelte components, so state and events work as usual — perfect for click-to-reveal, toggles, or anything interactive:

```svelte
<script>
  import Box from '$lib/components/Box.svelte';
  let show = false;
</script>

<button on:click={() => show = true}>Show the answer</button>

<Box bind:expanded={show} width={600} height={400}>
  <img src="answer.png" alt="the answer" />
</Box>
```

### Box — expandable overlay

`Box` pops its content up as a dimmed overlay. It opens when you set `expanded`, and closes on **CLOSE**, a click **outside**, or **Escape** — clicks *inside* are left alone, so the content stays interactive (e.g. selecting text).

```svelte
<Box bind:expanded={show} width={600} height={400}>
  <!-- any HTML or components -->
</Box>
```

Common props: `width`, `height`, `expanded`, `showClose`, `scrollable`, `top` / `left` / `bottom` / `right` (custom position), `shadowOpacity`.

### Code

Read-only code viewers built on the Monaco editor:

```svelte
<script>
  import Code    from '$lib/components/Code.svelte';
  import CodeBox from '$lib/components/CodeBox.svelte';
  let show = false;
</script>

<!-- inline, any language -->
<Code code={src} language="python" width="900px" height="300px" />

<!-- pop-up overlay, with an optional title bar -->
<CodeBox code={src} language="python" title="solution.py" bind:expanded={show} />
```

- `Code` / `CodeBox` — any language (via `language`), using Monaco's built-in folding.
- `JavaCode` / `JavaCodeBox` — Java-specialized, with a custom `import`/brace folding provider.

> Monaco is loaded from a CDN, so the code components need an internet connection.

### View source (and edit in dev)

Under **`pnpm dev`**, **☰ → SOURCE** and **EDIT** are available on **every** slide (no `ViewSource` required): the shell loads the current route's `+page.svelte` through `/__geekpresent/source-load`. On a **built** site, mount `ViewSource` (or `SourceView`) so SOURCE still has bytes without a server:

```svelte
<script>
  import ViewSource from '$lib/components/ViewSource.svelte';
  import source     from './+page.svelte?raw';   // Vite hands back the file's bytes
</script>

<!-- ...slide content... -->

<ViewSource {source} path="src/routes/slides/title.html/+page.svelte" />
```

- **☰ → SOURCE** opens a read-only Monaco `CodeBox` on the canvas (ViewSource's panel, or a deck-level fallback in dev). On a Text (no tool bar) the classic corner **`</> Source`** button still opens that panel when ViewSource is mounted.
- **☰ → EDIT**, or **EDIT** on the CodeBox title bar, opens a separate browser window at `/_source-edit`. Editing lives there on purpose: the slide canvas is CSS-scaled, and Monaco's caret metrics do not follow that scale. The popup is 1:1.
- In the edit window: **SAVE** (**Ctrl/Cmd+S**, or **Alt+. s**) writes the full `+page.svelte` via a vite-dev endpoint (same refusal language as ADJUST SAVE — **NOT ALLOWED** on a static host, never pre-disabled); **REFRESH** (**Ctrl/Cmd+Shift+R**, or **Alt+. r**) reloads from disk and confirms if the buffer differs; **CLOSE** (**Esc**, or **Alt+. c**) leaves the window and confirms if unsaved. **Alt+.** arms **R**/**S**/**C** briefly (amber bar); using a letter or pressing **Alt+.** again ends arm mode. Keys are handled in capture phase so Monaco cannot swallow Esc.
- With ViewSource, the source comes from Vite's `?raw` import so the panel cannot drift until you change the file; the path is still passed per page (`source` + `path`).
- Props: `source` (required when using ViewSource), `path`, `language` (defaults to `html`), `text` / `chrome` (Text-mode corner button only).
- Worked demo in the stock deck: `slides/viewsource-edit.html`.

### Animation controls

`AnimationBar` adds playback controls — a progress bar plus pause/play and restart — for a slide's own keyframe (`@keyframes`) animation. It drives the animations through the [Web Animations API](https://developer.mozilla.org/docs/Web/API/Web_Animations_API) (`getAnimations`), so you can pause to detach the animation from wall-clock time, drag the bar to scrub to any point, and restart from the top. It governs only the *in-page* CSS animations on the slide — page-to-page view transitions are untouched.

```svelte
<script>
  import AnimationBar from '$lib/components/AnimationBar.svelte';
</script>

<!-- a slide element with a finite @keyframes animation -->
<div class="builds">…</div>

<AnimationBar />
```

- **Self-gating.** It renders *nothing* on a slide with no finite, seekable `@keyframes` animation (CSS *transitions* and infinite loops are ignored), so it's safe to leave in a shared template — it simply won't appear where there's nothing to control.
- **Hosted in the ControlBar.** A plain deck-level bar (default `scope=".content"`, no `driven`/`host`) is the slide's one central control, so it's lifted out of the scaled slide and *portaled* into the deck's bottom ControlBar, next to the Table of Contents and pager. A **scoped** bar (`scope=".set-a"`, `<AnimationScene>`), a `driven` rail, or a `host`-set bar governs a region and stays in the slide. Pass `barHosted={false}` to force a plain bar back into the slide, or `barHosted` to force hosting.
- **Collapsed by default.** It first shows a low-profile **ANIMATE** button; clicking it reveals the bar (a one-way reveal).
- Props: `scope` (CSS selector for the subtree it searches, default `.content`), `highlight` (emphasize the ANIMATE button with the accent look), `startExpanded` (skip the button and show the controls straight away), and `barHosted` (override the auto host/in-slide placement). In a view-transition deck it re-detects on every navigation, so one bar in the deck layout serves every slide. The `slides/animation-bar.html` slide is a live demo; `transition/*-from.html` use it to scrub an in-page re-creation of each transition effect.

### Local assets

Keep a page's images next to its `+page.svelte` and `import` them — Vite bundles each one and hands you its URL:

```svelte
<script>
  import diagram from './diagram.png';
</script>

<img src={diagram} alt="diagram" />
```

(`static/` is still there for truly site-wide files.)

There's also a helper that fetches a YouTube thumbnail (and, optionally, generates a QR code) straight into a page folder:

```bash
cd src/routes/slides/my-slide.html
../../../../utils/prepare-youtube.sh https://youtu.be/<id> . my-video
```

then feed the thumbnail to the `YouTube` component, which shows it with a QR overlay linking to the video:

```svelte
<script>
  import YouTube   from '$lib/components/YouTube.svelte';
  import thumbnail from './my-video-TN.png';
</script>

<YouTube {thumbnail} alt="My talk" youtubeId="<id>" />
```

The QR is **encoded from the watch URL at render time**, so it can never drift from the
video — the `-QR.png` the script writes is only needed if you want to pin an existing
slide's exact pixels (`<YouTube {thumbnail} {qr} … />` still works).

Anywhere else, drop a code on a slide with `QRCode`:

```svelte
<QRCode value="https://geekpresent.dev" label="Slides" />
```

It encodes the symbol itself (`$lib/utils/qrCore.ts`, written from ISO/IEC 18004 — no npm
package, no `qrencode` binary) and draws it as SVG, so it stays crisp at whatever size the
projector scales the canvas to. An `http`/`mailto`/`tel` value links itself, so the code is
scannable by the room and clickable by whoever reads the deck as a page.

### Other components

The presentation under `src/routes/slides/` is itself a working reference — open any slide and read its source. Beyond the above you'll find **Note** (speaker notes), **Hint** (bottom-of-slide cue), **Label** (hoverable inline highlight), **ScrollDiv** (wheel-pannable container — `axis` x/y/both, with an optional draggable scrollbar; **WideDiv** is its `axis="x"` alias), **QuickCode** (small dark monospace box for short hand-written snippets — use `Code`/`CodeBox` for real syntax-highlighted code), and **Copyright** (auto-added corner notice).

---

## Display modes & speaker notes

Pick **FITTED / SCALED** from the control in the top-right corner:

- **FITTED** — the slide scales to fit the window. Use this to present.
- **SCALED** — the slide shows at an exact factor (1:1 and beyond), centered and pannable, with a minimap when it overflows. Pick a % or a target resolution from the menu. **Speaker notes** appear below the slide when you zoom out below the fit.

Add notes with the `Note` component (shown below the slide in SCALED mode; hidden in FITTED and when printing):

```svelte
<script>
  import Note from '$lib/components/Note.svelte';
</script>

<Note><p>Remember to mention X.</p></Note>
```

## Navigation & keyboard shortcuts

The nav bar (FIRST / PREV / NEXT / LAST), the **Table of Contents**, and the **Overview Page** grid are added automatically (window-edge chrome; opt out with `toolBar={false}` / `controlBar={false}` on `<SlideDeck>`).

| Key         | Action                       |
|-------------|------------------------------|
| Arrow Left  | Previous slide               |
| Arrow Right | Next slide                   |
| Space       | Next step, else next slide   |
| O           | Open the Overview Page grid  |
| E           | Toggle Overview **EDIT** deck (while Overview is open; dev) |
| Alt+. (⌥. on Mac) | Raise both chrome bars briefly for letter mnemonics |
| a / j / z / p / m / t / u | While bars raised: ANNOTATE / ADJUST / open zoom menu / PRESENT / ☰ / TOC / pause-resume a *live* Kiosk (underlined in the label when the letter fits; else a trailing chip; **u** is inert with no kiosk running). Zoom menu: ↑/↓, **c** → custom %, Enter |
| o / k / c / r / s / e | While bars raised or ☰ open: OVERVIEW / KIOSK / CAPTURE / PRINT / SOURCE / EDIT (PRINT is **r**; then flyout **cCwWtT**). **k** opens the Kiosk dialog while off, but toggles the panel's visibility while a kiosk is *live* — mouse-click ☰ → KIOSK still reaches the dialog either way |
| ← / → / ↑ / ↓ (chrome up) | Rove focus on the tool bar and ☰ rows (↓ opens ☰ from the hamburger; Enter activates) |
| Escape      | Close Overview / ToC / Box / ☰ / Kiosk dialog; disarm chrome raise |
| Enter (Kiosk dialog) | Start / OK |
| (in EDIT window) Ctrl+S / Ctrl+Shift+R / Esc | SAVE / REFRESH / CLOSE; Alt+. then r/s/c same (one-shot arm) |

`Space` advances a `<Steps>` build while one is running and pages the deck once it's spent, so a
build simply inserts sub-steps into the deck's forward march (`Shift+Space` reverses).

`O` opens the **Overview Page** — every slide at once, click one to jump. The tiles are the *real*
slides (each is the prerendered page in an `<iframe>`, scaled to fit), not screenshots, so they're
never stale and there's nothing to generate. They mount lazily as they scroll into view, so opening
a 65-slide deck boots the dozen you can see rather than all 65. Appendices (`hidden: true`) stay
out, exactly as they do in the ToC. In **`pnpm dev`**, Overview **EDIT** (or **E**) adds/unlists
slides via the vite-dev endpoints (production refuses with **NOT ALLOWED**). Letter shortcuts do
not fire while you're typing in a text field.

## Printing — and the handout

Each slide is its own page, so **Ctrl/Cmd-P on a slide prints that one slide** — and it prints as a *slide*: the whole canvas on paper its own shape, inside a half-inch margin, centred (the deck's chrome drops out, and the dark background is printed rather than dropped).

There's also a **PRINT** entry in the top tool bar's hamburger (☰) menu — groups are Overview · Capture/Print · Source/Edit. Hover **PRINT** for a nested flyout (keys **cCwWtT** while open):

- **Current slide** / **Current + notes** (**c** / **C**) — print here (notes grows the paper in place).
- **Whole deck** / **Whole + notes** (**w** / **W**) — the handout, one slide per page.
- **Thumbnail grid** / **Notes grid** (**t** / **T**) — contact sheet or thumbnail + notes rows.

The grids are `/_handout/<deck>.html?grid` and `?grid&notes`; like the handout they render the real slides (not screenshots) and let the browser paginate — as many tiles or rows as fit.

| URL | What prints |
| --- | --- |
| *any slide* | That slide, one page. |
| *any slide* `?notes` | That slide **and its `<Note>`** beneath it, still one page. |
| `/_handout/slides.html` | **The whole deck** — every slide, one per page. |
| `/_handout/slides.html?notes` | The same, with each slide's number, title and `<Note>` printed beneath it. |

Then Ctrl/Cmd-P → *Save as PDF*. The browser is the PDF engine, so there is no export step and no dependency. Every deck has a handout (`/_handout/<deck>.html`), a portrait deck prints on portrait paper, and a slide printed on its own is *exactly* the size it is inside the handout — both ask the same module.

The slide is **centred inside a margin** rather than bled to the edge, and both of those are load-bearing: a real printer cannot reach the edge of the paper, and a browser that declines the custom page size (Chrome and Edge honour it) prints on A4 instead — centred, the leftover splits evenly rather than pooling at the bottom.

The handout lives *outside* the deck on purpose: a deck is a folder of slides you own, so GeekPresent doesn't keep one of the names for itself. (It renders the slides as if it stood inside the deck — a `<base>` tag — so their relative links still work.)

It renders the real slide components — not screenshots — so it cannot drift from the deck, and your annotations print with it. Its one honest limit is the same one CAPTURE has: a slide holding a live `<iframe>` (a `WebSite` or `WebPage` embed) cannot be printed, so the handout names the embed on the sheet rather than leaving you a blank rectangle to puzzle over.

If your deck's canvas isn't 1920×1080, or it uses a theme, say so once in its `pages.ts` — the layout and the handout both read it, so they can't disagree:

```js
export const deck = { width: 1080, height: 1920, baseFontSize: '1.8em' };
```

## Text view (long-form)

Alongside slides, GeekPresent builds a second artifact type — a **Text**: *one long page* (fluid width that follows the window, capped at 1080px; height grows with the content) that you author by hand and scroll, reusing the same components. It's the read-at-your-own-pace counterpart to a deck.

- The site's **landing page** (`/`) and the sample at **`/text.html`** are Text artifacts — see `src/routes/(home)/` and `src/routes/text.html/`.
- The Table of Contents' "View as article" link opens `/text.html`.
- A Text renders the same components but in a flowing document; the on-slide navigation bar becomes a single **TOP** button. To start your own, copy the `src/routes/text.html/` route folder.

## Building & deploying to GitHub Pages

It's a fully static site (`@sveltejs/adapter-static`, every route prerendered).

### ⚠️ One-time setup: enable Pages (required before the first deploy)

GitHub Pages is **off by default** on a new repo or fork. Until you turn it on, the
deploy workflow fails at the **Setup Pages** step with
`Get Pages site failed ... Not Found`. Enable it once — pick either path:

- **Web UI:** open **Settings → Pages → Build and deployment**, and set
  **Source** to **GitHub Actions** (not "Deploy from a branch"). It applies
  immediately — there's no Save button.
- **CLI** (needs a token with `repo` scope on a repo you admin):

  ```bash
  gh api --method POST repos/<owner>/<repo>/pages -f build_type=workflow
  ```

Both set the same flag: Pages source = GitHub Actions. You only do this once per repo.

### Automatic deploy

Once Pages is enabled, every push to `main` triggers
[`.github/workflows/deploy-pages.yml`](.github/workflows/deploy-pages.yml), which
builds the site and publishes it to GitHub Pages — no manual step needed. The site
goes live at `https://<owner>.github.io/<repo>/`.

### Manual deploy (optional)

```bash
pnpm build      # outputs the static site to docs/
pnpm deploy     # publishes docs/ to GitHub Pages (via gh-pages)
```

### Notes

The build writes to `docs/`; `static/.nojekyll` ensures GitHub Pages serves SvelteKit's `_app/` directory (files starting with `_`) correctly. The site is served under the repo subpath (e.g. `/GeekPresent/`); adapter-static emits relative asset paths, so no `paths.base` configuration is required.

## SEO & social metadata

Every prerendered page carries SEO + social metadata in its **static HTML**: a
`<title>`, a `description`, OpenGraph + Twitter cards, and a `<link rel="canonical">`.
The build also emits a `sitemap.xml` (every prerendered route) and a `robots.txt`
into the site output. A reusable [`Seo.svelte`](src/lib/components/Seo.svelte)
component renders the tags; presentations set defaults via their `+layout.svelte`,
and a `pages.ts` entry can add a per-slide `description` / `image`.

In-page **assets stay relative** (so the build is portable to any sub-path or off
disk), but a handful of metadata fields — `og:url`, `og:image`, `twitter:image`,
`canonical`, and the sitemap — **must be absolute** (scrapers and search engines
can't resolve relative URLs). One build-time variable supplies that base URL:

| Variable | Default | Meaning |
| --- | --- | --- |
| `GEEKPRESENT_SITE_URL` | `https://nawaman.github.io/GeekPresent` | Absolute base URL for the absolute-only metadata. Set it to your custom domain (`GEEKPRESENT_SITE_URL=https://my.site pnpm build`). Set it **empty** (`GEEKPRESENT_SITE_URL=`) to omit the absolute-only tags entirely — useful when you don't yet know the deploy URL, so no half-formed `og:url`/`canonical` ships. |

It flows through `build-static.sh` too (env is inherited), e.g.
`GEEKPRESENT_SITE_URL=https://my.site ./build-static.sh ./dist`. A single-route
build (`./build-static.sh ./out text.html`) omits the sitemap by design.

The default social image is [`static/og-default.png`](static/og-default.png)
(1200×630); per-page images aren't auto-generated (a possible follow-up). Fonts
are still loaded from the Google Fonts CDN — self-hosting them is a separate
follow-up, not part of the SEO work.

## Build to a static folder of your choice

GitHub Pages is just *one* consumer of the static build. Because every route is
prerendered with **relative** asset paths, the output is fully portable — you can
drop it on any static host, serve it from any sub-path, or open it straight off
disk. The `build-static.sh` helper builds into a folder you name, without touching
the committed `docs/`:

```bash
./build-static.sh <output-dir> [route]
```

- **`<output-dir>`** (required) — where to write the site. Created if missing; if it
  already exists it must be empty or a previous output of this script (pass
  `--force` to overwrite anything else).
- **`[route]`** (optional) — build only **one** presentation/text instead of the
  whole site. Use the route name as it appears in the URL (`geeklight`,
  `slides`, `portrait`, `text.html`, …). Omit it to build everything (the home/landing
  page and every presentation).

Flags: `--zip` also packages the result into `<output-dir>.zip`; `--force`
overwrites a non-empty folder; `--precompress` keeps the `.br`/`.gz` copies (see
below); `-h`/`--help` prints full usage.

```bash
./build-static.sh ./dist                 # whole site            -> ./dist
./build-static.sh /tmp/out geeklight     # just the geeklight deck -> /tmp/out
./build-static.sh ./out text.html        # just the text sample  -> ./out
./build-static.sh --force ./dist         # overwrite a non-empty ./dist
./build-static.sh --zip ./dist           # build ./dist and ./dist.zip
```

Either way the result is self-contained. For a single presentation, the script
also writes a root `index.html` that redirects to that deck's first slide, and
includes the shared runtime (`_app/`), fonts, and favicon it needs.

### Preview the output

Serve the folder with any static server (don't open `index.html` over `file://` —
the routing and the CDN-loaded `Code` components expect `http://`):

```bash
npx http-server ./dist -p 8000        # then open http://127.0.0.1:8000/
# or:  python3 -m http.server 8000 --directory ./dist
```

Point the server at the folder you built — if you've already `cd`'d **into** it,
serve `.` (e.g. `npx http-server . -p 8000`) rather than `./dist`. (`pnpm preview`
only serves the adapter's `docs/` dir, not a custom output folder.)

### No precompressed clutter

`build-static.sh` skips the `.br`/`.gz` files by default, so the output stays lean
(e.g. the whole site is ~170 files instead of ~490). Those precompressed copies are
only useful when the host serves them directly (nginx `gzip_static`, Caddy, …); for
opening off disk, a simple static server, or GitHub Pages / Netlify / S3 (which
compress on the fly) they're dead weight. Pass `--precompress` if your server
actually consumes them:

```bash
./build-static.sh --precompress ./dist
```

> Under the hood the script sets `GEEKPRESENT_OUT` and `GEEKPRESENT_PRECOMPRESS`
> (both consumed by `svelte.config.js`). With those unset, `pnpm build` still writes
> to `docs/` with precompression on — exactly as before, so the GitHub Pages flow is
> unchanged. A third build var, `GEEKPRESENT_SITE_URL` (the absolute base URL for SEO
> metadata — see [SEO & social metadata](#seo--social-metadata)), is read by the SEO
> layer and is inherited by `build-static.sh` if you export it.
