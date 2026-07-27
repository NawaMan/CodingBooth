<!--
  SpriteStudio — a drop-anywhere authoring surface for a flying HTML element,
  built entirely on the unified Draw + Sprite path.

  It replaces the retired <KeyframeStudio/> (now deleted): the same "drop one
  component, get the whole authoring loop" ergonomics, and the SAME stop data
  ({ pct, x, y, w, h, rot, ease }) — but the motion is pure CSS @keyframes (so it
  PRERENDERS and needs no JS at runtime), and it is edited by the shared Draw
  toolbar, including the numeric L/T/W/H/R fields, instead of a bespoke WAAPI
  panel.

  Drop-in shape (the one KeyframeStudio used, so old call-sites port verbatim):

      <SpriteStudio name="fly" initialStops={stops} duration={2.5} fontScale={0.84}>🚀</SpriteStudio>

  Under the hood it is nothing more than a <Sprite> inside a decorative <Draw>,
  driven by a bundled <AnimationBar> — i.e. exactly what slides 5–7 do by hand,
  packaged so it can sit on any slide with no <Draw>/<AnimationBar> wiring.

  Prop notes vs KeyframeStudio: `initialStops`→ the Sprite's `stops`,
  `duration`→ `animate`. There is no separate overall `easing` prop — segment
  easing lives per-stop (`ease`), which is part of the @keyframes and copied.
-->
<script lang="ts">
	import type { Snippet } from 'svelte';
	import AnimationBar from '$lib/components/AnimationBar.svelte';
	import Draw from '$lib/draw/Draw.svelte';
	import Sprite from '$lib/draw/Sprite.svelte';
	import type { SpriteStop } from '$lib/draw/types';

	interface Props {
		/** Editing-toolbar title + localStorage key; also the Sprite's name. */
		name?: string;
		/** The flight: one box pose per percent (same shape KeyframeStudio used). */
		initialStops: SpriteStop[];
		/** Seconds for one pass through the stops. */
		duration?: number;
		/** Grow a glyph's font-size with its box (e.g. 0.84). null = no font track. */
		fontScale?: number | null;
		/** CSS transform-origin for the per-stop rotate track. */
		origin?: string;
		/** Make the bundled AnimationBar's ANIMATE button prominent. */
		highlight?: boolean;
		children?: Snippet;
	}

	let {
		name = '',
		initialStops,
		duration = 2.5,
		fontScale = null,
		origin = '50% 50%',
		highlight = false,
		children
	}: Props = $props();
</script>

<!-- A decorative surface (aria-hidden, no title needed): the flying element is
     the content, not a diagram. Same canvas coordinates as a bare <Block>. -->
<Draw decorative {name}>
	<Sprite {name} stops={initialStops} animate={duration} {fontScale} {origin}>
		{@render children?.()}
	</Sprite>
</Draw>

<!-- Bundled control, so SpriteStudio is drop-anywhere like KeyframeStudio. -->
<AnimationBar {highlight} />
