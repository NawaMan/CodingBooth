<!--
  SlideDeck — the reusable shell for a Presentation artifact.

  A Presentation is many discrete, fixed-size slide pages. This component is the
  whole canvas: it draws a fixed width x height box and shows it in one of two
  display modes (see $lib/stores/displayMode):
    - FITTED: scale the box to fit the window, preserving aspect (present mode).
    - SCALED: show the box at an exact factor (1 = native px), centred and
      pannable when it overflows the window (inspect mode), with a minimap.
  It also mounts the slide chrome (Table of Contents, display-mode control,
  copyright). The slides themselves flow in via the default <slot/>.

  Orientation lives HERE, set by a deck's +layout.svelte through the width/height
  props — never a runtime toggle. A landscape deck wraps its <slot/> in
  <SlideDeck width={1920} height={1080}>; a portrait deck (e.g. a YouTube Short)
  uses <SlideDeck width={1080} height={1920}>. Each slide's layout is authored
  for its deck's fixed dimension, so a deck is landscape OR portrait, full stop.

  Note: the deck's +layout.svelte must still call setPages(pages) itself — the
  slotted slide content is lexically owned by the layout, so it reads the
  layout's context, not this component's. `pages` is passed here only for the
  Table of Contents rendered inside this shell.
-->
<script lang="ts">
	import '$lib/styles/global.css';
	import '$lib/styles/note.css';
	import '$lib/styles/presentation.css';
	import '$lib/styles/tooltip.css';

	import Copyright      from '$lib/components/Copyright.svelte';
	import TableOfContent from '$lib/components/TableOfContent.svelte';
	import SizeMode       from '$lib/components/SizeMode.svelte';
	import SlideMap       from '$lib/components/SlideMap.svelte';
	import Seo            from '$lib/components/Seo.svelte';
	import { SITE_DESCRIPTION } from '$lib/seo/config';

	import { browser }    from '$app/environment';
	import { page }       from '$app/stores';
	import { onMount }    from 'svelte';
	import { displayMode, displayFactor, clampFactor } from '$lib/stores/displayMode';
	import type { DisplayMode } from '$lib/stores/displayMode';
	import { documentTitle } from '$lib/utils/navigate';
	import type { Page }  from '$lib/utils/navigate';

	/** This deck's slide list — for the Table of Contents rendered in the shell. */
	export let pages: Array<Page> = [];
	/** Presentation-level document title (the deck name) — the <title> counterpart
	    to the presentation favicon a +layout.svelte sets. Composed with the current
	    slide's own `title` into the browser-tab <title>; falls back to the site
	    default (SITE_TITLE) when left undefined. */
	export let title: string | undefined = undefined;
	/** Presentation-level SEO description, used for every slide that doesn't set its
	    own in pages.ts. Defaults to the site description. */
	export let description: string = SITE_DESCRIPTION;
	/** Presentation-level social/OG image (absolute URL or site-relative path), used
	    for slides without their own. Undefined falls back to the site-default image. */
	export let image: string | undefined = undefined;
	/** Presentation-level alt text for the social image, used for slides without
	    their own. Undefined falls back to the default card alt (see Seo). */
	export let imageAlt: string | undefined = undefined;
	/** Canvas size in px. Landscape: 1920x1080. Portrait (Tall): 1080x1920. */
	export let width  = 1920;
	export let height = 1080;
	/* Base font-size lever: every em-based size in the reused components scales
	   from here in one place. The landscape canvas grew x1.5 from the original
	   1280x720, hence 1.5em; a narrower portrait canvas wants a smaller base. */
	export let baseFontSize = '1.5em';
	/* Optional extra classes for the outer frame — the hook a deck uses to opt into
	   a theme. Pass "gp-deck theme-green" (and import themes.css + roles.css in the
	   deck's +layout.svelte) to recolour the whole canvas via the role tokens. Left
	   empty by default, so existing decks render exactly as before. */
	export let deckClass = '';
	/* Exact-fit mode. When false (the landscape default) the content box keeps its
	   legacy slack (+20 width / -30 height / 15 padding) — values hand-tuned for the
	   1920 canvas, whose wider-than-frame aspect leaves a small symmetric letterbox.
	   That gap is a tiny fraction at 1920 but visible on the much smaller portrait
	   render, so a Tall opts into fill=true: the content box IS the canvas
	   (border-box, no slack), so it shares the frame's aspect exactly and fills it
	   edge to edge. Either way the FITTED view scale (adjustSize) is an exact
	   Math.min fit, so content always sits inside the frame border. */
	export let fill = false;
	/* Optional per-deck overrides for the content surface — for themed decks (e.g.
	   GeekLight) that want a custom background (a watercolor image) or font while
	   reusing all the canvas/scaling machinery. Undefined keeps the standard dark
	   surface + Noto Sans. Passed through as CSS vars the .content rule falls back on. */
	export let contentBackground: string | undefined = undefined;
	export let contentFont: string | undefined = undefined;

	let viewport:  HTMLElement;
	let container: HTMLElement;
	let content:   HTMLElement;

	let mode: DisplayMode = $displayMode;
	let factor = clampFactor($displayFactor);
	let initialized = false;
	$: isFitted = mode === 'FITTED';
	$: aspectRatio = width / height;

	// Minimap state (SCALED only): which slice of the slide is currently on screen,
	// as fractions of the scaled slide. Recomputed on scroll / resize / mode change.
	let mapVisible = false;
	let mapRect = { left: 0, top: 0, width: 1, height: 1 };
	const clamp01 = (n: number) => Math.max(0, Math.min(1, n));

	// Anchor the overlay's display-mode control to the FRAME's top-right corner, so
	// it sits on the slide instead of adrift in the letterbox margin — but clamp it
	// to the viewport so it stays reachable when a zoomed-in SCALED frame pushes that
	// corner off-screen. Recomputed (with the minimap) on scroll / resize / change.
	let ctrlTop = '12px';
	let ctrlRight = '16px';
	const CTRL_INSET = 12;
	function updateOverlay() {
		updateMap();
		if (!container) return;
		const r = container.getBoundingClientRect();
		ctrlTop   = `${Math.round(Math.max(CTRL_INSET, r.top + CTRL_INSET))}px`;
		ctrlRight = `${Math.round(Math.max(CTRL_INSET, window.innerWidth - r.right + CTRL_INSET))}px`;
	}

	// Page-level favicon. The shell renders at SSR (only the slide *content* below
	// is gated on onMount), so emitting the current slide's favicon HERE puts it in
	// the prerendered HTML — no flicker, works without JS. Last <link rel="icon">
	// wins, so a slide's favicon (declared in its pages.ts entry) overrides both the
	// site default (app.html) and any presentation favicon set in the deck's layout.
	$: currentSlide   = $page.url.pathname.replace(/\/+$/, '').split('/').pop();
	$: currentFavicon = pages.find((p) => p.path === currentSlide)?.favicon;
	// `?clean` hides all shell chrome (ToC, display-mode control, copyright, nav bar,
	// minimap) for an unobstructed screen capture — e.g. the /tests calibration
	// target. `browser &&` short-circuits so url.searchParams is never read during
	// prerender (SvelteKit forbids it — a prerendered page can't vary by query
	// string). Client hydration re-evaluates with browser=true and picks up ?clean.
	$: clean = browser && $page.url.searchParams.has('clean');
	// Page-level document title, same cascade idea as the favicon above but emitted
	// as ONE <title> (the browser uses the FIRST <title>, so it can't stack the way
	// the favicon links do): the current slide's own `title` from pages.ts, composed
	// with this deck's `title` prop into "Slide — Deck". See documentTitle.
	$: currentTitle   = pages.find((p) => p.path === currentSlide)?.title;
	$: docTitle       = documentTitle(currentTitle, title);
	// SEO description/image cascade: the current slide's own pages.ts value, else
	// the deck-level default. Emitted (with title/canonical/og/twitter) by <Seo>.
	$: currentDescription = pages.find((p) => p.path === currentSlide)?.description ?? description;
	$: currentImage       = pages.find((p) => p.path === currentSlide)?.image ?? image;
	$: currentImageAlt    = pages.find((p) => p.path === currentSlide)?.imageAlt ?? imageAlt;

	// Recompute the minimap's "you are here" rectangle from the live scroll position.
	// Only meaningful in SCALED when the scaled slide overflows the viewport (else
	// there is nothing to pan, so the map is hidden).
	function updateMap() {
		if (!viewport || !container || mode !== 'SCALED' || clean) { mapVisible = false; return; }
		const vw = viewport.clientWidth,  vh = viewport.clientHeight;
		const sw = container.offsetWidth,  sh = container.offsetHeight;
		mapVisible = sw > vw + 1 || sh > vh + 1;
		if (!mapVisible) return;
		mapRect = {
			left:   clamp01(viewport.scrollLeft / sw),
			top:    clamp01(viewport.scrollTop  / sh),
			width:  clamp01(vw / sw),
			height: clamp01(vh / sh),
		};
	}

	// Park the scroll so the slide starts centred when it overflows (zoom-in). Pairs
	// with `safe center` on .viewport, which otherwise start-aligns an overflowing
	// child (top-left) — reachable, but jarring as an entry point.
	function centerScroll() {
		if (!viewport || !container) return;
		viewport.scrollLeft = Math.max(0, (container.offsetWidth  - viewport.clientWidth)  / 2);
		viewport.scrollTop  = Math.max(0, (container.offsetHeight - viewport.clientHeight) / 2);
	}

	function adjustSize(recenter = false) {
		if (!container) return;

		if (mode === 'SCALED') {
			// Exact factor: the frame is the canvas at `factor`, the content scales by
			// the same factor from its top-left so the two stay flush. The .viewport
			// scrolls/pans when this overflows the window.
			container.style.width  = `${Math.round(width  * factor)}px`;
			container.style.height = `${Math.round(height * factor)}px`;
			content.style.transform = `scale(${factor})`;
			content.style.transformOrigin = 'top left';
			if (recenter) centerScroll();
			updateOverlay();
			return;
		}

		// FITTED — fit the canvas to the window by aspect. Size the cross axis from the
		// INNER box (client*, excludes the 1.5px border), NOT the border-box (offset*):
		// the scale below divides by client*, so using offset* would leave the inner
		// box ~(3px * aspect) larger than the scaled content — a thin black gap between
		// the content and the frame on the non-binding axis. client* makes the inner
		// box a true `aspect` rectangle, so the content fills it flush on both axes.
		const windowRatio = window.innerWidth / window.innerHeight;
		if (windowRatio > aspectRatio) {
			container.style.height = 'calc(100vh - 10px)';
			container.style.width  = `${Math.round(container.clientHeight * aspectRatio)}px`;
		} else {
			container.style.width  = 'calc(100vw - 10px)';
			container.style.height = `${Math.round(container.clientWidth / aspectRatio)}px`;
		}
		// Exact fit: scale the content's TRUE border-box down to the container's INNER
		// box by whichever axis binds. Math.min guarantees no overflow on either axis,
		// so the frame border stays visible all around and content sits inside. The box
		// is the full canvas in fill mode; otherwise it carries the legacy slack (width
		// +20 + 2x15 padding = width + 50; height nets back to the canvas height).
		const boxW = fill ? width : width + 50;
		const boxH = height;
		const scale = Math.min(container.clientWidth / boxW, container.clientHeight / boxH);
		content.style.transform = `scale(${scale})`;
		content.style.transformOrigin = 'center center';
		updateOverlay();
	}

	// Wrap a re-layout in the body.rendering class (suppresses paint of half-applied
	// styles); recenter only on a mode/factor change, never on a resize mid-pan.
	function apply(recenter: boolean) {
		document.body.classList.add('rendering');
		adjustSize(recenter);
		document.body.classList.remove('rendering');
	}

	onMount(() => {
		if (!browser) return;
		const unsubMode   = displayMode.subscribe(v   => { mode = v;                  if (initialized) apply(true); });
		const unsubFactor = displayFactor.subscribe(v => { factor = clampFactor(v);   if (initialized) apply(true); });
		const onResize = () => adjustSize(false);
		window.addEventListener('resize', onResize);
		initialized = true;
		apply(true);
		return () => {
			unsubMode();
			unsubFactor();
			window.removeEventListener('resize', onResize);
		};
	});
