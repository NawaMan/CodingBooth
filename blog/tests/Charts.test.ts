import { fireEvent, render } from '@testing-library/svelte';
import { describe, expect, it } from 'vitest';
import AreaChart from '../src/lib/chart/AreaChart.svelte';
import BarChart from '../src/lib/chart/BarChart.svelte';
import ComboChart from '../src/lib/chart/ComboChart.svelte';
import Heatmap from '../src/lib/chart/Heatmap.svelte';
import Histogram from '../src/lib/chart/Histogram.svelte';
import LineChart from '../src/lib/chart/LineChart.svelte';
import PieChart from '../src/lib/chart/PieChart.svelte';
import ScatterChart from '../src/lib/chart/ScatterChart.svelte';
import ScatterTooltipHost from './ScatterTooltipHost.svelte';
import type { AxisDef, SeriesDef } from '../src/lib/chart/types';

// Structure-only smoke tests (no pixels): bar/rect counts, gap in the line
// path, tick labels, zero-line presence. The pure geometry is covered
// exhaustively in chartCore.test.ts; these prove the components wire it up.

type Region = { region: string; net: number | null };
const regions: Region[] = [
	{ region: 'us-east', net: 320 },
	{ region: 'us-west', net: -140 }, // negative → below the zero line
	{ region: 'eu-west', net: null }, // blank → no bar
	{ region: 'sa-east', net: 480 }
];
// AxisDef/SeriesDef<any> — testing-library's render() can't infer the generic.
const regionX: AxisDef = { value: 'region', type: 'band' };
const netSeries: SeriesDef = { key: 'net', label: 'Net change', value: 'net' };

type Sample = { month: number; latency: number | null };
const samples: Sample[] = [
	{ month: 1, latency: 120 },
	{ month: 4, latency: 128 }, // uneven x
	{ month: 5, latency: null }, // blank → gap
	{ month: 6, latency: 145 }
];
const monthX: AxisDef = { value: 'month', type: 'linear', label: 'Month' };
const latencySeries: SeriesDef = { key: 'latency', label: 'Latency', value: 'latency' };

describe('BarChart', () => {
	it('draws one bar per non-blank row (the blank draws none)', () => {
		const { container } = render(BarChart, {
			props: { data: regions, x: regionX, series: netSeries, title: 'Net by region' }
		});
		const bars = container.querySelectorAll('.bars rect');
		expect(bars).toHaveLength(3); // eu-west (null) omitted
	});

	it('is an accessible image with a title and per-bar aria-labels', () => {
		const { container } = render(BarChart, {
			props: {
				data: regions,
				x: regionX,
				series: netSeries,
				title: 'Net by region',
				description: 'net change per region'
			}
		});
		const svg = container.querySelector('svg')!;
		expect(svg.getAttribute('role')).toBe('img');
		expect(container.querySelector('title')?.textContent).toBe('Net by region');
		expect(container.querySelector('desc')?.textContent).toBe('net change per region');
		const labels = Array.from(container.querySelectorAll('.bars rect')).map((r) =>
			r.getAttribute('aria-label')
		);
		expect(labels).toContain('us-east: 320');
		expect(labels).toContain('us-west: -140');
	});

	it('renders a zero baseline and includes 0 among the y ticks', () => {
		const { container } = render(BarChart, {
			props: { data: regions, x: regionX, series: netSeries, title: 'Net by region' }
		});
		expect(container.querySelector('.zero-line')).not.toBeNull();
		const tickTexts = Array.from(container.querySelectorAll('.ticks .tick-label')).map(
			(t) => t.textContent
		);
		expect(tickTexts).toContain('0');
	});

	it('forces zero into the domain even when all values are positive', () => {
		const { container } = render(BarChart, {
			props: {
				data: [
					{ region: 'a', net: 500 },
					{ region: 'b', net: 900 }
				],
				x: regionX,
				series: netSeries,
				title: 'All positive'
			}
		});
		const tickTexts = Array.from(container.querySelectorAll('.ticks .tick-label')).map(
			(t) => t.textContent
		);
		expect(tickTexts).toContain('0');
	});
});

describe('BarChart — multi-series', () => {
	type Row = { region: string; a: number | null; b: number };
	const rows: Row[] = [
		{ region: 'us', a: 10, b: 20 },
		{ region: 'eu', a: null, b: 15 } // blank in series a
	];
	const two: SeriesDef[] = [
		{ key: 'a', label: 'Alpha', value: 'a' },
		{ key: 'b', label: 'Beta', value: 'b' }
	];

	it('grouped: draws one rect per (series × non-blank value)', () => {
		const { container } = render(BarChart, {
			props: { data: rows, x: regionX, series: two, title: 'Grouped' }
		});
		// us: a + b = 2 rects; eu: a is blank so only b = 1 rect → 3 total
		expect(container.querySelectorAll('.bars rect')).toHaveLength(3);
	});

	it('grouped: distinct series colors and disambiguated aria-labels', () => {
		const { container } = render(BarChart, {
			props: { data: rows, x: regionX, series: two, title: 'Grouped' }
		});
		const labels = Array.from(container.querySelectorAll('.bars rect')).map((r) =>
			r.getAttribute('aria-label')
		);
		expect(labels).toContain('us — Alpha: 10');
		expect(labels).toContain('us — Beta: 20');
		const fills = new Set(
			Array.from(container.querySelectorAll('.bars rect')).map((r) => r.getAttribute('fill'))
		);
		expect(fills.size).toBeGreaterThan(1); // series don't share one color
	});

	it('stacked: full-width bars whose segment tops equal the running totals', () => {
		const { container } = render(BarChart, {
			props: { data: rows, x: regionX, series: two, stacked: true, title: 'Stacked' }
		});
		const rects = Array.from(container.querySelectorAll('.bars rect'));
		// us: a(10)+b(15 is eu)… us has a=10,b=20 → 2 segments; eu: a blank(0, no rect)+b=15 → 1 → 3
		expect(rects).toHaveLength(3);
		// the two us segments share the same x and width (one stacked column)
		const us = rects.filter((r) => r.getAttribute('aria-label')?.startsWith('us'));
		expect(us).toHaveLength(2);
		expect(us[0].getAttribute('x')).toBe(us[1].getAttribute('x'));
		expect(us[0].getAttribute('width')).toBe(us[1].getAttribute('width'));
	});

	it('stacked: a blank contributes no rect and does not corrupt the stack', () => {
		const { container } = render(BarChart, {
			props: { data: rows, x: regionX, series: two, stacked: true, title: 'Stacked' }
		});
		const labels = Array.from(container.querySelectorAll('.bars rect')).map((r) =>
			r.getAttribute('aria-label')
		);
		expect(labels).not.toContain('eu — Alpha: 0'); // blank drew nothing
		expect(labels).toContain('eu — Beta: 15');
	});
});

