<!--
  WebSite — a live website embedded as a component, bounded to the space you give it.

  The engine behind both web embeds: WebSite fills its parent box (wrap it in a
  <Block> to place/size it in canvas pixels), while WebPage takes the whole slide
  canvas. Same iframe, same chrome, same shield — only the frame differs.

  Usage:

    <script>
      import WebSite from '$lib/components/WebSite.svelte';
      import Block   from '$lib/components/Block.svelte';
    </script>

    <Block x={120} y={260} width={760} height={520}>
      <WebSite src="https://svelte.dev" />
    </Block>

    A desktop layout shrunk to fit a small box:

    <WebSite src="https://example.com" zoom={0.5} />

  Three things a slide needs that a bare <iframe> does not:

  1. A SHIELD. An iframe swallows every click, scroll and key it is given, so on a
     slide it would eat the presenter's paging keys the moment the pointer strayed
     over it. By default the frame is inert (`pointer-events: none`) behind an
     INVISIBLE shield: the embed looks like the site, not like a site wearing a
     badge. Clicking arms it, and the next click ANYWHERE outside the component
     disarms it again — so interaction is always deliberate and always escapable
     without touching the keyboard. What tells you the shield is there is a tooltip
     on hover (plus a faint wash, and a focus ring for the keyboard).
     `interactive` starts it armed and drops the shield for good.

  2. LAZY MOUNT. `lazy` (the default) means the iframe is created only once the
     component scrolls into view, via IntersectionObserver — so rendering the
     component server-side costs NO request to a third party, and a `text`-mode page
     with many embeds loads each as the reader arrives. Until it enters view the box
     renders a placeholder carrying a plain <a href> to the site, so a reader with
     no JS still gets the link. Where IntersectionObserver is absent the frame mounts
     on `onMount` instead — degrade to eager, never blank. `lazy={false}` renders the
     iframe during SSR too.

     (Inside a SlideDeck this is belt-and-braces: the deck already withholds ALL
     slide markup until it has measured the canvas, so no slide component reaches
     the prerendered HTML. Lazy is what makes the embed cheap once it does mount,
     and what carries the fallback link in a text artifact.)

  3. ZOOM. A site laid out for a 1280px desktop looks like a phone in a 640px box.
     `zoom={0.5}` renders the frame at 2x the box's CSS size and scales it down, so
     the DESKTOP layout is what shrinks — not the site's own responsive breakpoints.

  The chrome bar also carries a live zoom (− 100% +) and a reload (⟳), both of
  which a presenter reaches without arming the frame. The buttons walk `zoomLevels`
  — a browser's own stops by default, overridable per embed:

    <WebSite src="…" zoom={0.5} zoomLevels={[0.25, 0.5, 1]} />

  Clicking the percentage snaps back to the author's `zoom`, and reload re-keys the
  iframe — the only way to refresh a cross-origin embed, since its
  `contentWindow.location` is walled off. `controls={false}` drops them both.

  Props:
    src         — the URL to embed (required).
    title       — chrome label + iframe accessible name. Default: the URL's host.
    width       — CSS width  (default '100%' — fills a Block).
    height      — CSS height (default '100%'). In normal flow (no Block, no fixed
                  parent height) `100%` collapses — pass e.g. height="540px".
    zoom        — render scale; <1 shrinks a desktop layout into a small box.
    zoomLevels  — the stops the − / + buttons walk. Default: a browser's own ladder.
    chrome      — show the fake browser bar (URL + Open ↗). Default true.
    controls    — show the bar's zoom + reload controls. Default true; needs `chrome`.
    interactive — start armed, no shield. Default false.
    lazy        — mount the iframe only once visible. Default true.
    sandbox     — iframe sandbox tokens. Default allows scripts / same-origin /
                  popups / forms, which is what most third-party sites need to run.
                  Pass '' to lock the frame down completely, or `false` to drop the
                  attribute (NO sandbox — only for content you control).
    allow       — iframe permission policy (e.g. 'fullscreen; clipboard-write').
    style       — extra inline CSS appended to the outer box.

  Slots:
    placeholder — what the box shows before the frame mounts (default: a link).

  Note: many sites refuse to be framed at all (X-Frame-Options / frame-ancestors).
  That is the site's call, not this component's — the frame renders empty and the
  chrome bar's "Open ↗" is the escape hatch. Check the target before a talk.

  In `text` mode the shield is dropped (a document is meant to be scrolled and
  clicked) and the frame is live from the start.
