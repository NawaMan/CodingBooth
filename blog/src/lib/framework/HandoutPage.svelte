<!--
  The handout — one deck, every slide, one printable document.

  Ctrl+P on a slide prints that slide, because each slide is its own SvelteKit document;
  that is the deck being honest about what it is, and it is no use to someone who wants
  the talk as a PDF. This route is the other artifact: it stacks all of a deck's slides
  into a single page and gives the printer the two rules it needs — a sheet the shape of
  the slide (`@page { size }`) and a break after each one. The browser is the PDF engine,
  so there is no export pipeline and no dependency; `Ctrl+P → Save as PDF` is the feature.

  It renders the REAL slide components, globbed from the routes (handoutDecks.ts) — not a
  copy, not a screenshot. So a handout cannot drift from the deck, and the slide you print
  is the slide you present, ink and all.

  Three things it does NOT do, each on purpose:

  - It is not a Text. text.html is a hand-authored document that happens to share the
    components; its own body says a Text "is not a stack of slides glued together". This
    IS the stack of slides, deliberately, and the two answer different questions.
  - It does not mount <SlideDeck>. The deck shell is a viewport — scaling, panning, chrome,
    and a slot gated on `initialized` so nothing renders before the browser arrives. A
    document wants none of that, and wants the opposite of the last: the slides must be in
    the prerendered HTML. So the handout publishes the deck's own context (setPages) and
    renders the slides directly, which is why they SSR here and nowhere else.
  - It does not pretend about embeds. A <WebSite>/<WebPage>/<YouTube> slide is a live
    <iframe>, and a printer hands you a blank rectangle for one. The handout finds them
    (captureCore.findBlockers — the same scan, the same reason, as CAPTURE's refusal) and
    NAMES them on the sheet in ink, so the reader knows a live thing stood there.
-->
<script lang="ts">
	import { onMount } from 'svelte';
	import { browser } from '$app/environment';
	import { base } from '$app/paths';
	import { page } from '$app/stores';
	import { setPages, setHandout } from '$lib/presentation';
	import { findBlockers } from '$lib/capture/captureCore';
	import {
		GRID_TILE_W,
		NOTES_THUMB_W,
		gridPageRule,
		handoutRefusalText,
		handoutSheets,
		notesGridPageRule,
		pageRule,
		refusedSummary,
		sheetMetrics,
		surfaceStyle,
		thumb
	} from '$lib/handout/handoutCore';
	import { applyPageRule } from '$lib/handout/pageRuleDom';
	import { deckCanvas, deckPages, deckUrlPath, slideComponent } from '$lib/handout/handoutDecks';
	import HandoutFrame from '$lib/handout/HandoutFrame.svelte';

	// The themed decks (geeklight, transition) carry a `deckClass` and their role tokens come
	// from these. Both files are ENTIRELY class-scoped (`.gp-deck`, `.theme-*`) — no :root, no
	// element rules — so importing them here is inert for a deck that names no theme, which is
	// exactly what the main deck relies on: its colours are the var() fallbacks in roles.css,
	// and nothing must quietly start overriding them.
	import '$lib/themes/themes.css';
	import '$lib/themes/roles.css';

	export let data: { deck: string };

	// The deck's surface — canvas, em lever, theme class, background, font — from its pages.ts,
	// which is the same place its +layout.svelte gets them. That is what makes the printed slide
	// the slide you present rather than a lookalike drawn on GeekPresent's defaults.
	const surface = deckCanvas(data.deck);
	const pages = deckPages(data.deck);
	const sheets = handoutSheets(pages);
	// Nested decks use a single-segment handout id (`references-shell`) but live at a
	// multi-segment URL (`references/shell`). Base must point at the public path so
	// relative links inside slides resolve into the real deck.
	const urlPath = deckUrlPath(data.deck);

	// The deck's own slide list, published to the slides exactly as its +layout.svelte would.
	// The templates read it (ContentPage's nav and ToC), so without it every slide here would
	// render a deck of nothing. They are chrome and never print — but they must not throw.
	setPages(pages);

	// Notes are always in the DOM; whether they are SHOWN is `showNotes` below, a class. That
	// split is what lets this page prerender: the server has no query string to read, so a
	// handout that BUILT the notes conditionally would hydrate into different markup than it
	// shipped. A class flip is invisible to hydration.
	setHandout({ notes: true });

	// `?notes` — the reader's choice, and only a starting value for the toggle they can also
	// just click. Browser-only, like every other flag the deck reads (SlideDeck's ?clean/?shot).
	let showNotes = browser && $page.url.searchParams.has('notes');

	// The ADJUST: the default one-slide-per-page handout, or one of the two compact OVERVIEW
	// layouts. It stays 'pages' until onMount, deliberately: the server has no query string, so
	// it prerenders the pages layout, and starting the client there too means hydration adopts a
	// matching tree before the URL flips it. A print page can afford one settling frame; a
	// hydration mismatch it cannot. `?grid` → the thumbnail grid; `?grid` + `?notes` → the notes
	// grid (thumbnail + note per row).
	let mode: 'pages' | 'grid' | 'notesgrid' = 'pages';

	const gridTile = thumb(surface, GRID_TILE_W);
	const notesThumbnail = thumb(surface, NOTES_THUMB_W);

	$: metrics = sheetMetrics(surface, showNotes);
	// The paper, written straight into the head rather than declared in <svelte:head>: an
	// {@html} there is adopted unchanged at hydration, so the rule the SERVER computed (no
	// notes, because the server has no query string) would outlive the reader turning notes on.
	// See handout/pageRuleDom.
	$: pageCss =
		mode === 'grid' ? gridPageRule() : mode === 'notesgrid' ? notesGridPageRule() : pageRule(metrics);
	$: if (browser) applyPageRule(pageCss);

	// Which sheets hold a live embed. Answerable only in a browser — it is a warning to whoever
	// is about to print, and printing needs a browser anyway — so it is empty at prerender.
	// Keyed by path; the slide still prints, minus the frame.
	let refusals: Record<string, string> = {};
	$: refusedTitles = sheets.filter((s) => refusals[s.path]).map((s) => s.title);
	$: summary = refusedSummary(refusedTitles);

	function rescan() {
		const found: Record<string, string> = {};
		for (const el of Array.from(document.querySelectorAll<HTMLElement>('.sheet'))) {
			const path = el.dataset.path;
			if (!path) continue;
			// The same scan CAPTURE runs, against the same Blocker: an <iframe> is a separate
			// document, and neither a rasteriser nor a printer can reach into one.
			const text = handoutRefusalText(findBlockers(el));
			if (text) found[path] = text;
		}
		refusals = found;
	}

	onMount(() => {
		// Read the layout now (not at init) so SSR and the first client render agree on `pages`.
		const sp = $page.url.searchParams;
		if (sp.has('grid')) mode = sp.has('notes') ? 'notesgrid' : 'grid';

		rescan();

		// …and again whenever an embed appears, which is the part a single scan gets wrong.
		// <WebSite> mounts its iframe LAZILY, on IntersectionObserver, so at the moment this
		// component mounts there is not an embed in the document to find — the frames come into
		// being one by one as the reader scrolls down the handout towards them. A scan that ran
		// once would therefore report a clean document and then print a hollow rectangle out of
		// the middle of it, which is precisely the lie the refusal exists to prevent. So the
		// warning tracks the document instead of a moment in it, and by the time anyone reaches
		// Ctrl+P the ink is already on the sheet.
		//
		// (A <YouTube> is not in this category and must not be: it is a thumbnail until someone
		// clicks it, and a thumbnail is an image. It prints perfectly, so it is never refused —
		// which is why this asks the DOM what is actually there rather than asking pages.ts what
		// the slide imports.)
		if (typeof MutationObserver !== 'function') return;
		let frames = document.querySelectorAll('iframe').length;
		const observer = new MutationObserver(() => {
			const now = document.querySelectorAll('iframe').length;
			if (now === frames) return; // slides mutate constantly (animations); embeds do not
			frames = now;
			rescan();
		});
		observer.observe(document.body, { childList: true, subtree: true });
		return () => observer.disconnect();
	});
</script>

<svelte:head>
	<title>{data.deck} — handout</title>
	<meta name="robots" content="noindex" />
	<!-- The one tag that lets this document live outside the deck it prints. Every slide in it
	     links RELATIVELY (`./appendix-detail.html`, `../`), and those links mean "next to me in
	     the deck" — so the document declares that it stands where the deck stands, and the
	     browser, and SvelteKit's prerender crawler, both resolve them into the real slides. See
	     +page.js. Everything else here is root-absolute, so this moves nothing but the links. -->
	<base href="{base}/{urlPath}/" />
</svelte:head>

<div class="handout" class:with-notes={showNotes}>
	<!-- The only chrome this document has, and it never prints. -->
	<div class="bar no-print">
		<button class="print" on:click={() => window.print()}>Print / Save as PDF</button>
		{#if mode === 'pages'}
			<label class="toggle">
				<input type="checkbox" bind:checked={showNotes} />
				Speaker notes
			</label>
		{/if}
		<span class="count">
			{sheets.length}
			{sheets.length === 1 ? 'slide' : 'slides'}
			· {mode === 'grid' ? 'thumbnail grid' : mode === 'notesgrid' ? 'notes grid' : `${metrics.pageWidthIn}in × ${metrics.pageHeightIn}in`}
		</span>
		{#if summary}
			<span class="warn">⚠ {summary}</span>
		{/if}
	</div>

	{#if mode === 'pages'}
		{#each sheets as sheet (sheet.path)}
			{@const Slide = slideComponent(data.deck, sheet.path)}
			<section
				class="sheet"
				class:blocked={!!refusals[sheet.path]}
				data-path={sheet.path}
				style="width: {metrics.slideWidthPx}px; padding-bottom: {metrics.notesHeightPx}px;"
			>
				<div
					class="slide"
					style="width: {metrics.slideWidthPx}px; height: {metrics.slideHeightPx}px;"
				>
					<div
						class="canvas {surface.deckClass}"
						style="{surfaceStyle(surface)} transform: scale({metrics.scale});"
					>
						{#if Slide}
							<svelte:component this={Slide} />
						{:else}
							<!-- A pages.ts entry with no route behind it. One named sheet, not a broken
							     document. -->
							<p class="missing">No slide at {data.deck}/{sheet.path}</p>
						{/if}
					</div>
				</div>

				{#if refusals[sheet.path]}
					<p class="refusal">⚠ {refusals[sheet.path]}</p>
				{/if}

				<!-- The footer is the notes band's own header, so it exists only when there IS a band.
				     Without notes the sheet is the slide, edge to edge, and a page number printed over
				     it would be printed over the slide. -->
				{#if showNotes}
					<p class="caption">
						<span class="num">{sheet.number}</span>
						<span class="title">{sheet.title}</span>
						{#if sheet.appendix}<span class="appendix">appendix</span>{/if}
					</p>
				{/if}
			</section>
		{/each}

	{:else if mode === 'grid'}
		<!-- The thumbnail grid: a contact-sheet. Tiles flow and wrap, and the browser breaks
		     between rows — as many as fit the landscape page, no count to hardcode. Each tile is
		     the REAL slide scaled to GRID_TILE_W (not a screenshot), so it prints as itself. -->
		<div class="grid-doc">
			{#each sheets as sheet (sheet.path)}
				{@const Slide = slideComponent(data.deck, sheet.path)}
				<div class="gtile" data-path={sheet.path} class:blocked={!!refusals[sheet.path]}>
					<div class="gtile-box" style="width: {gridTile.widthPx}px; height: {gridTile.heightPx}px;">
						<div
							class="gtile-canvas {surface.deckClass}"
							style="{surfaceStyle(surface)} transform: scale({gridTile.scale});"
						>
							{#if Slide}<svelte:component this={Slide} />{/if}
						</div>
					</div>
					<span class="gtile-cap"><b>{sheet.number}</b> {sheet.title}</span>
				</div>
			{/each}
		</div>

	{:else if mode === 'notesgrid'}
		<!-- The notes grid: one row per slide, thumbnail LEFT and the note RIGHT, on a portrait
		     page. The slide is rendered TWICE per row — a small thumbnail with notes off, and a
		     full-size note-only render beside it — because the note lives inside the slide's own
		     scaled canvas and cannot be pulled out of that scale by CSS. See HandoutFrame. -->
		<div class="notes-doc">
			{#each sheets as sheet (sheet.path)}
				{@const Slide = slideComponent(data.deck, sheet.path)}
				<div class="nrow" data-path={sheet.path} class:blocked={!!refusals[sheet.path]}>
					<div class="nrow-thumb" style="width: {notesThumbnail.widthPx}px; height: {notesThumbnail.heightPx}px;">
						<div
							class="nrow-canvas {surface.deckClass}"
							style="{surfaceStyle(surface)} transform: scale({notesThumbnail.scale});"
						>
							{#if Slide}
								<HandoutFrame notes={false}><svelte:component this={Slide} /></HandoutFrame>
							{/if}
						</div>
					</div>
					<div class="nrow-note">
						<span class="nrow-cap"><b>{sheet.number}</b> {sheet.title}</span>
						<div class="nrow-note-body">
							{#if Slide}
								<HandoutFrame notes={true}><svelte:component this={Slide} /></HandoutFrame>
							{/if}
						</div>
					</div>
				</div>
			{/each}
		</div>
	{/if}
</div>

<style>
	/* global.css centres the document — `html, body { display: flex; align-items: center;
	   height: 100% }` — because every other page in this project is ONE slide sitting in the
	   middle of a window. A handout is the one page that is a document: it is sixty-odd sheets
	   tall and must flow from the top. This is route CSS, so it lands only where the handout does. */
	:global(html),
	:global(body) {
		display: block;
		height: auto;
	}

	/* ── Screen ──────────────────────────────────────────────────────────────────
	   The screen view is a preview of the paper: the sheets are the same boxes, laid
	   out down a grey desk. What you scroll is what you get. */
	.handout {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 24px;
		padding: 24px 0 64px;
		background: #4a4a4a;
		min-height: 100vh;
	}

	.bar {
		position: sticky;
		top: 0;
		z-index: 10;
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 16px;
		padding: 10px 16px;
		border-radius: 8px;
		background: #1c1c1c;
		color: #eee;
		font-family: ui-sans-serif, system-ui, sans-serif;
		font-size: 14px;
		box-shadow: 0 2px 12px rgb(0 0 0 / 35%);
	}
	.bar .print {
		padding: 6px 14px;
		border: 1px solid #666;
		border-radius: 6px;
		background: #2e2e2e;
		color: #eee;
		font: inherit;
		cursor: pointer;
	}
	.bar .print:hover {
		background: #3a3a3a;
	}
	.bar .toggle {
		display: flex;
		align-items: center;
		gap: 6px;
		cursor: pointer;
	}
	.bar .count {
		opacity: 0.7;
	}
	.bar .warn {
		color: #ffcf6b;
	}

	/* The sheet IS the page, so it is the sheet — not the slide box inside it — that clips: the
	   canvas below is 50px wider than the canvas proper (SlideDeck's own box arithmetic, copied
	   faithfully), and that bleed must not widen the document past the paper, or the printer
	   shrinks the entire deck to fit. */
	.sheet {
		position: relative;
		display: flex;
		flex-direction: column;
		overflow: hidden;
		background: #fff;
		box-shadow: 0 2px 10px rgb(0 0 0 / 40%);
	}

	/* The slide's box on the sheet: the scaled canvas's true size. */
	.slide {
		position: relative;
		overflow: hidden;
		flex: none;
	}

	/* …except with notes, where it must NOT clip: the <Note> lives inside the slide component,
	   so it is inside the scaled canvas, and a transformed element is the containing block for
	   everything absolute within it — there is no way to lift the note out. So the note is left
	   where it is and allowed to paint BELOW the slide box, into the band the sheet reserves for
	   it. The sheet still clips the horizontal bleed. */
	.handout.with-notes .slide {
		overflow: visible;
	}

	/* The band under the slide is `padding-bottom` on the sheet, set inline from
	   `metrics.notesHeightPx` — the same three inches the @page rule grew by, from the same
	   number, so the two cannot drift. Padding rather than an element because what fills it —
	   the note — cannot be an element here; see above. */

	/* The canvas: a FAITHFUL COPY of SlideDeck's `.content` — the surface a slide is authored
	   against — scaled from the top-left so it lands flush in the box above. Every declaration
	   down to `calc(var(--canvas-w) + 20px)` is copied deliberately, and the odd arithmetic is
	   the reason why: a <Block> is placed at absolute canvas pixels inside this box, so a box
	   that is 50px wider than the canvas (which SlideDeck's is, and which the .slide above
	   clips, exactly as the deck's viewport does) puts every Block where the deck puts it. Guess
	   at a clean 1920x1080 instead and the whole deck prints subtly out of position.
	   Cross-check against SlideDeck.svelte's `.content` if you touch either.

	   `.gtile-canvas` (grid) and `.nrow-canvas` (notes grid) are the SAME surface at a smaller
	   scale, so they share this rule — a thumbnail is a true miniature of the printed slide. */
	.canvas,
	.gtile-canvas,
	.nrow-canvas {
		position: relative;
		transform-origin: top left;

		font-size: var(--base-font);
		width: calc(var(--canvas-w) + 20px);
		height: calc(var(--canvas-h) - 30px);
		overflow: visible;
		padding: 15px;
		display: flex;
		justify-content: center;
		align-items: center;
		color: var(--surface-fg, #c0f1ff);
		background: var(--content-bg, var(--surface-bg, #181818));
		font-family: var(--content-font, 'Noto Sans', 'Cormorant Garamond', serif);

		/* A deck is light-on-dark, and a browser does not print background colours unless it is
		   told to ("Background graphics", off by default) — which would hand the reader white
		   paper with white text on it. This is the one property that says the background IS the
		   slide, not decoration around it, and it is inherited, so the whole slide obeys. */
		-webkit-print-color-adjust: exact;
		print-color-adjust: exact;
	}

	.missing {
		padding: 40px;
		color: #900;
		font-family: ui-monospace, monospace;
	}

	/* ── The thumbnail grid ──────────────────────────────────────────────────────────
	   Tiles flow and wrap; the browser breaks between rows. On screen they sit on the same grey
	   desk as the sheets; on paper they fill the landscape page. */
	.grid-doc {
		display: flex;
		flex-wrap: wrap;
		justify-content: center;
		align-content: flex-start;
		gap: 14px;
		width: 10in; /* the landscape page's printable width; centres the preview on the desk */
		max-width: 100%;
	}
	.gtile {
		display: flex;
		flex-direction: column;
		gap: 3px;
	}
	/* The tile's box: the scaled canvas's true size, clipping its bleed — the same bargain the
	   full sheet strikes, just smaller. A hairline so a dark slide has an edge on white paper. */
	.gtile-box {
		overflow: hidden;
		background: #fff;
		border: 1px solid #d0d0d0;
	}
	.gtile-cap {
		font-family: ui-sans-serif, system-ui, sans-serif;
		font-size: 11px;
		color: #333;
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
		max-width: 236px;
	}
	/* A tile is a picture, never notes — this layout is the no-notes one. The note renders into
	   the DOM (the page keeps notes on for the pages layout's toggle), so hide it here. */
	.gtile-canvas :global(.note) {
		display: none;
	}

	/* ── The notes grid ──────────────────────────────────────────────────────────────
	   One row per slide: a fixed thumbnail on the left, the note (full size, readable) on the
	   right. Rows flow down the portrait page; the browser breaks between them. */
	.notes-doc {
		display: flex;
		flex-direction: column;
		gap: 16px;
		width: 7.5in; /* the portrait page's printable width; centres the preview on the desk */
		max-width: 100%;
	}
	.nrow {
		display: flex;
		gap: 16px;
		align-items: flex-start;
		padding-bottom: 14px;
		border-bottom: 1px solid #ccc;
	}
	.nrow-thumb {
		flex: none;
		overflow: hidden;
		background: #fff;
		border: 1px solid #d0d0d0;
	}
	.nrow-note {
		flex: 1 1 auto;
		min-width: 0;
	}
	.nrow-cap {
		display: block;
		margin-bottom: 4px;
		font-family: ui-sans-serif, system-ui, sans-serif;
		font-size: 12px;
		font-weight: 600;
		color: #222;
	}
	/* The note-only render: the slide's roots (its visual — whatever shape it is: a template's
	   `.page`, bare Blocks, a StateBox, a Video…) are DIRECT children of this box, alongside the
	   `.note`. Hide every direct child, then bring the note back. Hiding by the root rather than by
	   naming the visual is what makes this survive the diversity of real slides — the visual is the
	   thumbnail on the left; here we want only the words. */
	.nrow-note-body > :global(*) {
		display: none;
	}
	.nrow-note-body > :global(.note) {
		display: block;
		position: static;
		width: auto;
		max-width: none;
		min-height: 0;
		max-height: none;
		overflow: visible;
		margin: 0;
		padding: 0;
		border: none;
		border-radius: 0;
		background: transparent;
		color: #222;
		font-family: ui-sans-serif, system-ui, sans-serif;
		font-size: 12.5px;
		line-height: 1.4;
	}

	/* ── Chrome inside a slide ───────────────────────────────────────────────────
	   A slide rendered outside the deck shell still builds its own nav bar, ToC and
	   buttons. They are already marked for exactly this — `.no-print`/`.gp-chrome` is
	   the repo's one convention for "this is chrome, not content" (captureCore's
	   CHROME_SELECTOR strips the same two, for the same reason) — so the handout hides
	   them on screen too, since the screen here is a preview of the paper. */
	.sheet :global(.no-print),
	.sheet :global(.gp-chrome) {
		display: none;
	}

	/* ── Notes ───────────────────────────────────────────────────────────────────
	   A <Note> on screen is a beige card with a fixed height and its own scrollbar, which is
	   right for a window and wrong for paper: there is nothing to scroll, and here the note is
	   not a card ON the slide — it is the prose UNDER it. So it is stripped back to plain text
	   that grows to its content, in the band the sheet reserves.

	   It stays ABSOLUTE, and that is the one line to not to change. `.canvas` is a copy of
	   SlideDeck's `.content`, which is `display: flex` — a ROW — so a note made `static` becomes
	   a flex sibling of the slide and sits BESIDE it, squeezing the slide to two-thirds of the
	   page. Absolute takes it out of the flex flow, and `top: 100%` puts it just below the
	   canvas it is anchored to.

	   The selector is deep because it must out-specify both the chrome rule above and
	   global.css's `.no-print { display: none }` — a note is marked `.no-print`, since in every
	   OTHER context it is the speaker's, not the audience's. No `!important`: it wins on
	   specificity, honestly. */
	.handout.with-notes .sheet :global(.note) {
		display: block;
		position: absolute;
		top: calc(100% + 30px);
		left: 0;
		width: 100%;
		height: auto;
		max-height: none;
		min-height: 0;
		overflow: visible;
		margin: 0;
		padding: 0;
		border: none;
		border-radius: 0;
		background: transparent;
		color: #222;
		font-size: 1em;
	}
	.handout:not(.with-notes) .sheet :global(.note) {
		display: none;
	}

	/* Pinned to the foot of the sheet rather than laid out after the slide, because the note it
	   shares the band with is absolutely positioned (see above) and so has no height the caption
	   could sit below. Two absolutes, each anchored to an end of the band, cannot collide. */
	.caption {
		position: absolute;
		bottom: 10px;
		left: 16px;
		right: 16px;
		display: flex;
		align-items: baseline;
		gap: 10px;
		margin: 0;
		padding: 0;
		color: #444;
		font-family: ui-sans-serif, system-ui, sans-serif;
		font-size: 13px;
	}
	.caption .num {
		font-weight: 700;
	}
	.caption .title {
		font-weight: 600;
	}
	.caption .appendix {
		padding: 1px 6px;
		border-radius: 999px;
		background: #eee;
		font-size: 11px;
		text-transform: uppercase;
		letter-spacing: 0.06em;
	}

	.refusal {
		margin: 0;
		padding: 8px 16px;
		background: #fff3d6;
		color: #6b4b00;
		font-family: ui-sans-serif, system-ui, sans-serif;
		font-size: 13px;
	}

	/* ── Paper ───────────────────────────────────────────────────────────────────
	   The sheet is the page. `@page { size }` (emitted in the head) already gave the
	   paper the slide's shape and no margin, so all that is left is to break after each
	   sheet and take the desk away. */
	@media print {
		/* The bar wears `.no-print`, but global.css's `.no-print { display: none }` is a single
		   class and this component's own `.bar { display: flex }` is a scoped one — two classes,
		   so it WINS, and the toolbar printed itself as page 1. A component that sets `display`
		   on something it also marks `.no-print` has to retract it here; the marker alone is not
		   enough to beat it. */
		.bar {
			display: none;
		}
		/* Sheets are centred on the paper (`margin: 0 auto` below) for the same reason the deck
		   centres a printed slide: `@page { size }` is honoured by Chrome and Edge but not by
		   every engine, and one that prints on A4 instead scales each sheet to fit its width.
		   Centred, the leftover splits evenly instead of pooling on one side. */
		.handout {
			display: block;
			gap: 0;
			padding: 0;
			background: none;
			min-height: 0;
		}
		.sheet {
			margin: 0 auto;
			box-shadow: none;
			break-after: page;
			page-break-after: always;
			break-inside: avoid;
			page-break-inside: avoid;
		}
		.sheet:last-child {
			break-after: auto;
			page-break-after: auto;
		}
		/* The live embed the printer cannot draw: it prints as a blank rectangle, and a
		   blank rectangle is a lie — it reads as an empty slide. Blank it deliberately and
		   let the refusal beside it say what stood there. */
		.sheet.blocked :global(iframe) {
			visibility: hidden;
		}

		/* The thumbnail grid on paper: fill the landscape page, tiles never split across a page. */
		.grid-doc {
			width: auto;
			gap: 12px;
			justify-content: flex-start;
		}
		.gtile {
			break-inside: avoid;
			page-break-inside: avoid;
		}
		.gtile.blocked :global(iframe) {
			visibility: hidden;
		}

		/* The notes grid on paper: fill the portrait page, a row never split across a page. */
		.notes-doc {
			width: auto;
		}
		.nrow {
			break-inside: avoid;
			page-break-inside: avoid;
		}
		.nrow.blocked :global(iframe) {
			visibility: hidden;
		}
	}
</style>