describe('LineChart', () => {
	it('breaks the line into two sub-paths across a blank (a gap, not a dip to 0)', () => {
		const { container } = render(LineChart, {
			props: { data: samples, x: monthX, series: latencySeries, title: 'Latency' }
		});
		const d = container.querySelector('path.line')!.getAttribute('d')!;
		expect(d.match(/M/g)).toHaveLength(2); // two moves = one gap
		expect(d).not.toContain('L 0'); // never routes through y=0
	});

	it('draws a dot only at each finite point when points is set', () => {
		const { container } = render(LineChart, {
			props: { data: samples, x: monthX, series: latencySeries, title: 'Latency', points: true }
		});
		// 4 samples, one is blank → 3 finite dots
		expect(container.querySelectorAll('.dots circle')).toHaveLength(3);
	});

	it('renders the x-axis label', () => {
		const { container } = render(LineChart, {
			props: { data: samples, x: monthX, series: latencySeries, title: 'Latency' }
		});
		const labels = Array.from(container.querySelectorAll('.axis-label')).map((t) => t.textContent);
		expect(labels).toContain('Month');
	});

	it('draws one <path> per series with distinct colors and aria-labels', () => {
		type Row = { month: number; req: number; cost: number };
		const rows: Row[] = [
			{ month: 1, req: 100, cost: 4 },
			{ month: 2, req: 200, cost: 9 }
		];
		const two: SeriesDef[] = [
			{ key: 'req', label: 'Requests', value: 'req' },
			{ key: 'cost', label: 'Cost', value: 'cost' }
		];
		const { container } = render(LineChart, {
			props: { data: rows, x: monthX, series: two, title: 'Two series' }
		});
		const paths = Array.from(container.querySelectorAll('path.line'));
		expect(paths).toHaveLength(2);
		const labels = paths.map((p) => p.getAttribute('aria-label'));
		expect(labels).toEqual(['Requests', 'Cost']);
		const strokes = new Set(paths.map((p) => p.getAttribute('stroke')));
		expect(strokes.size).toBe(2);
	});
});

describe('ChartLegend / visibility', () => {
	type Row = { month: number; big: number; small: number };
	const rows: Row[] = [
		{ month: 1, big: 1000, small: 10 },
		{ month: 2, big: 2000, small: 20 }
	];
	const two: SeriesDef[] = [
		{ key: 'big', label: 'Big', value: 'big' },
		{ key: 'small', label: 'Small', value: 'small' }
	];
	const monthX: AxisDef = { value: 'month', type: 'linear' };

	it('renders a button per series, aria-pressed=true while shown', () => {
		const { container } = render(LineChart, {
			props: { data: rows, x: monthX, series: two, legend: true, title: 'Legend' }
		});
		const buttons = Array.from(container.querySelectorAll('.legend button'));
		expect(buttons.map((b) => b.textContent?.trim())).toEqual(['Big', 'Small']);
		expect(buttons.every((b) => b.getAttribute('aria-pressed') === 'true')).toBe(true);
	});

	it('clicking a legend button hides that series and toggles aria-pressed', async () => {
		const { container } = render(LineChart, {
			props: { data: rows, x: monthX, series: two, legend: true, title: 'Legend' }
		});
		expect(container.querySelectorAll('path.line')).toHaveLength(2);
		const bigBtn = Array.from(container.querySelectorAll('.legend button')).find(
			(b) => b.textContent?.trim() === 'Big'
		)!;
		await fireEvent.click(bigBtn);
		expect(container.querySelectorAll('path.line')).toHaveLength(1); // Big line gone
		expect(bigBtn.getAttribute('aria-pressed')).toBe('false');
	});

	it('hiding the larger series re-fits the y axis to the smaller (acceptance)', async () => {
		const { container } = render(LineChart, {
			props: { data: rows, x: monthX, series: two, legend: true, title: 'Legend' }
		});
		const yTicks = () =>
			Array.from(container.querySelectorAll('.ticks .tick-label')).map((t) => t.textContent);
		expect(yTicks()).toContain('2,000'); // domain reaches the big series
		const bigBtn = Array.from(container.querySelectorAll('.legend button')).find(
			(b) => b.textContent?.trim() === 'Big'
		)!;
		await fireEvent.click(bigBtn);
		const after = yTicks();
		expect(after).not.toContain('2,000'); // re-scaled down…
		expect(after).toContain('20'); // …to fit the small series
	});

	it('BarChart: hiding a grouped series drops its rects', async () => {
		const { container } = render(BarChart, {
			props: {
				data: [{ region: 'us', big: 1000, small: 10 }],
				x: { value: 'region', type: 'band' } as AxisDef,
				series: two,
				legend: true,
				title: 'Legend'
			}
		});
		expect(container.querySelectorAll('.bars rect')).toHaveLength(2);
		const smallBtn = Array.from(container.querySelectorAll('.legend button')).find(
			(b) => b.textContent?.trim() === 'Small'
		)!;
		await fireEvent.click(smallBtn);
		expect(container.querySelectorAll('.bars rect')).toHaveLength(1);
	});
});

