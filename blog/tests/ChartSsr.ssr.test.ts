// @vitest-environment node
//
// True server-side render of the charts (svelte/server, no DOM): the node
// environment gets vitest's SSR transform, so the components compile in server
// mode — proving each chart emits its complete SVG markup from props alone,
// which is what prerendering a slide does. (The slides deck itself gates slide
// content behind onMount in SlideDeck, so the deck's built HTML can't
// demonstrate this — this test is the prerender guarantee, mirroring
// DrawSsr.ssr.test.ts.)
import { render } from 'svelte/server';
import { describe, expect, it } from 'vitest';
import ChartSsrHost from './ChartSsrHost.svelte';

describe('Chart (SSR)', () => {
	const { body } = render(ChartSsrHost, { props: {} });

	it('renders the full BarChart SVG server-side from props alone', () => {
		expect(body).toContain('viewBox="0 0 640 400"');
		expect(body).toContain('role="img"');
		expect(body).toContain('<title>Net change by region</title>');
		expect(body).toContain('<desc>bars with a zero baseline</desc>');
		// three region bars: us-east, us-west, sa-east — eu-west is blank, no rect
		// (single-series labels are "cat: value"; the ComboChart uses "cat — series:
		// value" and the Histogram uses "x0–x1: count" — both excluded via the dashes,
		// and the Heatmap's "col × row: value" via the × )
		const regionBars = body.match(/aria-label="[^"—–×]*: -?[\d,]+"/g) ?? [];
		expect(regionBars).toHaveLength(3);
		expect(body).toContain('aria-label="us-east: 320"');
		expect(body).toContain('aria-label="us-west: -140"'); // negative bar
		expect(body).not.toContain('eu-west:'); // blank drew no bar
		expect(body).toContain('zero-line'); // visible zero baseline (scoped class)
	});

	it('renders the LineChart line as a gapped path (blank → two sub-paths)', () => {
		expect(body).toContain('<title>Latency over time</title>');
		const line = body.match(/class="line[^"]*"[^>]*d="([^"]*)"/)?.[1] ?? '';
		expect(line).not.toBe('');
		// the null at month 5 breaks the line: exactly two M sub-paths, a gap
		expect(line.match(/M/g)).toHaveLength(2);
		expect(body).toContain('<circle'); // point dots
	});

	it('renders the ComboChart bars and line server-side on two axes', () => {
		expect(body).toContain('<title>Sessions and rate</title>');
		// bar rects for the sessions series…
		expect(body).toContain('aria-label="Jan — Sessions: 4,200"');
		// …and a line path for the rate series
		expect(body).toMatch(/class="line[^"]*"[^>]*d="M /);
	});

	it('renders the PieChart (donut) slices server-side with value + percentage labels', () => {
		expect(body).toContain('<title>Request share by region</title>');
		// 60/30/10 shares → per-slice aria-labels with value and percentage
		expect(body).toContain('aria-label="apac: 60 (60%)"');
		expect(body).toContain('aria-label="latam: 10 (10%)"');
		// donut (innerRadius set) → ring-segment paths carry an inner arc (two A cmds)
		const slice = body.match(/class="slice[^"]*"[^>]*d="([^"]*)"/)?.[1] ?? '';
		expect((slice.match(/A /g) ?? []).length).toBe(2);
	});

	it('renders the ScatterChart dots server-side, dropping the blank point', () => {
		expect(body).toContain('<title>MPG vs weight</title>');
		// coordinate aria-labels "(x, y)" are unique to the scatter dots (the line's
		// dots carry none): one per non-blank row → 3 (the null weight draws none).
		const coords = body.match(/aria-label="\([^)]*\)"/g) ?? [];
		expect(coords).toHaveLength(3);
		expect(body).toContain('aria-label="(1.2, 33)"');
	});

	it('renders the AreaChart region server-side with a zero baseline and top edge', () => {
		expect(body).toContain('<title>Latency area</title>');
		// the filled region path + its crisp top edge (linePath, "M ")
		expect(body).toMatch(/class="area[^"]*"[^>]*d="M /);
		expect(body).toMatch(/class="edge[^"]*"[^>]*d="M /);
		expect(body).toContain('zero-line'); // area measures magnitude up from zero
	});

	it('renders the Histogram bars server-side, binned with per-bar aria-labels', () => {
		expect(body).toContain('<title>Value distribution</title>');
		// edges [0,10) [10,20) [20,30]: counts 2 / 1 / 2 (the null is dropped)
		expect(body).toContain('aria-label="0–10: 2"');
		expect(body).toContain('aria-label="10–20: 1"');
		expect(body).toContain('aria-label="20–30: 2"'); // 30 lands in the closed last bin
		expect(body).toContain('zero-line'); // bars grow from a visible baseline
	});

	it('renders the Heatmap cells server-side, blanks drawn empty, colour from a ramp', () => {
		expect(body).toContain('<title>Weekly load</title>');
		// the full 2×2 grid: three measured cells + one blank ("no data")
		expect(body).toContain('aria-label="Mon × AM: 2"');
		expect(body).toContain('aria-label="Mon × PM: 8"');
		expect(body).toContain('aria-label="Tue × AM: 5"');
		expect(body).toContain('aria-label="Tue × PM: no data"'); // absent combo, drawn empty
		// cell fills interpolate two theme tokens, not a raw palette hex
		expect(body).toContain('color-mix(in oklab');
		// the static colour-ramp legend renders server-side (scoped class base name)
		expect(body).toContain('legend-end');
	});

	it('renders the Gantt plan server-side: spans, a milestone, arrows, today', () => {
		expect(body).toContain('<title>Migration plan</title>');

		// two dated spans, each labelled with its dates and duration
		expect(body).toContain(
			'aria-label="audit: 2026-03-02 – 2026-03-16 (14 days), 100% complete"'
		);
		expect(body).toContain(
			'aria-label="dual-write: 2026-03-09 – 2026-03-27 (18 days), 70% complete"'
		);
		// the row with no end is a moment, not an open-ended bar
		expect(body).toContain('aria-label="cutover: 2026-04-20 (milestone)"');

		// the undated row keeps its LANE (the axis labels it) but draws no bar
		expect(body).toContain('unscheduled');
		expect(body).not.toContain('unscheduled: ');

		// span rects (the <g class="spans"> wrapper excluded by the non-'s' guard)
		const spans = body.match(/class="span[^s]/g) ?? [];
		expect(spans).toHaveLength(2);
		// progress overlays, one per span carrying progress
		const done = body.match(/class="done/g) ?? [];
		expect(done).toHaveLength(2);

		// dependency arrows: audit→dual-write, dual-write→cutover, with a marker
		const links = body.match(/class="link[^s]/g) ?? [];
		expect(links).toHaveLength(2);
		expect(body).toMatch(/<marker[^>]*id="chart-gantt-arrow-/);
		expect(body).toMatch(/marker-end="url\(#chart-gantt-arrow-/);

		// dual-write starts 03-09 but waits on audit, which ends 03-16 — a plan that
		// contradicts itself. It prerenders DASHED with its reason, not passed off as
		// an ordinary finish-to-start.
		expect(body).toContain('violated');
		expect(body).toContain('audit → dual-write: starts before its dependency ends');
		expect(body).toMatch(/marker-end="url\(#chart-gantt-arrow-warn-/);

		expect(body).toContain('class="today'); // the "you are here" rule
		expect(body).toContain('2026'); // the x axis label
	});

	it('renders the Waterfall walk server-side: rises, a fall, checkpoints, steps', () => {
		expect(body).toContain('<title>Where the time goes</title>');
		// 180 → 270 → 235 (the cache gives time back) → checkpoint → blank → 295
		expect(body).toContain('aria-label="tls: +180 (total 180)"');
		expect(body).toContain('aria-label="query: +90 (total 270)"');
		expect(body).toContain('aria-label="cache: -35 (total 235)"'); // falls
		expect(body).toContain('aria-label="mid: 235 total"'); // isTotal checkpoint
		expect(body).toContain('aria-label="middleware: no change (total 235)"'); // blank kept its slot
		expect(body).toContain('aria-label="render: +60 (total 295)"');
		expect(body).toContain('aria-label="Total: 295 total"'); // the appended endTotal

		// contributions vs checkpoints: 5 moving bars + 2 total columns
		const moves = body.match(/aria-label="[^"]*\(total [^"]*\)"/g) ?? [];
		expect(moves).toHaveLength(5);
		const totals = body.match(/aria-label="[^"]*: [\d,]+ total"/g) ?? [];
		expect(totals).toHaveLength(2);

		// one step line per adjacent pair (7 bars → 6 gaps); the <g class="steps">
		// wrapper is excluded by requiring a non-'s' character after "step"
		const steps = body.match(/class="step[^s]/g) ?? [];
		expect(steps).toHaveLength(6);

		expect(body).toContain('zero-line'); // total columns are measured from it
	});

	it('never emits NaN in any coordinate', () => {
		expect(body).not.toContain('NaN');
	});

	it('never prerenders the client-only layers (tooltip / hover guide / animate clip)', () => {
		// The interactive + animation layers mount client-side; the static SVG must
		// be complete on its own — no tooltip, hover guide, or reveal clip server-side
		// (so the prerendered chart shows finished, never mid-wipe or hidden).
		expect(body).not.toContain('class="tooltip"');
		expect(body).not.toContain('class="guide"');
		expect(body).not.toContain('<clipPath');
		expect(body).not.toContain('class="wipe"');
	});
});
