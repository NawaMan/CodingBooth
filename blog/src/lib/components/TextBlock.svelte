<!--
  TextBlock — a Block that IS a diagram box: bordered, rounded, its label centred.

      <TextBlock name="api" x={1660} y={250} width={240} height={110} grid={10}>API</TextBlock>

  is the one-line form of what every boxes-and-arrows slide used to spell out —

      <Block name="api" …><div class="node">API</div></Block>

  — plus a `.node` rule copied into the slide's own style block. The look now lives
  here, on role tokens (`--textblock-*`), so one theme reskins every node.

  It is a Block in every way that matters: `name` publishes its box for Connector /
  Spotlight, and ADJUST drags, SAVEs, deletes and copy/pastes it like any Block —
  through `tag="TextBlock"`, so the source patcher looks for `<TextBlock` (the same
  move ImageBlock makes). The label is a slot, so richer markup works too.

  All Block props (x/y/width/height/name/grid/aspect/z/bounds/canvas*/minSize/fill)
  pass straight through.
-->
<script lang="ts">
	import Block from '$lib/components/Block.svelte';

	// Geometry/behaviour props — forwarded verbatim to Block.
	export let x = 0;
	export let y = 0;
	export let width = 200;
	export let height = 120;
	export let name = '';
	export let z = 0;
	export let fill = true;
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
</script>

<Block
	{x} {y} {width} {height} {name} {z} {fill} {grid} {aspect} {canvasWidth} {canvasHeight} {bounds} {minSize}
	{style} {id} class={klass} {__file}
	tag="TextBlock"
>
	<div class="node"><slot /></div>
</Block>

<style>
	/* Block fills its content, so the node stretches to whatever shape the box is
	   dragged into. Fallbacks repeat roles.css's dark defaults, so a node renders
	   the same with neither that file nor a theme present. */
	.node {
		display: grid;
		place-items: center;
		box-sizing: border-box;
		text-align: center;
		color: var(--textblock-fg, #C0F1FF);
		background: var(--textblock-bg, #181818);
		border: var(--textblock-border-width, 2px) solid var(--textblock-border, #C0F1FF);
		border-radius: var(--textblock-radius, 10px);
		font-size: 0.9em;
		font-weight: bold;
	}
</style>