describe('ComboChart', () => {
	type Row = { region: string; vol: number | null; rate: number };
	const rows: Row[] = [
		{ region: 'us', vol: 320, rate: 4.1 },
		{ region: 'eu', vol: 260, rate: 3.2 },
		{ region: 'ap', vol: null, rate: 2.8 } // blank bar, line continues
	];
	const regionX: AxisDef = { value: 'region', type: 'band', label: 'Region' };
	const twoDefault: SeriesDef[] = [
		{ key: 'vol', label: 'Volume', value: 'vol' },
		{ key: 'rate', label: 'Rate', value: 'rate' }
	];

	it('defaults the first series to bars/left and the rest to a line/right', () => {
		const { container } = render(ComboChart, {
			props: { data: rows, x: regionX, series: twoDefault, title: 'Combo' }
		});
		// bars: one rect per non-blank vol row (ap is blank → 2 rects)
		expect(container.querySelectorAll('.bars rect')).toHaveLength(2);
		// line: exactly one path for the rate series
		expect(container.querySelectorAll('path.line')).toHaveLength(1);
		// both a left (Volume) and right (Rate) axis label
		const axisLabels = Array.from(container.querySelectorAll('.axis-label')).map(
			(t) => t.textContent
		);
		expect(axisLabels).toContain('Volume');
		expect(axisLabels).toContain('Rate');
	});

	it('honors explicit per-series mark / axis', () => {
		const explicit: SeriesDef[] = [
			{ key: 'vol', label: 'Volume', value: 'vol', mark: 'line', axis: 'left' },
			{ key: 'rate', label: 'Rate', value: 'rate', mark: 'bar', axis: 'right' }
		];
		const { container } = render(ComboChart, {
			props: { data: rows, x: regionX, series: explicit, title: 'Combo' }
		});
		// vol is now the line (3 finite points), rate the bars (3 rects)
		expect(container.querySelectorAll('path.line')).toHaveLength(1);
		expect(container.querySelectorAll('.bars rect')).toHaveLength(3);
	});

	it('gives the line series a shape-based legend chip (not just color)', () => {
		const { container } = render(ComboChart, {
			props: { data: rows, x: regionX, series: twoDefault, legend: true, title: 'Combo' }
		});
		// the line series gets a .line chip; the bar series a plain square swatch
		expect(container.querySelector('.legend .swatch.line')).not.toBeNull();
		expect(container.querySelector('.legend .swatch:not(.line)')).not.toBeNull();
	});

	it('stacks two bar series on one axis when stacked', () => {
		type S = { region: string; a: number; b: number };
		const sr: S[] = [{ region: 'us', a: 10, b: 20 }];
		const barsTwo: SeriesDef[] = [
			{ key: 'a', label: 'A', value: 'a', mark: 'bar', axis: 'left' },
			{ key: 'b', label: 'B', value: 'b', mark: 'bar', axis: 'left' }
		];
		const { container } = render(ComboChart, {
			props: { data: sr, x: regionX, series: barsTwo, stacked: true, title: 'Stacked combo' }
		});
		const rects = Array.from(container.querySelectorAll('.bars rect'));
		expect(rects).toHaveLength(2);
		// stacked → both segments share the same x and width (one column)
		expect(rects[0].getAttribute('x')).toBe(rects[1].getAttribute('x'));
		expect(rects[0].getAttribute('width')).toBe(rects[1].getAttribute('width'));
	});

	it('drops a hidden series from its marks', async () => {
		const { container } = render(ComboChart, {
			props: {
				data: rows,
				x: regionX,
				series: twoDefault,
				legend: true,
				title: 'Combo',
				hidden: new Set(['rate'])
			}
		});
		expect(container.querySelectorAll('path.line')).toHaveLength(0); // rate line hidden
		expect(container.querySelectorAll('.bars rect')).toHaveLength(2); // vol bars remain
	});
});