-->
<script lang="ts">
	import { browser } from '$app/environment';
	import { getMode } from '$lib/presentation';
	import { onDestroy, onMount } from 'svelte';

	/** Default zoom ladder — a browser's own stops, which readers already know. */
	const ZOOM_LEVELS = [0.25, 0.33, 0.5, 0.67, 0.75, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3, 4];

	/** The URL to embed. */
	export let src: string = '';
	/** Chrome label + iframe accessible name; `null` → the URL's host. */
	export let title: string | null = null;
	/** Outer box size, any CSS length. Defaults fill a Block. */
	export let width: string = '100%';
	export let height: string = '100%';
	/** Render scale: `0.5` shows a 2x-wide desktop layout at half size. */
	export let zoom: number = 1;
	/** The stops the bar's − / + buttons walk. Sorted and de-duped; the first and
	    last are the clamp. An empty or all-invalid list falls back to the default. */
	export let zoomLevels: number[] = ZOOM_LEVELS;
	/** Show the fake browser bar (URL + "Open ↗"). */
	export let chrome: boolean = true;
	/** Show the bar's zoom (− % +) and reload (⟳) controls. Needs `chrome`. */
	export let controls: boolean = true;
	/** Start armed with no shield — the frame takes pointer/keyboard immediately. */
	export let interactive: boolean = false;
	/** Mount the iframe only once the box scrolls into view. */
	export let lazy: boolean = true;
	/** Sandbox tokens; `''` locks it down, `false` drops the attribute entirely. */
	export let sandbox: string | false = 'allow-scripts allow-same-origin allow-popups allow-forms';
	/** Iframe permission policy, e.g. 'fullscreen; clipboard-write'. */
	export let allow: string = '';
	/** Extra inline CSS appended to the outer box. */
	export let style: string = '';
	/** DOM id for the root element. */
	export let id: string = '';
	/** Extra class(es) for the root element. NOTE: a slide's own style block is scoped, so a
	    class defined there will NOT match — use global CSS (global.css / roles.css / a
	    :global(...) block) or a utility class. See AGENTS.md. */
	let klass: string = '';
	export { klass as class };

	// A text artifact is one long, scrollable document: shielding an embed there
	// would be noise. A presentation slide is driven by the keyboard, so it shields.
	const isText = getMode() === 'text';

	let root: HTMLDivElement;

	// `entered` is the lazy gate: flipped by IntersectionObserver (or onMount where
	// there is none). Server-side it stays false, so a lazy embed prerenders as the
	// placeholder — no iframe, no build-time network request.
	let entered = false;
	$: visible = entered || !lazy;

	// `armed` is the shield gate. Kept separate from `interactive` so that flipping
	// the prop never strands a stale armed state.
	let armed = false;
	$: live = isText || interactive || armed;

	onMount(() => {
		if (!lazy) return;
		// No IntersectionObserver (jsdom, old browsers) → mount eagerly rather than
		// leave the reader staring at a placeholder that will never resolve.
		if (typeof IntersectionObserver === 'undefined') {
			entered = true;
			return;
		}
		const io = new IntersectionObserver(
			(entries) => {
				if (entries.some((e) => e.isIntersecting)) {
					entered = true;
					io.disconnect();
				}
			},
			{ rootMargin: '200px' }
		);
		io.observe(root);
		return () => io.disconnect();
	});

	// Disarm on the next click outside the component. A click INSIDE the iframe
	// never reaches this listener (that is the point — the site keeps the pointer);
	// a click on the surrounding slide does, and hands control back to the deck.
	// Capture phase, so a slide handler that stops propagation can't strand us armed.
	function handleOutside(event: PointerEvent) {
		if (root && !root.contains(event.target as Node)) armed = false;
	}
	$: if (browser) {
		if (armed && !interactive) window.addEventListener('pointerdown', handleOutside, true);
		else window.removeEventListener('pointerdown', handleOutside, true);
	}
	onDestroy(() => {
		if (browser) window.removeEventListener('pointerdown', handleOutside, true);
	});

	function hostOf(url: string): string {
		try {
			return new URL(url).host;
		} catch {
			return url; // relative or malformed — show it verbatim rather than nothing
		}
	}

	// RELOAD. A cross-origin frame's contentWindow.location is walled off, so there
	// is no reaching in to refresh it. Re-keying the iframe on a counter destroys
	// and recreates the element, which is a fresh fetch — the only refresh a
	// third-party embed allows. (Re-assigning the same `src` would not: the browser
	// treats it as a no-op navigation.)
	let reloads = 0;

	// ZOOM. `zoom` is the author's setting; `liveZoom` is what the viewer has done
	// to it with the bar's − / + buttons. Seeded from the prop, and re-seeded if the
	// prop itself changes — without that guard a re-render for any OTHER reason
	// would stomp the viewer's zoom back to the author's.
	let liveZoom = zoom;
	let seededFrom = zoom;
	$: if (zoom !== seededFrom) {
		seededFrom = zoom;
		liveZoom = zoom;
	}

	// The − / + buttons walk THIS ladder rather than multiplying by a step. Two
	// reasons: the author picks the stops that suit the site (a wide dashboard wants
	// coarse ones, a text page fine), and an explicit list cannot drift — repeated
	// ×1.25 / ÷1.25 lands on 0.9999… and would show "100%" while still emitting a
	// transform. Sanitised, so a hand-written list can't break the buttons.
	$: levels = (() => {
		const clean = [...new Set((zoomLevels ?? []).filter((v) => Number.isFinite(v) && v > 0))];
		clean.sort((a, b) => a - b);
		return clean.length ? clean : ZOOM_LEVELS;
	})();

	// The ladder bounds ARE the clamp: there is nowhere past either end to go.
	$: zoomMin = levels[0];
	$: zoomMax = levels[levels.length - 1];

	// Read the plain state, NOT the reactive `z`: two clicks inside one frame would
	// both see the pre-flush `z` and step to the same stop.
	const currentZoom = () => (Number.isFinite(liveZoom) && liveZoom > 0 ? liveZoom : 1);

	// Step to the nearest stop STRICTLY past the current zoom, so an author's
	// off-ladder `zoom` (say 0.6) still moves to its neighbours rather than snapping
	// to a stop it is already between.
	const zoomIn = () => {
		const at = currentZoom();
		liveZoom = levels.find((v) => v > at) ?? at;
	};
	const zoomOut = () => {
		const at = currentZoom();
		liveZoom = [...levels].reverse().find((v) => v < at) ?? at;
	};
	/** Click the percentage to snap back to whatever the slide author asked for. */
	const zoomReset = () => (liveZoom = zoom);

	$: label = title ?? hostOf(src);
	// `false` must DROP the attribute; Svelte would render the string "false".
	$: sandboxAttr = sandbox === false ? undefined : sandbox;
	$: allowAttr = allow || undefined;
	// Guard the divisor: a zero/NaN zoom would blow the frame up to Infinity.
	$: z = Number.isFinite(liveZoom) && liveZoom > 0 ? liveZoom : 1; // = currentZoom(), reactively
	$: pct = Math.round(z * 100);
	// At 1:1 skip the transform entirely — an identity scale still forces the frame
	// onto its own layer and can soften text.
	$: frameStyle =
		z === 1
			? ''
			: `width: ${100 / z}%; height: ${100 / z}%; transform: scale(${z}); transform-origin: 0 0;`;
