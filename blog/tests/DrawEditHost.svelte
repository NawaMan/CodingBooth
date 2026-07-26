<!-- Host for ADJUST-mode editing tests: a Draw surface with editable shapes.
     Grows a shape per DRAW-3 deliverable. -->
<script lang="ts">
	import Block from '../src/lib/components/Block.svelte';
	import Arc from '../src/lib/draw/Arc.svelte';
	import Curve from '../src/lib/draw/Curve.svelte';
	import Draw from '../src/lib/draw/Draw.svelte';
	import Ellipse from '../src/lib/draw/Ellipse.svelte';
	import Line from '../src/lib/draw/Line.svelte';
	import Path from '../src/lib/draw/Path.svelte';
	import Rect from '../src/lib/draw/Rect.svelte';
</script>

<!-- A plain slide-level Block, OUTSIDE the Draw — it participates in
     "Copy changed" via the page-wide registry, not Draw context. -->
<Block name="node" x={100} y={800} width={200} height={100}>
	<div>node</div>
</Block>

<Draw title="Edit host">
	<Line name="main" from={[100, 100]} to={[500, 100]} arrow="end" thickness={6} />
	<Curve name="hop" from={[100, 300]} to={[500, 300]} c1={[200, 200]} c2={[400, 200]} />
	<Arc name="loop" from={[100, 500]} to={[500, 500]} bend={0.25} />
	<Rect name="frame" x={700} y={100} width={300} height={200} rounded={12} color="#2980b9" />
	<Ellipse name="ring" x={700} y={400} width={200} height={100} />
	<Rect name="revealbox" x={1100} y={100} width={220} height={120} draw={1.5} drawDelay={0.5} />
	<Line name="beam" from={[100, 600]} to={[500, 600]} stops={[{ pct: 0, to: [500, 600] }, { pct: 100, to: [500, 400] }]} animate={2} />
	<Line name="reveal" from={[100, 700]} to={[500, 700]} draw={2} drawDelay={0.5} />
	<Curve name="progress" from={[100, 900]} to={[500, 900]} c1={[300, 800]} stops={[{ pct: 0, c1: [300, 800], drawn: 0 }, { pct: 100, c1: [300, 700], drawn: 1 }]} animate={3} />
	<Path name="route" start={[700, 700]} arrow="end" segments={[{ to: [900, 700] }, { to: [1100, 600], c1: [1000, 700] }, { to: [1300, 600], bend: 0.4 }]} />
	<Path name="morph" start={[700, 900]} segments={[{ to: [900, 900] }, { to: [1100, 900] }]} stops={[{ pct: 0, segments: [{ to: [900, 900] }, { to: [1100, 900] }] }, { pct: 100, segments: [{ to: [900, 700] }, { to: [1100, 700] }] }]} animate={2} />
</Draw>