describe('Dual-axis LineChart', () => {
	type Row = { month: number; requests: number; cost: number };
	const rows: Row[] = [
		{ month: 1, requests: 412000, cost: 118 },
		{ month: 2, requests: 1930000, cost: 501 }
	];
	const two: SeriesDef[] = [
		{
			key: 'requests',
			label: 'Requests',
			value: 'requests',
			format: (v) => v.toLocaleString('en-US')
		},
		{ key: 'cost', label: 'Cost', value: 'cost', format: (v) => `$${v}` }
	];
	const monthX: AxisDef = { value: 'month', type: 'linear' };

	it('renders three axes — bottom, left, and right — when dualAxis is set', () => {
		const { container } = render(LineChart, {
			props: { data: rows, x: monthX, series: two, dualAxis: true, title: 'Dual' }
		});
		// Two vertical axes means two sets of vertical axis labels (left + right).
		const axisLabels = Array.from(container.querySelectorAll('.axis-label')).map(
			(t) => t.textContent
		);
		expect(axisLabels).toContain('Requests'); // left
		expect(axisLabels).toContain('Cost'); // right
	});

	it('scales each series to its own axis, so the small line is not pinned flat', () => {
		const { container } = render(LineChart, {
			props: { data: rows, x: monthX, series: two, dualAxis: true, title: 'Dual' }
		});
		// Each line spans a real vertical range on its own axis: the cost line's two
		// points differ in y just as much as requests', instead of both hugging 0.
		const [reqPath, costPath] = Array.from(container.querySelectorAll('path.line')).map(
			(p) => p.getAttribute('d') ?? ''
		);
		const ys = (d: string) => [...d.matchAll(/[ML] [\d.]+ ([\d.]+)/g)].map((m) => parseFloat(m[1]));
		const span = (d: string) => Math.max(...ys(d)) - Math.min(...ys(d));
		expect(span(reqPath)).toBeGreaterThan(50);
		expect(span(costPath)).toBeGreaterThan(50); // would be ~0 on a shared axis
	});

	it('tints each y-axis to match its series color', () => {
		const { container } = render(LineChart, {
			props: { data: rows, x: monthX, series: two, dualAxis: true, title: 'Dual' }
		});
		expect(container.querySelectorAll('.axis.tinted').length).toBe(2);
	});

	it('ignores dualAxis unless there are exactly two series', () => {
		const { container } = render(LineChart, {
			props: {
				data: [{ month: 1, requests: 1, cost: 2 }],
				x: monthX,
				series: [two[0]], // one series
				dualAxis: true,
				title: 'Solo'
			}
		});
		expect(container.querySelectorAll('.axis.tinted').length).toBe(0); // no dual tint
	});
});

describe('Time x-axis', () => {
	it('labels a multi-year time axis with years, no NaN coordinates', () => {
		type Row = { at: Date; v: number };
		const rows: Row[] = [
			{ at: new Date(2021, 0, 1), v: 10 },
			{ at: new Date(2022, 6, 1), v: 30 },
			{ at: new Date(2024, 0, 1), v: 20 }
		];
		const timeX: AxisDef = { value: 'at', type: 'time', label: 'Date' };
		const s: SeriesDef = { key: 'v', label: 'V', value: 'v' };
		const { container } = render(LineChart, {
			props: { data: rows, x: timeX, series: s, title: 'Over time' }
		});
		const tickTexts = Array.from(container.querySelectorAll('.ticks .tick-label')).map(
			(t) => t.textContent ?? ''
		);
		// year labels present on the x axis…
		expect(tickTexts.some((t) => /^\d{4}$/.test(t))).toBe(true);
		// …and the line path carries no NaN from date coercion.
		const d = container.querySelector('path.line')!.getAttribute('d')!;
		expect(d).not.toContain('NaN');
		expect(d).toContain('M');
	});

	it('honors AxisDef.format (given a Date) over the default time labels', () => {
		type Row = { at: Date; v: number };
		const rows: Row[] = [
			{ at: new Date(2024, 0, 1), v: 10 },
			{ at: new Date(2024, 6, 1), v: 20 }
		];
		const timeX: AxisDef = {
			value: 'at',
			type: 'time',
			format: (v) => `Y${(v as Date).getFullYear()}`
		};
		const s: SeriesDef = { key: 'v', label: 'V', value: 'v' };
		const { container } = render(LineChart, {
			props: { data: rows, x: timeX, series: s, title: 'Custom fmt' }
		});
		const tickTexts = Array.from(container.querySelectorAll('.ticks .tick-label')).map(
			(t) => t.textContent ?? ''
		);
		expect(tickTexts.some((t) => t.startsWith('Y2024'))).toBe(true);
	});
});

