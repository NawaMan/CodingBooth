<!--
  Host for the pass-through contract on the components that CANNOT be rendered alone —
  the Draw primitives, which only exist inside a <Draw> surface (an SVG), and CarouselItem,
  which registers itself with a parent Carousel through context and throws without one.

  One component per instance, chosen by `which` — a single host keeps the probe values in
  one place and lets the test loop over these the way it loops over everything else.
-->
<script lang="ts">
	import Carousel from '$lib/components/Carousel.svelte';
	import CarouselItem from '$lib/components/CarouselItem.svelte';
	import Draw from '$lib/draw/Draw.svelte';
	import Rect from '$lib/draw/Rect.svelte';
	import Ellipse from '$lib/draw/Ellipse.svelte';
	import Line from '$lib/draw/Line.svelte';
	import Path from '$lib/draw/Path.svelte';
	import Polyline from '$lib/draw/Polyline.svelte';
	import Curve from '$lib/draw/Curve.svelte';
	import Arc from '$lib/draw/Arc.svelte';
	import Sprite from '$lib/draw/Sprite.svelte';
	import Cursor from '$lib/draw/Cursor.svelte';
	import Connector from '$lib/components/Connector.svelte';
	import Block from '$lib/components/Block.svelte';

	export let which: string;
	export let style = '';
	export let id = '';
	let klass = '';
	export { klass as class };

	const pts: Array<[number, number]> = [
		[10, 10],
		[90, 90]
	];
</script>

{#if which === 'Draw'}
	<Draw {style} {id} class={klass} />
{:else if which === 'CarouselItem'}
	<Carousel>
		<CarouselItem {style} {id} class={klass}>slide</CarouselItem>
	</Carousel>
{:else}
	<Draw>
		{#if which === 'Rect'}
			<Rect x={10} y={10} width={80} height={40} {style} {id} class={klass} />
		{:else if which === 'Ellipse'}
			<Ellipse x={10} y={10} width={80} height={40} {style} {id} class={klass} />
		{:else if which === 'Line'}
			<Line from={pts[0]} to={pts[1]} {style} {id} class={klass} />
		{:else if which === 'Path'}
			<!-- `start` + `segments`, not points — and each shape must actually RENDER for
			     the probe to mean anything: a Path with no geometry draws nothing, and the
			     assertion would pass or fail for the wrong reason. -->
			<Path start={pts[0]} segments={[{ to: pts[1] }]} {style} {id} class={klass} />
		{:else if which === 'Polyline'}
			<Polyline points={pts} {style} {id} class={klass} />
		{:else if which === 'Curve'}
			<Curve from={pts[0]} to={pts[1]} c1={[30, 5]} c2={[70, 95]} {style} {id} class={klass} />
		{:else if which === 'Arc'}
			<Arc from={pts[0]} to={pts[1]} bend={0.3} {style} {id} class={klass} />
		{:else if which === 'Sprite'}
			<!-- A Sprite is placed by its keyframe STOPS, not by a box. -->
			<Sprite
				stops={[{ pct: 0, x: 10, y: 10, w: 40, h: 40 }, { pct: 100, x: 90, y: 90, w: 40, h: 40 }]}
				animate={2}
				{style}
				{id}
				class={klass}
			>
				🚀
			</Sprite>
		{:else if which === 'Connector'}
			<!-- Connector resolves against NAMED Blocks, so it needs two to point at. It
			     renders nothing at all when an anchor is missing — which would make this
			     probe silently vacuous, so the Blocks come first (they register as their
			     instance code runs, exactly as ConnectorSsrHost documents). -->
			<Block name="api" x={0} y={0} width={100} height={50}>API</Block>
			<Block name="db" x={300} y={0} width={100} height={50}>DB</Block>
			<Connector from="api" to="db" {style} {id} class={klass} />
		{:else if which === 'Cursor'}
			<!-- Cursor renders nothing at all without a resolvable target
			     (Connector's rule too) — a literal point always has a flight. -->
			<Cursor path={[[10, 10]]} {style} {id} class={klass} />
		{/if}
	</Draw>
{/if}