</script>

<!-- Seo owns the <title> + SEO/social tags; the favicon link stays here (its
     last-one-wins cascade is separate from the single <title> Seo emits). -->
<Seo
	title={docTitle}
	description={currentDescription}
	image={currentImage}
	imageAlt={currentImageAlt}
	type="website"
/>

<svelte:head>
	{#if currentFavicon}
		<link rel="icon" href={currentFavicon} />
	{/if}
</svelte:head>

<!-- .viewport is the screen-fixed pan area. It centres the frame when it fits and
     scrolls (top-left reachable, via `safe center`) when SCALED overflows it. -->
<div class="viewport" class:zoom={!isFitted} bind:this={viewport} on:scroll={updateOverlay}>
	<div
		class="container {deckClass}"
		class:fit-mode={isFitted}
		class:zoom-mode={!isFitted}
		class:clean={clean}
		style="--canvas-w:{width}px; --canvas-h:{height}px; --aspect:{aspectRatio}; --base-font:{baseFontSize};{contentBackground ? ` --content-bg:${contentBackground};` : ''}{contentFont ? ` --content-font:${contentFont};` : ''}"
		bind:this={container}
	>
		<div class="content" class:fill class:ready={initialized} bind:this={content}>
			{#if initialized}
			<slot />
			<TableOfContent {pages} />
			<Copyright />
			{/if}
		</div>
	</div>
</div>

<!-- Screen-fixed chrome that must stay reachable regardless of pan/zoom: the
     display-mode control and the minimap. Kept OUT of .content (which is scaled
     and panned) so they never drift off-screen. Hidden by ?clean. -->
{#if initialized && !clean}
<div class="overlay" style="--base-font:{baseFontSize}; --ctrl-top:{ctrlTop}; --ctrl-right:{ctrlRight};">
	<SizeMode {width} {height} />
	{#if mapVisible}
	<SlideMap {width} {height} rect={mapRect} />
	{/if}
</div>
{/if}

<style>
	.viewport {
		position: fixed;
		inset: 0;
		/* FITTED never scrolls (the frame always fits); hidden also clips any phantom
		   sub-pixel overflow from the scaled content. SCALED opts into scroll/pan. */
		overflow: hidden;
		display: flex;
		/* `safe` keeps the start edge reachable when the slide overflows (SCALED
		   zoom-in) while still centring it when it fits. */
		justify-content: safe center;
		align-items: safe center;
	}
	.viewport.zoom {
		overflow: auto;
	}
	.container {
		width: var(--canvas-w);
		height: var(--canvas-h);
		/* Hold the JS-set size in the flex viewport (no shrink/grow). */
		flex: none;
		display: flex;
		flex-direction: column;
		background: var(--surface-bg, #181818);
		border: 1.5px solid var(--frame-border, #CCCCCC);
		position: relative;
	}
	.container.fit-mode {
		/* Fit the frame to the window by ASPECT, in pure CSS, so first paint is
		   already the right shape — before onMount/adjustSize() runs. adjustSize()
		   still sets equivalent px inline (and tracks resize); this just owns first
		   paint. Both axes are set EXPLICITLY (not width:auto + aspect-ratio) so the
		   inner content's min-width can't inflate the frame back to canvas width. */
		width:  min(calc(100vw - 10px), calc((100vh - 10px) * var(--aspect)));
		height: min(calc(100vh - 10px), calc((100vw - 10px) / var(--aspect)));
		/* Centre the content child so the exact-fit scale (adjustSize) letterboxes
		   symmetrically about the centre — paired with transformOrigin 'center'. */
		justify-content: center;
		align-items: center;
	}
	.content {
		/* Base font-size lever (see baseFontSize prop): every em-based size in the
		   reused components scales from here in one place. */
		font-size: var(--base-font);
		width: calc(var(--canvas-w) + 20px);
		height: calc(var(--canvas-h) - 30px);
		min-width: calc(var(--canvas-w) - 30px);
		min-height: calc(var(--canvas-h) - 30px);
		overflow: visible;
		padding: 15px;
		margin: 0px;
		display: flex;
		justify-content: center;
		align-items: center;
		color: var(--surface-fg, #C0F1FF);
		background: var(--content-bg, var(--surface-bg, #181818));
		font-family: var(--content-font, 'Noto Sans', 'Cormorant Garamond', serif);
	}
	/* Keep the content OUT OF LAYOUT until JS has applied the scale transform (the
	   `ready` class flips on at onMount, right after the first adjustSize()). At its
	   native px size the unscaled box overflows the frame; display:none removes it
	   from layout entirely — adjustSize() only measures the CONTAINER, so this is
	   safe. The container stays visible (sized in CSS), so the gap shows an empty
	   frame, never an overflowing box. */
	.content:not(.ready) {
		display: none;
	}
	.content.fill {
		/* Exact-fit: the box IS the full canvas (padding folded in via border-box),
		   so it fills the frame edge to edge on BOTH axes with no fudge. */
		box-sizing: border-box;
		width: var(--canvas-w);
		height: var(--canvas-h);
		min-width: var(--canvas-w);
		min-height: var(--canvas-h);
	}
	/* With a full-canvas fill box the chrome that normally hangs at bottom:-10 (in
	   the content's own unscaled coords) would spill past the bottom border. Nudge
	   it just inside, so it floats over the slide's bottom corners. */
	.content.fill :global(.nav),
	.content.fill :global(.copyright) {
		bottom: 20px;
	}

	/* Screen-fixed overlay for always-reachable chrome (display-mode control,
	   minimap). pointer-events:none lets clicks fall through to the slide; each
	   control re-enables them for itself. */
	.overlay {
		position: fixed;
		inset: 0;
		z-index: 50;
		pointer-events: none;
		font-size: var(--base-font);
	}
	.overlay > :global(*) {
		pointer-events: auto;
	}

	/* `?clean`: hide the in-canvas chrome so a capture shows only the slide. (The
	   overlay chrome is render-gated on !clean above.) The deck's 1.5px frame is
	   intentionally kept: it marks the canvas edge the capture is measured against. */
	.container.clean :global(.toc),
	.container.clean :global(.copyright),
	.container.clean :global(.nav) {
		display: none;
	}
</style>