describe('Hover tooltip', () => {
	// jsdom's getBoundingClientRect is all-zero, so stub it to the logical box to
	// make the pointer→logical mapping (and thus which x is nearest) deterministic.
	const stubRect = (svg: Element) => {
		(svg as SVGSVGElement).getBoundingClientRect = () =>
			({
				left: 0,
				top: 0,
				width: 640,
				height: 400,
				right: 640,
				bottom: 400,
				x: 0,
				y: 0
			}) as DOMRect;
	};

	type Row = { month: number; req: number; cost: number };
	const rows: Row[] = [
		{ month: 1, req: 1253153, cost: 501.26 },
		{ month: 2, req: 900000, cost: 300 }
	];
	const two: SeriesDef[] = [
		{ key: 'req', label: 'Requests', value: 'req', format: (v) => v.toLocaleString('en-US') },
		{ key: 'cost', label: 'Cost', value: 'cost', format: (v) => `$${v.toFixed(2)}` }
	];
	const monthX: AxisDef = { value: 'month', type: 'linear' };

	it('renders nothing until a pointer moves, then one formatted entry per series', async () => {
		const { container } = render(LineChart, {
			props: { data: rows, x: monthX, series: two, title: 'Tip' }
		});
		expect(container.querySelector('.tooltip')).toBeNull(); // no hover yet
		expect(container.querySelector('.guide')).toBeNull();

		const svg = container.querySelector('svg')!;
		stubRect(svg);
		// clientX near the left edge → nearest to month 1.
		await fireEvent.pointerMove(svg, { clientX: 55, clientY: 100 });

		const tip = container.querySelector('.tooltip')!;
		expect(tip).not.toBeNull();
		expect(tip.textContent).toContain('1,253,153'); // Requests, formatted
		expect(tip.textContent).toContain('$501.26'); // Cost, formatted
		expect(container.querySelector('.guide')).not.toBeNull(); // vertical guide shown
	});

	it('hides again on pointer leave', async () => {
		const { container } = render(LineChart, {
			props: { data: rows, x: monthX, series: two, title: 'Tip' }
		});
		const svg = container.querySelector('svg')!;
		stubRect(svg);
		await fireEvent.pointerMove(svg, { clientX: 55, clientY: 100 });
		expect(container.querySelector('.tooltip')).not.toBeNull();
		await fireEvent.pointerLeave(svg);
		expect(container.querySelector('.tooltip')).toBeNull();
	});

	it('omits a hidden series from the tooltip entries', async () => {
		const { container } = render(LineChart, {
			props: { data: rows, x: monthX, series: two, title: 'Tip', hidden: new Set(['cost']) }
		});
		const svg = container.querySelector('svg')!;
		stubRect(svg);
		await fireEvent.pointerMove(svg, { clientX: 55, clientY: 100 });
		const tip = container.querySelector('.tooltip')!;
		expect(tip.textContent).toContain('Requests');
		expect(tip.textContent).not.toContain('Cost'); // hidden series excluded
	});
});

describe('PieChart', () => {
	type Region = { region: string; requests: number | null };
	// shares: 40/30/20/8/2 = 100%. The 2% slice is below the 4% label threshold.
	const regions: Region[] = [
		{ region: 'us-east', requests: 40 },
		{ region: 'us-west', requests: 30 },
		{ region: 'eu', requests: 20 },
		{ region: 'ap', requests: 8 },
		{ region: 'sa', requests: 2 },
		{ region: 'blank', requests: null }, // skipped — not a slice
		{ region: 'zero', requests: 0 } // skipped — a pie shows positive parts
	];
	const regionX: AxisDef = { value: 'region' };
	const reqSeries: SeriesDef = { key: 'requests', label: 'Requests', value: 'requests' };

	it('draws one slice per finite positive row (blank / zero skipped)', () => {
		const { container } = render(PieChart, {
			props: { data: regions, x: regionX, series: reqSeries, title: 'Share' }
		});
		expect(container.querySelectorAll('.slices .slice')).toHaveLength(5);
	});

	it('per-slice aria-labels carry value and percentage, summing to ~100%', () => {
		const { container } = render(PieChart, {
			props: { data: regions, x: regionX, series: reqSeries, title: 'Share' }
		});
		const labels = Array.from(container.querySelectorAll('.slice')).map((s) =>
			s.getAttribute('aria-label')
		);
		expect(labels).toContain('us-east: 40 (40%)');
		expect(labels).toContain('sa: 2 (2%)');
		const pctSum = labels.reduce((sum, l) => sum + Number(l!.match(/\((\d+)%\)/)![1]), 0);
		expect(pctSum).toBeGreaterThanOrEqual(99);
		expect(pctSum).toBeLessThanOrEqual(101);
	});

	it('omits the in-slice label on a slice under minSliceLabel (legend still lists it)', () => {
		const { container } = render(PieChart, {
			props: { data: regions, x: regionX, series: reqSeries, legend: true, title: 'Share' }
		});
		const inSlice = Array.from(container.querySelectorAll('.slice-label')).map(
			(t) => t.textContent
		);
		expect(inSlice).toContain('ap'); // 8% ≥ threshold → labelled
		expect(inSlice).not.toContain('sa'); // 2% < threshold → no in-slice label
		// …but every drawable slice is in the legend
		const legend = Array.from(container.querySelectorAll('.legend .label')).map(
			(t) => t.textContent
		);
		expect(legend).toContain('sa');
		expect(legend).toHaveLength(5); // blank/zero rows aren't legend entries either
	});

	it('cuts a donut hole when innerRadius is set (ring-segment paths, two arcs each)', () => {
		const pie = render(PieChart, {
			props: { data: regions, x: regionX, series: reqSeries, title: 'Pie' }
		});
		const donut = render(PieChart, {
			props: { data: regions, x: regionX, series: reqSeries, innerRadius: 0.6, title: 'Donut' }
		});
		const arcs = (root: ParentNode) =>
			(root.querySelector('.slice')!.getAttribute('d')!.match(/A /g) ?? []).length;
		expect(arcs(pie.container)).toBe(1); // solid wedge: one arc
		expect(arcs(donut.container)).toBe(2); // ring segment: outer + inner arc
	});

	it('hiding a slice via the legend re-normalises the rest (percentages grow)', async () => {
		const { container } = render(PieChart, {
			props: { data: regions, x: regionX, series: reqSeries, legend: true, title: 'Share' }
		});
		const pctOf = (region: string) =>
			Number(
				Array.from(container.querySelectorAll('.slice'))
					.find((s) => s.getAttribute('aria-label')!.startsWith(`${region}:`))!
					.getAttribute('aria-label')!
					.match(/\((\d+)%\)/)![1]
			);
		expect(pctOf('us-east')).toBe(40);
		const sa = Array.from(container.querySelectorAll('.legend button')).find(
			(b) => b.textContent?.trim() === 'sa'
		)!;
		await fireEvent.click(sa); // hide the 2% slice
		expect(pctOf('us-east')).toBeGreaterThan(40); // rest re-normalised to 100%
	});
});

