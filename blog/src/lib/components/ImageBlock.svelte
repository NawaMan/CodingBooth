<!--
  ImageBlock — a Block whose content IS an image that fills the panel.

  Plain <Block><img object-fit:contain></Block> keeps the image's OWN aspect
  ratio, so resizing the panel to a new shape just letterboxes the picture. This
  wrapper sizes the image to the panel exactly, so the image takes whatever shape
  you drag the box into:

      <ImageBlock src={photo} alt="..." x={760} y={560} width={320} height={320} />

  `fit` controls how the picture maps onto the panel:
    - 'fill'    (default) the image fills the panel exactly. Aspect is LOCKED by
                default, so the panel keeps its shape and the image never skews;
                hold Alt while resizing to break the lock and reshape both.
    - 'cover'   fill the panel and crop the overflow, keeping the image's aspect.
    - 'contain' fit inside the panel and letterbox, keeping the image's aspect.

  `live` (SVG only) puts the SVG into the page inline, once the slide is in the
  browser. Through <img>, a browser renders an SVG as a static picture, so an
  animated GIF embedded in it is stuck on its first frame; inline, it plays. The
  prerendered markup stays the plain <img> (see utils/imageBlockCore.ts).

  `live="after-transition"` does the same, but waits for the view transition that
  brought the slide in to finish — so a GIF starts on the landed slide, not while a
  morph or zoom is still moving it. With no transition (opened directly, a
  full-page-load deck), it is the same as `live`.

  All other props (x/y/width/height/name/z/grid/aspect/canvas*/minSize) pass straight
  through to Block. `aspect` defaults to true here (lock); pass `false` for
  freeform. Dragging, snapping, Esc-to-cancel and Copy all work as on a bare Block.
-->
<script lang="ts">
	import { onMount } from 'svelte';
	import { browser } from '$app/environment';
	import Block from '$lib/components/Block.svelte';
	import { afterViewTransition } from '$lib/utils/deckNav';
	import { inlineSvg } from '$lib/utils/imageBlockCore';

	export let src: string;
	export let alt = '';
	/** How the image maps onto the panel. 'fill' stretches with the box. */
	export let fit: 'fill' | 'cover' | 'contain' = 'fill';
	/** SVG only: inline it in the browser, so an animated GIF inside it plays.
	    'after-transition' waits for the slide's view transition to finish first. */
	export let live: Live = false;

	// The inline SVG once fetched; '' shows the <img> (SSR, before the fetch, or on failure).
	let svg = '';
	// Guards against a slow fetch for an old src landing after a newer one.
	let wanted = '';
	// For 'after-transition': no view transition is (still) moving the slide.
	let landed = false;
	onMount(() => afterViewTransition(() => (landed = true)));
	$: on = live === 'after-transition' ? landed : live;
	$: if (browser && on) load(src, fit);
	$: if (!live) svg = '';

	async function load(url: string, how: typeof fit) {
		const key = `${url}|${how}`;
		wanted = key;
		let text = '';
		try {
			const res = await fetch(url);
			if (res.ok) text = await res.text();
		} catch {
			// Network or URL trouble: keep the <img>.
		}
		if (wanted === key) svg = inlineSvg(text, how);
	}

	// Geometry/behaviour props — forwarded verbatim to Block.
	export let x = 0;
	export let y = 0;
	export let width = 200;
	export let height = 120;
	export let name = '';
	/** Stacking order — forwarded so an authored or ADJUST-saved `z` takes effect. */
	export let z = 0;
	export let grid = 1;
	/** Aspect lock — defaults to ON for images (resize keeps the panel's shape; hold
	    Alt to break it). Pass a number for an explicit ratio, or `false` for freeform. */
	export let aspect: number | boolean | null = true;
	export let canvasWidth = 1920;
	export let canvasHeight = 1080;
	export let minSize = 24;
	/** Dev-only source stamp (see Block) — forwarded so SAVE finds this tag in the file that wrote it. */
	export let __file = '';
	export let bounds: 'canvas' | 'none' = 'canvas';

	/** Inline style for the root element, applied last so it wins. */
	export let style: string = '';
	/** DOM id for the root element. */
	export let id: string = '';
	/** Extra class(es) for the root element. NOTE: a slide's own style block is scoped, so a
	    class defined there will NOT match — use global CSS (global.css / roles.css / a
	    :global(...) block) or a utility class. See AGENTS.md. */
	let klass: string = '';
	export { klass as class };
</script>

<script context="module" lang="ts">
	import { liveAttr, type Live } from '$lib/utils/imageBlockCore';

	// src is an imported asset (unknown variable name at runtime), so the copied
	// snippet emits a `src={…}` placeholder for the author to fill; alt/fit carry
	// across verbatim. fit is omitted when it's the default, live when it's off.
	const snippetAttrs = (alt: string, fit: string, live: Live) =>
		` src={…}` + (alt ? ` alt="${alt}"` : '') + (fit !== 'fill' ? ` fit="${fit}"` : '') + liveAttr(live);
</script>

<Block
	{x} {y} {width} {height} {name} {z} {grid} {aspect} {canvasWidth} {canvasHeight} {minSize} {bounds}
	{style} {id} class={klass} {__file}
	tag="ImageBlock"
	attrs={snippetAttrs(alt, fit, live)}
	selfClose
>
	{#if svg}
		<!-- pointer-events: none, so a drag in ADJUST mode reaches the Block as it does over <img>. -->
		<div
			role="img"
			aria-label={alt || undefined}
			aria-hidden={alt ? undefined : 'true'}
			style="width:100%; height:100%; pointer-events:none;"
		>
			{@html svg}
		</div>
	{:else}
		<img {src} {alt} style="display:block; width:100%; height:100%; object-fit:{fit};" />
	{/if}
</Block>
