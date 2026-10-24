<!--
  SvgBlock — a Block whose content is an SVG drawn INLINE, so it takes the slide's
  colours: anything drawn in `currentColor` follows the `--svgblock-fg` role token
  (the canvas ink by default) and so every theme. An <ImageBlock> of the same file
  could not — an <img> is a sealed document the page's CSS never reaches.

  Two ways to give it the drawing:

      (a) a file, imported as text:
          import logo from './logo.svg?raw';
          <SvgBlock name="logo" svg={logo} x={…} y={…} width={…} height={…} />

      (b) shapes written in place, in the drawing's own coordinates:
          <SvgBlock name="mark" viewBox="0 0 100 100" x={…} y={…} width={…} height={…}>
              <circle cx="50" cy="50" r="40" fill="none" stroke="currentColor" />
          </SvgBlock>

  Either way the drawing fills the box through its viewBox; `fit` says how its
  proportions meet the box's — 'contain' (default, letterbox), 'cover' (crop) or
  'fill' (stretch). The markup surgery for (a) is pure: utils/svgCore.ts.

  It is a Block in every way that matters — `name` publishes an anchor, and ADJUST
  drags, SAVEs, deletes and copy/pastes it through `tag="SvgBlock"`. All Block
  props (x/y/width/height/name/z/grid/aspect/bounds/canvas*/minSize) pass through.

  The SVG is your own file, trusted like the slide's source: it is not sanitised.
-->
<script lang="ts">
	import Block from '$lib/components/Block.svelte';
	import { inlineSvg, preserveFor, type SvgFit } from '$lib/utils/svgCore';

	/** (a) SVG markup — typically `import x from './x.svg?raw'`. Wins over the slot. */
	export let svg: string = '';
	/** (b) The coordinate system of shapes written in the slot. */
	export let viewBox: string = '';
	/** How the drawing's proportions meet the box. */
	export let fit: SvgFit = 'contain';
	/** Accessible name. Set it for a meaningful drawing; leave it empty for decoration. */
	export let title: string = '';

	// Geometry/behaviour props — forwarded verbatim to Block.
	export let x = 0;
	export let y = 0;
	export let width = 200;
	export let height = 120;
	export let name = '';
	export let z = 0;
	export let grid = 1;
	export let aspect: number | boolean | null = null;
	export let canvasWidth = 1920;
	export let canvasHeight = 1080;
	export let bounds: 'canvas' | 'none' = 'canvas';
	export let minSize = 24;
	/** Dev-only source stamp (see Block) — forwarded so SAVE finds this tag in the file that wrote it. */
	export let __file = '';

	/** Inline style for the root element, applied last so it wins. */
	export let style: string = '';
	/** DOM id for the root element. */
	export let id: string = '';
	/** Extra class(es) for the root element. NOTE: a slide's own style block is scoped, so a
	    class defined there will NOT match — use global CSS (global.css / roles.css / a
	    :global(...) block) or a utility class. See AGENTS.md. */
	let klass: string = '';
	export { klass as class };

	$: inlined = svg ? inlineSvg(svg, fit) : '';
</script>

<script context="module" lang="ts">
	// The imported markup has an unknown variable name at runtime, so the copied
	// snippet emits a `svg={…}` placeholder for the author to fill, as ImageBlock
	// does for `src`. A literal viewBox / non-default fit / title carry across.
	const snippetAttrs = (svg: string, viewBox: string, fit: string, title: string) =>
		(svg ? ` svg={…}` : '') +
		(viewBox ? ` viewBox="${viewBox}"` : '') +
		(fit !== 'contain' ? ` fit="${fit}"` : '') +
		(title ? ` title="${title}"` : '');
</script>

<Block
	{x} {y} {width} {height} {name} {z} {grid} {aspect} {canvasWidth} {canvasHeight} {bounds} {minSize}
	{style} {id} class={klass} {__file}
	tag="SvgBlock"
	attrs={snippetAttrs(svg, viewBox, fit, title)}
	selfClose={!!svg}
>
	{#if svg}
		<div class="svg" role={title ? 'img' : undefined} aria-label={title || undefined} aria-hidden={title ? undefined : 'true'}>
			{@html inlined}
		</div>
	{:else}
		<svg
			class="svg"
			viewBox={viewBox || undefined}
			preserveAspectRatio={preserveFor(fit)}
			role={title ? 'img' : undefined}
			aria-label={title || undefined}
			aria-hidden={title ? undefined : 'true'}
		><slot /></svg>
	{/if}
</Block>

<style>
	/* The drawing fills the box; `currentColor` inside it is the role token. */
	.svg {
		display: block;
		width: 100%;
		height: 100%;
		color: var(--svgblock-fg, #C0F1FF);
		overflow: hidden;
	}
	.svg :global(svg) {
		display: block;
		width: 100%;
		height: 100%;
	}
</style>