describe('Selection highlighting', () => {
	type Row = { id: number; region: string; v: number };
	const rows: Row[] = [
		{ id: 1, region: 'a', v: 10 },
		{ id: 2, region: 'b', v: 20 },
		{ id: 3, region: 'c', v: 30 }
	];
	const regionX: AxisDef = { value: 'region', type: 'band' };
	const vSeries: SeriesDef = { key: 'v', label: 'V', value: 'v' };

	it('BarChart: highlighted bars get .hl, the rest .dim; keyed by rowKeyAccessor', () => {
		const { container } = render(BarChart, {
			props: {
				data: rows,
				x: regionX,
				series: vSeries,
				title: 'Bars',
				rowKeyAccessor: 'id',
				highlighted: [2]
			}
		});
		const rects = Array.from(container.querySelectorAll('.bars rect'));
		const hl = rects.filter((r) => r.classList.contains('hl'));
		const dim = rects.filter((r) => r.classList.contains('dim'));
		expect(hl).toHaveLength(1);
		expect(hl[0].getAttribute('aria-label')).toBe('b: 20'); // id 2 → region b
		expect(dim).toHaveLength(2); // the other two dim
	});

	it('BarChart: an empty highlight list dims nothing (clearing un-dims everything)', () => {
		const { container } = render(BarChart, {
			props: {
				data: rows,
				x: regionX,
				series: vSeries,
				title: 'Bars',
				rowKeyAccessor: 'id',
				highlighted: []
			}
		});
		expect(container.querySelectorAll('.bars rect.dim')).toHaveLength(0);
		expect(container.querySelectorAll('.bars rect.hl')).toHaveLength(0);
	});

	it('PieChart: the selected slice is emphasised and the rest dim', () => {
		const { container } = render(PieChart, {
			props: {
				data: rows,
				x: { value: 'region' } as AxisDef,
				series: vSeries,
				title: 'Pie',
				rowKeyAccessor: 'id',
				highlighted: [3]
			}
		});
		const slices = Array.from(container.querySelectorAll('.slice'));
		expect(slices.filter((s) => s.classList.contains('hl'))).toHaveLength(1);
		expect(container.querySelector('.slice.hl')!.getAttribute('aria-label')!.startsWith('c:')).toBe(
			true
		);
		expect(slices.filter((s) => s.classList.contains('dim'))).toHaveLength(2);
	});

	it('LineChart: reveals point markers and highlights the selected one', () => {
		const { container } = render(LineChart, {
			props: {
				data: rows.map((r) => ({ ...r, x: r.id })),
				x: { value: 'x', type: 'linear' } as AxisDef,
				series: vSeries,
				title: 'Line',
				rowKeyAccessor: 'id',
				highlighted: [2]
				// note: points not set — highlighting alone reveals the dots
			}
		});
		const dots = Array.from(container.querySelectorAll('.dots circle'));
		expect(dots).toHaveLength(3); // markers shown despite points={false}
		expect(dots.filter((d) => d.classList.contains('hl'))).toHaveLength(1);
		expect(dots.filter((d) => d.classList.contains('dim'))).toHaveLength(2);
	});

	it('ignores highlighting when no rowKeyAccessor is given', () => {
		const { container } = render(BarChart, {
			props: { data: rows, x: regionX, series: vSeries, title: 'Bars', highlighted: [2] }
		});
		expect(container.querySelectorAll('.bars rect.dim')).toHaveLength(0);
		expect(container.querySelectorAll('.bars rect.hl')).toHaveLength(0);
	});
});

