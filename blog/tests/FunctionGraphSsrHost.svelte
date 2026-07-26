<!-- SSR host for the function-plotting prerender test: sampleFunction() feeds a
     formula straight into LineChart, proving a math graph emits its complete
     <svg> from props alone — no new component, no DOM. Mirrors the demo slide
     src/routes/slides/function-graph.html. The tan curve is clamped near its
     poles (|y| > 8 → NaN) so linePath breaks it into gaps. -->
<script lang="ts">
	import LineChart from '../src/lib/chart/LineChart.svelte';
	import { sampleFunction } from '../src/lib/chart/chartCore';

	const TAU = Math.PI * 2;
	const domain: [number, number] = [-TAU, TAU];

	const sin = sampleFunction(Math.sin, domain, 240);
	const cos = sampleFunction(Math.cos, domain, 240);
	const waves = sin.map((p, i) => ({ x: p.x, sin: p.y, cos: cos[i].y }));

	const tan = sampleFunction(Math.tan, domain, 240).map((p) => ({
		x: p.x,
		y: Math.abs(p.y) > 8 ? NaN : p.y // clamp near ±π/2, ±3π/2 → gaps
	}));
</script>

<LineChart
	data={waves}
	x={{ value: 'x', type: 'linear', label: 'x' }}
	series={[
		{ key: 'sin', label: 'sin x', value: 'sin' },
		{ key: 'cos', label: 'cos x', value: 'cos' }
	]}
	title="sin and cos"
	description="two sampled functions on one axis"
/>
<LineChart
	data={tan}
	x={{ value: 'x', type: 'linear', label: 'x' }}
	series={{ key: 'tan', label: 'tan x', value: 'y' }}
	title="tan x"
	description="clamped near its asymptotes"
/>
