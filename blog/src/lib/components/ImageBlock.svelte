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

  All other props (x/y/width/height/name/grid/aspect/canvas*/minSize) pass straight
  through to Block. `aspect` defaults to true here (lock); pass `false` for
  freeform. Dragging, snapping, Esc-to-cancel and Copy all work as on a bare Block.
-->
<script lang="ts">
	import Block from '$lib/components/Block.svelte';

	export let src: string;
	export let alt = '';
	/** How the image maps onto the panel. 'fill' stretches with the box. */
	export let fit: 'fill' | 'cover' | 'contain' = 'fill';

	// Geometry/behaviour props — forwarded verbatim to Block.
	export let x = 0;
	export let y = 0;
	export let width = 200;
	export let height = 120;
	export let name = '';
	export let grid = 1;
	/** Aspect lock — defaults to ON for images (resize keeps the panel's shape; hold
	    Alt to break it). Pass a number for an explicit ratio, or `false` for freeform. */
	export let aspect: number | boolean | null = true;
	export let canvasWidth = 1920;
	export let canvasHeight = 1080;
	export let minSize = 24;
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
	// src is an imported asset (unknown variable name at runtime), so the copied
	// snippet emits a `src={…}` placeholder for the author to fill; alt/fit carry
	// across verbatim. fit is omitted when it's the default.
	const snippetAttrs = (alt: string, fit: string) =>
		` src={…}` + (alt ? ` alt="${alt}"` : '') + (fit !== 'fill' ? ` fit="${fit}"` : '');
</script>

<Block
	{x} {y} {width} {height} {name} {grid} {aspect} {canvasWidth} {canvasHeight} {minSize} {bounds}
	{style} {id} class={klass}
	tag="ImageBlock"
	attrs={snippetAttrs(alt, fit)}
	selfClose
>
	<img {src} {alt} style="display:block; width:100%; height:100%; object-fit:{fit};" />
</Block>