describe('ScatterChart', () => {
	// x/y both continuous; one point (weight=null) is a blank → no dot.
	type Obs = { size: number; weight: number | null; group: string };
	const obs: Obs[] = [
		{ size: 1, weight: 2, group: 'a' },
		{ size: 2, weight: 5, group: 'a' },
		{ size: 3, weight: null, group: 'b' }, // blank y → dropped
		{ size: 4, weight: 8, group: 'b' }
	];
	const sizeX: AxisDef = { value: 'size', type: 'linear', label: 'Size' };
	const weightY: SeriesDef = { key: 'weight', label: 'Weight', value: 'weight' };

	it('draws one dot per non-blank row (the blank y draws none)', () => {
		const { container } = render(ScatterChart, {
			props: { data: obs, x: sizeX, series: weightY, title: 'Weight vs size' }
		});
		expect(container.querySelectorAll('.dots circle')).toHaveLength(3); // null weight omitted
	});

	it('is an accessible image with a title and per-dot coordinate labels', () => {
		const { container } = render(ScatterChart, {
			props: {
				data: obs,
				x: sizeX,
				series: weightY,
				title: 'Weight vs size',
				description: 'a scatter of weight against size'
			}
		});
		const svg = container.querySelector('svg')!;
		expect(svg.getAttribute('role')).toBe('img');
		expect(container.querySelector('title')?.textContent).toBe('Weight vs size');
		expect(container.querySelector('desc')?.textContent).toBe('a scatter of weight against size');
		const labels = Array.from(container.querySelectorAll('.dots circle')).map((c) =>
			c.getAttribute('aria-label')
		);
		expect(labels).toContain('(1, 2)');
	});

	it('draws a dot per visible series across two clouds', () => {
		const two: SeriesDef[] = [
			{ key: 'weight', label: 'Weight', value: 'weight' },
			{ key: 'size', label: 'Size', value: 'size' }
		];
		const { container } = render(ScatterChart, {
			props: { data: obs, x: sizeX, series: two, title: 'Two clouds' }
		});
		// weight: 3 finite dots; size: 4 finite dots → 7 total
		expect(container.querySelectorAll('.dots circle')).toHaveLength(7);
	});

	it('sizes bubbles by area when a series carries a size accessor', () => {
		const { container } = render(ScatterChart, {
			props: {
				data: obs,
				x: sizeX,
				series: { ...weightY, size: 'size' } as SeriesDef,
				sizeRange: [4, 20],
				title: 'Bubbles'
			}
		});
		const radii = Array.from(container.querySelectorAll('.dots circle')).map((c) =>
			Number(c.getAttribute('r'))
		);
		// varied radii within the configured range (not all the default point size)
		expect(new Set(radii).size).toBeGreaterThan(1);
		expect(Math.min(...radii)).toBeGreaterThanOrEqual(4);
		expect(Math.max(...radii)).toBeLessThanOrEqual(20);
	});

	it('emphasises highlighted rows and dims the rest', () => {
		const { container } = render(ScatterChart, {
			props: {
				data: obs.map((r, i) => ({ ...r, id: i })),
				x: sizeX,
				series: weightY,
				title: 'Highlight',
				rowKeyAccessor: 'id',
				highlighted: [0]
			}
		});
		const dots = Array.from(container.querySelectorAll('.dots circle'));
		expect(dots.filter((d) => d.classList.contains('hl'))).toHaveLength(1);
		expect(dots.filter((d) => d.classList.contains('dim'))).toHaveLength(2);
	});

	it('passes the hovered source row to a custom tooltip (a field the chart never sees)', async () => {
		const { container } = render(ScatterTooltipHost);
		// jsdom's getBoundingClientRect is all-zero; stub it to the logical box so
		// the pointer→logical mapping matches the SVG's own coordinates 1:1.
		const svg = container.querySelector('svg')!;
		(svg as SVGSVGElement).getBoundingClientRect = () =>
			({
				left: 0,
				top: 0,
				width: 640,
				height: 400,
				right: 640,
				bottom: 400,
				x: 0,
				y: 0
			}) as DOMRect;

		expect(container.querySelector('.tooltip')).toBeNull(); // nothing until hover
		// Hover exactly on the 'Alpha' dot by reading its rendered centre.
		const alpha = container.querySelector('.dots circle[aria-label="(1000, 50)"]')!;
		const cx = Number(alpha.getAttribute('cx'));
		const cy = Number(alpha.getAttribute('cy'));
		// jsdom's PointerEvent drops clientX/clientY; a MouseEvent typed 'pointermove'
		// still fires onpointermove and carries the coordinates.
		await fireEvent(
			svg,
			new MouseEvent('pointermove', { clientX: cx, clientY: cy, bubbles: true })
		);

		const tip = container.querySelector('.tooltip')!;
		expect(tip).not.toBeNull();
		expect(tip.textContent).toContain('Alpha'); // row.city — only reachable via the row arg
		expect(tip.textContent).toContain('50'); // the series value, formatted
	});
});

