<!-- SSR host for the prerender test: a full Draw surface with every shape
     (Phases 1 + 2) plus the raw-SVG escape hatch, rendered via svelte/server
     with no DOM — proves each shape emits its complete SVG from props alone,
     including labels and the CSS-only draw-on animation plumbing. -->
<script lang="ts">
	import Arc from '../src/lib/draw/Arc.svelte';
	import Curve from '../src/lib/draw/Curve.svelte';
	import Draw from '../src/lib/draw/Draw.svelte';
	import Ellipse from '../src/lib/draw/Ellipse.svelte';
	import Line from '../src/lib/draw/Line.svelte';
	import Path from '../src/lib/draw/Path.svelte';
	import Polyline from '../src/lib/draw/Polyline.svelte';
	import Rect from '../src/lib/draw/Rect.svelte';
	import Sprite from '../src/lib/draw/Sprite.svelte';
</script>

<Draw title="Request flow">
	<Line from={[510, 770]} to={[1410, 770]} arrow="end" thickness={6} />
	<Line from={[1410, 810]} to={[510, 810]} dash />
	<Curve from={[200, 200]} to={[900, 700]} c1={[500, 100]} c2={[700, 800]} arrow="end" />
	<Arc from={[400, 540]} to={[1500, 540]} bend={0.3} labelText="round trip" />
	<Polyline points={[[100, 900], [400, 700], [700, 950], [1100, 600]]} smooth draw={1.5} />
	<Path start={[200, 300]} segments={[
		{ to: [500, 300] },
		{ to: [800, 150], c1: [650, 300] },
		{ to: [1150, 150], bend: 0.5 }
	]} arrow="end" thickness={5} labelText="route" />
	<Path start={[100, 460]} segments={[{ to: [300, 460] }, { to: [500, 460] }]} animate={3} stops={[
		{ pct: 0, segments: [{ to: [300, 460] }, { to: [500, 460] }] },
		{ pct: 100, segments: [{ to: [300, 360] }, { to: [500, 360] }] }
	]} />
	<Rect x={1395} y={675} width={370} height={190} rounded={16} />
	<Ellipse x={860} y={940} width={200} height={90} />
	<Sprite name="rocket" animate={2.5} fontScale={0.84} stops={[
		{ pct: 0, x: 100, y: 800, w: 56, h: 55, rot: 20, ease: 'ease-in' },
		{ pct: 100, x: 1500, y: 430, w: 228, h: 219, rot: -45 }
	]}>ROCKET</Sprite>
	<circle cx="960" cy="770" r="10" fill="currentColor" />
</Draw>
