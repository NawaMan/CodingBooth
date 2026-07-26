<!-- SSR host for the prerender test: a BarChart (with a negative and a blank)
     and a LineChart (with a null → gap) rendered via svelte/server with no DOM,
     proving each chart emits its complete <svg> from props alone — the same
     guarantee a prerendered slide needs, mirroring DrawSsrHost. -->
<script lang="ts">
	import AreaChart from '../src/lib/chart/AreaChart.svelte';
	import BarChart from '../src/lib/chart/BarChart.svelte';
	import ComboChart from '../src/lib/chart/ComboChart.svelte';
	import Gantt from '../src/lib/chart/Gantt.svelte';
	import Heatmap from '../src/lib/chart/Heatmap.svelte';
	import Histogram from '../src/lib/chart/Histogram.svelte';
	import LineChart from '../src/lib/chart/LineChart.svelte';
	import PieChart from '../src/lib/chart/PieChart.svelte';
	import ScatterChart from '../src/lib/chart/ScatterChart.svelte';
	import Waterfall from '../src/lib/chart/Waterfall.svelte';

	const regions = [
		{ region: 'us-east', net: 320 },
		{ region: 'us-west', net: -140 },
		{ region: 'eu-west', net: null }, // blank → no bar
		{ region: 'sa-east', net: 480 }
	];
	const share = [
		{ region: 'apac', requests: 60 },
		{ region: 'emea', requests: 30 },
		{ region: 'latam', requests: 10 }
	];
	const samples = [
		{ month: 1, latency: 120 },
		{ month: 4, latency: 128 },
		{ month: 5, latency: null }, // blank → gap
		{ month: 6, latency: 145 }
	];
	const combo = [
		{ month: 'Jan', sessions: 4200, rate: 2.4 },
		{ month: 'Feb', sessions: 4600, rate: 2.9 },
		{ month: 'Mar', sessions: 5100, rate: 3.3 }
	];
	const cloud = [
		{ weight: 1.2, mpg: 33 },
		{ weight: 2.4, mpg: 25 },
		{ weight: null, mpg: 18 }, // blank x → dropped
		{ weight: 3.6, mpg: 16 }
	];
	// A sample to bin: explicit edges [0,10) [10,20) [20,30] so the counts (and
	// the aria-labels) are predictable in the SSR assertion. The null is dropped.
	const sample = [{ v: 2 }, { v: 5 }, { v: 12 }, { v: 24 }, { v: 30 }, { v: null }];
	// A 2×2 matrix for the heatmap: Tue × PM is absent (a blank cell), so the full
	// grid still emits four rects with predictable aria-labels.
	const load = [
		{ day: 'Mon', slot: 'AM', load: 2 },
		{ day: 'Mon', slot: 'PM', load: 8 },
		{ day: 'Tue', slot: 'AM', load: 5 }
	];
	// A plan with every kind of row: two spans (one with progress, one overlapping
	// its predecessor), a dependency chain, a milestone, and an undated row that
	// keeps its lane. ISO dates via an explicit dateFormat keep the labels stable.
	const plan = [
		{ phase: 'audit', from: '2026-03-02', to: '2026-03-16', done: 100 },
		{ phase: 'dual-write', from: '2026-03-09', to: '2026-03-27', done: 70, after: 'audit' },
		{ phase: 'cutover', from: '2026-04-20', after: 'dual-write' }, // milestone
		{ phase: 'unscheduled', from: '', to: '' } // lane only, no bar
	];
	const isoDate = (d: Date) => d.toISOString().slice(0, 10);
	// A walk with every kind of bar: rises, a fall, a blank (contributes 0 but
	// keeps its slot), a mid-walk checkpoint, and an appended closing total.
	const walk = [
		{ stage: 'tls', cost: 180 },
		{ stage: 'query', cost: 90 },
		{ stage: 'cache', cost: -35 }, // falls
		{ stage: 'mid', cost: null, check: true }, // checkpoint drawn from the baseline
		{ stage: 'middleware', cost: null }, // blank → contributes 0, keeps its slot
		{ stage: 'render', cost: 60 }
	];
</script>

<BarChart
	data={regions}
	x={{ value: 'region', type: 'band' }}
	series={{ key: 'net', label: 'Net change', value: 'net', color: '#f0a33e' }}
	title="Net change by region"
	description="bars with a zero baseline"
/>
<LineChart
	data={samples}
	x={{ value: 'month', type: 'linear', label: 'Month' }}
	series={{ key: 'latency', label: 'Latency', value: 'latency' }}
	points
	title="Latency over time"
	description="a gapped line"
/>
<ComboChart
	data={combo}
	x={{ value: 'month', type: 'band', label: 'Month' }}
	series={[
		{ key: 'sessions', label: 'Sessions', value: 'sessions', mark: 'bar', axis: 'left' },
		{ key: 'rate', label: 'Rate', value: 'rate', mark: 'line', axis: 'right' }
	]}
	title="Sessions and rate"
	description="bars plus a line on two axes"
/>
<PieChart
	data={share}
	x={{ value: 'region' }}
	series={{ key: 'requests', label: 'Requests', value: 'requests' }}
	innerRadius={0.55}
	title="Request share by region"
	description="the paired table is the accessible representation"
/>
<ScatterChart
	data={cloud}
	x={{ value: 'weight', type: 'linear', label: 'Weight' }}
	series={{ key: 'mpg', label: 'MPG', value: 'mpg' }}
	title="MPG vs weight"
	description="a dot per car; the blank weight draws none"
/>
<AreaChart
	data={samples}
	x={{ value: 'month', type: 'linear', label: 'Month' }}
	series={{ key: 'latency', label: 'Latency', value: 'latency' }}
	title="Latency area"
	description="a filled region with a zero baseline; animate is a client-only enhancement"
	animate
/>
<Histogram
	data={sample}
	value="v"
	edges={[0, 10, 20, 30]}
	title="Value distribution"
	description="a sample binned into three fixed buckets; the blank is dropped"
/>
<Heatmap
	data={load}
	x="day"
	y="slot"
	value="load"
	title="Weekly load"
	description="a 2×2 matrix; Tue × PM has no measurement and is drawn empty"
/>
<Gantt
	data={plan}
	task="phase"
	start="from"
	end="to"
	progress="done"
	dependsOn="after"
	today="2026-03-20"
	dateFormat={isoDate}
	xLabel="2026"
	title="Migration plan"
	description="spans, a milestone, dependency arrows and a today rule; animate and the tooltip are client-only"
	animate
/>
<Waterfall
	data={walk}
	x={{ value: 'stage', type: 'band', label: 'Stage' }}
	value="cost"
	isTotal="check"
	endTotal
	label="Cost"
	title="Where the time goes"
	description="a running total per stage; animate and the tooltip are client-only"
	animate
/>