describe('AreaChart', () => {
	it('draws a filled region with a crisp top edge over a zero baseline', () => {
		const { container } = render(AreaChart, {
			props: { data: samples, x: monthX, series: latencySeries, title: 'Latency area' }
		});
		expect(container.querySelector('path.area')?.getAttribute('d')).toMatch(/^M /);
		expect(container.querySelector('path.edge')?.getAttribute('d')).toMatch(/^M /);
		// area measures magnitude up from zero → a visible zero baseline
		expect(container.querySelector('.zero-line')).not.toBeNull();
	});

	it('gaps the region across a blank (two closed sub-polygons, no dip to 0)', () => {
		const { container } = render(AreaChart, {
			props: { data: samples, x: monthX, series: latencySeries, title: 'Latency area' }
		});
		const d = container.querySelector('path.area')!.getAttribute('d')!;
		expect(d.match(/M/g)).toHaveLength(2); // the null at month 5 splits the fill
		expect(d.match(/Z/g)).toHaveLength(2);
	});

	it('stacks into one region per series (a blank pinches to zero thickness)', () => {
		type Row = { day: number; a: number; b: number | null };
		const rows: Row[] = [
			{ day: 1, a: 10, b: 5 },
			{ day: 2, a: 12, b: null }, // blank → contributes 0, no gap
			{ day: 3, a: 9, b: 7 }
		];
		const two: SeriesDef[] = [
			{ key: 'a', label: 'A', value: 'a' },
			{ key: 'b', label: 'B', value: 'b' }
		];
		const { container } = render(AreaChart, {
			props: {
				data: rows,
				x: { value: 'day', type: 'linear' } as AxisDef,
				series: two,
				stacked: true,
				title: 'Stacked'
			}
		});
		// one filled region per series; a stacked area never gaps (single sub-path each)
		const areas = container.querySelectorAll('path.area');
		expect(areas).toHaveLength(2);
		for (const a of areas) expect(a.getAttribute('d')!.match(/M/g)).toHaveLength(1);
	});

	it('renders no reveal clip by default (animate off → static markup)', () => {
		const { container } = render(AreaChart, {
			props: { data: samples, x: monthX, series: latencySeries, title: 'Latency area' }
		});
		expect(container.querySelector('clipPath')).toBeNull();
		expect(container.querySelector('.wipe')).toBeNull();
	});
});
describe('Histogram', () => {
	type V = { v: number | null };
	const sample: V[] = [
		{ v: 2 },
		{ v: 5 },
		{ v: 12 },
		{ v: 24 },
		{ v: 30 },
		{ v: null } // blank → dropped, not counted as 0
	];

	it('draws one rect per non-empty bin, counting every finite value', () => {
		const { container } = render(Histogram, {
			props: { data: sample, value: 'v', edges: [0, 10, 20, 30], title: 'Dist' }
		});
		const bars = container.querySelectorAll('.bars rect');
		expect(bars).toHaveLength(3); // [0,10) [10,20) [20,30] all non-empty
	});

	it('labels each bar with its range and count; the blank is dropped', () => {
		const { container } = render(Histogram, {
			props: { data: sample, value: 'v', edges: [0, 10, 20, 30], title: 'Dist' }
		});
		const labels = Array.from(container.querySelectorAll('.bars rect')).map((r) =>
			r.getAttribute('aria-label')
		);
		expect(labels).toContain('0–10: 2');
		expect(labels).toContain('10–20: 1');
		expect(labels).toContain('20–30: 2'); // 30 lands in the closed final bin
	});

	it('omits an empty bin entirely (a gap, never a zero-height stub)', () => {
		// nothing in [10,20): that bin draws no rect
		const gapped: V[] = [{ v: 1 }, { v: 2 }, { v: 25 }];
		const { container } = render(Histogram, {
			props: { data: gapped, value: 'v', edges: [0, 10, 20, 30], title: 'Dist' }
		});
		expect(container.querySelectorAll('.bars rect')).toHaveLength(2);
	});

	it('is an accessible image with a title and a zero baseline', () => {
		const { container } = render(Histogram, {
			props: { data: sample, value: 'v', bins: 4, title: 'Latency', description: 'ms' }
		});
		expect(container.querySelector('svg')!.getAttribute('role')).toBe('img');
		expect(container.querySelector('title')?.textContent).toBe('Latency');
		expect(container.querySelector('desc')?.textContent).toBe('ms');
		expect(container.querySelector('.zero-line')).not.toBeNull();
	});

	it('renders no reveal clip by default (animate off → static markup)', () => {
		const { container } = render(Histogram, {
			props: { data: sample, value: 'v', title: 'Dist' }
		});
		expect(container.querySelector('clipPath')).toBeNull();
		expect(container.querySelector('.wipe')).toBeNull();
	});
});

describe('Heatmap', () => {
	type Cell = { day: string; slot: string; load: number | null };
	// 2×2 grid with Tue × PM absent → a blank cell in the full matrix.
	const load: Cell[] = [
		{ day: 'Mon', slot: 'AM', load: 2 },
		{ day: 'Mon', slot: 'PM', load: 8 },
		{ day: 'Tue', slot: 'AM', load: 5 }
	];
	const props = { data: load, x: 'day', y: 'slot', value: 'load', title: 'Load' };

	it('draws one rect per cell of the full grid (blanks included)', () => {
		const { container } = render(Heatmap, { props });
		expect(container.querySelectorAll('.cells rect')).toHaveLength(4); // 2×2
	});

	it('labels every cell; the absent combo reads "no data"', () => {
		const { container } = render(Heatmap, { props });
		const labels = Array.from(container.querySelectorAll('.cells rect')).map((r) =>
			r.getAttribute('aria-label')
		);
		expect(labels).toContain('Mon × AM: 2');
		expect(labels).toContain('Mon × PM: 8');
		expect(labels).toContain('Tue × AM: 5');
		expect(labels).toContain('Tue × PM: no data');
	});

	it('marks a blank cell empty (its own class, no color-mix fill)', () => {
		const { container } = render(Heatmap, { props });
		const empties = container.querySelectorAll('.cells rect.empty');
		expect(empties).toHaveLength(1); // only Tue × PM
		expect(empties[0].getAttribute('fill')).not.toContain('color-mix');
	});

	it('tints measured cells along the ramp via color-mix', () => {
		const { container } = render(Heatmap, { props });
		const measured = Array.from(container.querySelectorAll('.cells rect:not(.empty)'));
		expect(measured).toHaveLength(3);
		expect(measured.every((r) => (r.getAttribute('fill') ?? '').includes('color-mix'))).toBe(true);
	});

	it('is an accessible image with a title and a colour-ramp legend', () => {
		const { container } = render(Heatmap, {
			props: { ...props, description: 'requests per slot' }
		});
		expect(container.querySelector('svg')!.getAttribute('role')).toBe('img');
		expect(container.querySelector('title')?.textContent).toBe('Load');
		expect(container.querySelector('desc')?.textContent).toBe('requests per slot');
		// legend prints the scale ends (min 2 … max 8)
		const ends = Array.from(container.querySelectorAll('.legend-end')).map((e) => e.textContent);
		expect(ends).toEqual(['2', '8']);
	});

	it('prints per-cell values only when showValues is on', () => {
		const off = render(Heatmap, { props });
		expect(off.container.querySelectorAll('.cell-value')).toHaveLength(0);
		const on = render(Heatmap, { props: { ...props, showValues: true } });
		// one per MEASURED cell (blanks print nothing)
		expect(on.container.querySelectorAll('.cell-value')).toHaveLength(3);
	});

	it('renders no reveal clip by default (animate off → static markup)', () => {
		const { container } = render(Heatmap, { props });
		expect(container.querySelector('clipPath')).toBeNull();
		expect(container.querySelector('.wipe')).toBeNull();
	});
});