</script>

<div
	class="website {klass}"
	class:text-mode={isText}
	class:armed={live && !interactive}
	bind:this={root}
	id={id || undefined}
	style="width: {width}; height: {height}; {style}"
>
	{#if chrome}
		<div class="bar">
			<span class="dots" aria-hidden="true"><i></i><i></i><i></i></span>
			<span class="url" title={src}>{label}</span>

			{#if controls}
				<span class="zoom">
					<button
						type="button"
						class="icon"
						title="Zoom out"
						aria-label="Zoom out"
						disabled={z <= zoomMin}
						on:click={zoomOut}>−</button
					>
					<button
						type="button"
						class="level"
						title="Reset zoom to {Math.round(zoom * 100)}%"
						on:click={zoomReset}>{pct}%</button
					>
					<button
						type="button"
						class="icon"
						title="Zoom in"
						aria-label="Zoom in"
						disabled={z >= zoomMax}
						on:click={zoomIn}>+</button
					>
				</span>
				<button
					type="button"
					class="icon"
					title="Reload the page"
					aria-label="Reload the page"
					on:click={() => (reloads += 1)}>⟳</button
				>
			{/if}

			{#if live && !interactive && !isText}
				<button type="button" class="pill" on:click={() => (armed = false)}>Release</button>
			{/if}
			<a class="pill" href={src} target="_blank" rel="noopener noreferrer">Open ↗</a>
		</div>
	{/if}

	<div class="viewport">
		{#if visible}
			<!-- Keyed on the reload counter: a bump throws the iframe away and builds a
			     new one, which is the only way to re-fetch a cross-origin embed. -->
			{#key reloads}
				<iframe
					{src}
					title={label}
					sandbox={sandboxAttr}
					allow={allowAttr}
					referrerpolicy="no-referrer"
					loading="lazy"
					class:live
					style={frameStyle}
				></iframe>
			{/key}
		{:else}
			<div class="placeholder">
				<slot name="placeholder">
					<a href={src} target="_blank" rel="noopener noreferrer">{label}</a>
				</slot>
			</div>
		{/if}

		{#if visible && !live}
			<!-- Invisible on purpose: the site should look like the site, not like a
			     site with a badge on it. The shield still covers the frame and still
			     takes the arming click; it explains itself with a tooltip on hover
			     (and, for the keyboard, its accessible name). -->
			<button
				type="button"
				class="shield"
				title="Click to interact with {label}"
				aria-label="Click to interact with {label}"
				on:click={() => (armed = true)}
			></button>
		{/if}
	</div>
</div>

<style>
	.website {
		display: flex;
		flex-direction: column;
		box-sizing: border-box;
		overflow: hidden;
		border: 1px solid color-mix(in srgb, var(--embed-frame-border, #CCCCCC) 45%, transparent);
		border-radius: 8px;
		background: var(--embed-frame-bg, #1E1E1E);
	}

	/* Armed: a soft accent ring says "this frame owns your pointer now". */
	.website.armed {
		border-color: var(--embed-accent, #2980B9);
		box-shadow: 0 0 0 2px color-mix(in srgb, var(--embed-accent, #2980B9) 35%, transparent);
	}

	.bar {
		flex: 0 0 auto;
		display: flex;
		align-items: center;
		gap: 0.6em;
		padding: 0.35em 0.6em;
		background: var(--embed-chrome-bg, #1E1E1E);
		color: var(--embed-chrome-fg, #C0F1FF);
		border-bottom: 1px solid color-mix(in srgb, var(--embed-frame-border, #CCCCCC) 30%, transparent);
		font-size: 0.6em;
		line-height: 1.6;
	}

	.dots {
		display: flex;
		gap: 0.3em;
		flex: 0 0 auto;
	}
	.dots i {
		width: 0.7em;
		height: 0.7em;
		border-radius: 50%;
		background: color-mix(in srgb, var(--embed-chrome-fg, #C0F1FF) 30%, transparent);
	}

	.url {
		flex: 1 1 auto;
		min-width: 0;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		font-family: monospace;
		opacity: 0.75;
	}

	.pill {
		flex: 0 0 auto;
		font: inherit;
		color: inherit;
		text-decoration: none;
		cursor: pointer;
		padding: 0.1em 0.6em;
		border-radius: 999px;
		border: 1px solid color-mix(in srgb, var(--embed-chrome-fg, #C0F1FF) 35%, transparent);
		background: transparent;
	}
	.pill:hover {
		background: color-mix(in srgb, var(--embed-accent, #2980B9) 30%, transparent);
	}

	/* Zoom cluster: −, the level, +. Grouped in one bordered capsule so it reads as
	   one control rather than three loose buttons next to the reload. */
	.zoom {
		flex: 0 0 auto;
		display: flex;
		align-items: stretch;
		border-radius: 999px;
		border: 1px solid color-mix(in srgb, var(--embed-chrome-fg, #C0F1FF) 35%, transparent);
		overflow: hidden;
	}

	.icon,
	.level {
		font: inherit;
		color: inherit;
		cursor: pointer;
		background: transparent;
		border: 0;
		padding: 0.1em 0.5em;
		line-height: 1.6;
	}
	.icon:hover:not(:disabled),
	.level:hover {
		background: color-mix(in srgb, var(--embed-accent, #2980B9) 30%, transparent);
	}
	.icon:disabled {
		opacity: 0.35;
		cursor: default;
	}

	/* The level doubles as the reset button, so it must be wide enough that "100%"
	   and "25%" don't shuffle the buttons either side of it as you step through. */
	.level {
		min-width: 3.6em;
		font-variant-numeric: tabular-nums;
		border-left: 1px solid color-mix(in srgb, var(--embed-chrome-fg, #C0F1FF) 20%, transparent);
		border-right: 1px solid color-mix(in srgb, var(--embed-chrome-fg, #C0F1FF) 20%, transparent);
	}

	/* The lone reload sits outside the capsule but wears the same ring. */
	.bar > .icon {
		flex: 0 0 auto;
		border: 1px solid color-mix(in srgb, var(--embed-chrome-fg, #C0F1FF) 35%, transparent);
		border-radius: 999px;
	}

	/* The clipping window. `min-height: 0` lets it shrink inside the flex column
	   instead of being floored at the iframe's default 150px content height. */
	.viewport {
		position: relative;
		flex: 1 1 auto;
		min-height: 0;
		overflow: hidden;
	}

	iframe {
		display: block;
		width: 100%;
		height: 100%;
		border: 0;
		background: #FFFFFF; /* the site's own canvas, not the deck's */
		/* Inert until armed, so the slide keeps the pointer (and the keys). */
		pointer-events: none;
	}
	iframe.live {
		pointer-events: auto;
	}

	.placeholder {
		display: flex;
		align-items: center;
		justify-content: center;
		width: 100%;
		height: 100%;
		font-size: 0.7em;
	}
	.placeholder a {
		color: var(--embed-chrome-fg, #C0F1FF);
	}

	/* Covers the frame, not the chrome bar — "Open ↗" stays clickable while inert.
	   Fully transparent at rest, so the embed reads as the site itself; the faint
	   hover wash is the only tell that the frame is not yet yours. */
	.shield {
		position: absolute;
		inset: 0;
		border: 0;
		cursor: pointer;
		background: transparent;
		font: inherit;
	}
	.shield:hover {
		background: color-mix(in srgb, var(--embed-shield-bg, #000000) 10%, transparent);
	}
	/* The tooltip never fires for a keyboard user, so give focus a visible ring. */
	.shield:focus-visible {
		outline: 2px solid var(--embed-accent, #2980B9);
		outline-offset: -2px;
	}

	/* A text artifact has no fixed canvas: give the embed a sane default shape so
	   `height: 100%` against an auto-height parent can't collapse it to nothing. */
	.text-mode {
		min-height: 320px;
	}
</style>
