<!--
  WebPage — a live website filling the whole slide canvas.

  The full-bleed sibling of WebSite: same iframe engine (shield, lazy mount, zoom,
  sandbox — see WebSite.svelte for what each does), but the frame is stretched over
  the deck's fixed 1920x1080 canvas instead of a Block. Use WebSite when the site is
  ONE element on a slide; use WebPage when the site IS the slide.

  Usage — this is a complete slide:

    <script>
      import WebPage from '$lib/components/WebPage.svelte';
    </script>

    <WebPage src="https://svelte.dev" title="svelte.dev" />

  Paging still works with the site on screen: the deck's pager lives in SlideDeck's
  ControlBar (the bottom-centre chrome bar), not on this component, so a full-bleed
  site and a nested one behave the same and there is no second bar to suppress.

  Layering: the frame is absolutely positioned and carries no z-index, so it paints
  in DOM order — the deck's own chrome (ADJUST toggle, Table of Contents, speaker
  Notes) stays above it and stays clickable. The site behind them is inert anyway
  until you click the shield.

  Props: `src`, `title`, `zoom`, `zoomLevels`, `chrome`, `controls`, `interactive`,
  `lazy`, `sandbox`, `allow` all pass straight through to WebSite. Plus:
    height — text mode only: the embed's height there (a text artifact has no canvas).

  In `text` mode there is no canvas to fill, so the embed drops out of the absolute
  layer and renders as a plain, full-width block `height` tall, with no nav bar.
-->
<script lang="ts">
	import { getMode } from '$lib/presentation';
	import WebSite from '$lib/components/WebSite.svelte';

	/** The URL to embed. */
	export let src: string = '';
	/** Chrome label + iframe accessible name; `null` → the URL's host. */
	export let title: string | null = null;
	/** Render scale: `0.5` shows a 2x-wide desktop layout at half size. */
	export let zoom: number = 1;
	/** The stops the bar's − / + buttons walk. Undefined keeps WebSite's default
	    ladder (Svelte falls back to a prop's initialiser when it is passed undefined),
	    so the ladder is declared in exactly one place. */
	export let zoomLevels: number[] | undefined = undefined;
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
	/** Text mode only: how tall the embed renders where there is no canvas. */
	export let height: string = '640px';
	/** Inline style for the root element, applied last so it wins. */
	export let style: string = '';
	/** DOM id for the root element. */
	export let id: string = '';
	/** Extra class(es) for the root element. NOTE: a slide's own style block is scoped, so a
	    class defined there will NOT match — use global CSS (global.css / roles.css / a
	    :global(...) block) or a utility class. See AGENTS.md. */
	let klass: string = '';
	export { klass as class };

	const isText = getMode() === 'text';
</script>

<div class="webpage {klass}" class:text-mode={isText} id={id || undefined} style={style || undefined}>
	<WebSite
		{src}
		{title}
		{zoom}
		{zoomLevels}
		{chrome}
		{controls}
		{interactive}
		{lazy}
		{sandbox}
		{allow}
		height={isText ? height : '100%'}
	/>
</div>

<style>
	/* Absolute against the deck's .container (the only positioned ancestor), so this
	   covers the full canvas — the same coordinate space Block authors in. No
	   z-index: later siblings (nav bar, TOC, Notes) must keep painting above it. */
	.webpage {
		position: absolute;
		inset: 0;
		overflow: hidden;
	}

	/* No canvas in a text artifact — fall back into the document flow. */
	.webpage.text-mode {
		position: static;
		inset: auto;
		width: 100%;
	}
</style>
