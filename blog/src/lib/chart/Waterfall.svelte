<!--
  Waterfall — one series walked ACROSS categories as floating bars: each bar
  starts where the previous one ended, so the chart shows the arithmetic that
  gets you from a start value to an end value. The breakdown slide: "the 400ms
  request — 180 in TLS, 90 in the query, 60 rendering", or "2.1s down to 0.6s,
  and here is each win".

  This is the counterpart to BarChart's `stacked`, not a variant of it. A stack
  sums MANY series inside one category from a shared zero; a waterfall walks ONE
  series and makes the SIGN the point: bars rise or fall, and the running total
  is carried across the whole row.

    • rise / fall — a signed contribution, drawn from the running total before it
      to the running total after it. Colored by direction (--chart-rise /
      --chart-fall), because "which way did this move" is the chart's whole job.
    • total — a checkpoint that ASSERTS the running total instead of moving it:
      drawn from the zero baseline (--chart-total). Mark rows with `isTotal`,
      and/or append a closing one with `endTotal`.
    • A blank contributes 0 and keeps its slot on the axis (drawn as a flat
      marker) — the walk continues undisturbed. Same convention as stacked bars,
      the deliberate contrast with lines, where a blank gaps. See waterfallBars.
    • connectors — the horizontal step lines joining each bar's end level to the
      next bar's start, so the eye follows the running total. On by default.

  Wiring + SVG only; all math is pure in chartCore.ts, flowing through the
  chained pipeline (each stage its own $derived, never merged):

      data → waterfall bars → band-x + linear-y scales → rects/steps → SVG

  SSR-safe: the full <svg> renders from props alone — the hover tooltip and the
  draw-in wipe are client-only enhancements that emit nothing server-side.
  Accessible: role="img" with a required `title` (→ <title>), optional
  `description` (→ <desc>), and one aria-label per bar carrying both the signed
  contribution and the running total ("Query: +90 (total 270)").
  Theme via --chart-rise / --chart-fall / --chart-total and the shared --chart-*.
-->
<script lang="ts" generics="T">
	import { onMount, type Snippet } from 'svelte';
	import Axis from './Axis.svelte';
	import ChartTooltip from './ChartTooltip.svelte';
	import {
		bandScale,
		linearScale,
		nearestIndex,
		waterfallBars,
		waterfallExtent,
		type WaterfallBar
	} from './chartCore';
	import type { Accessor, AxisDef, TooltipPoint } from './types';

	interface Props {
		data: T[];
		x: AxisDef<T>;
		/** The signed contribution per row (a waterfall is inherently one series). */
		value: Accessor<T>;
		/** Name for the quantity — the y axis label and the tooltip's change row. */
		label?: string;
		/** Format for values in tick labels, tooltips and aria-labels. */
		format?: (value: number) => string;
		/** Rows whose value here reads truthy are TOTAL columns: drawn from the
		 *  baseline, asserting the running total rather than moving it. */
		isTotal?: Accessor<T>;
		/** The value the first bar starts from. Default 0. */
		start?: number;
		/** Append a closing total column after the last row. */
		endTotal?: boolean;
		/** The appended column's label. Default 'Total'. */
		endTotalLabel?: string;
		/** Draw the step lines joining each bar to the next. Default true. */
		connectors?: boolean;
		width?: number;
		height?: number;
		/** Accessible name (SVG <title>) — required. */
		title: string;
		description?: string;
		/** Play a one-off left-to-right draw-in when the chart mounts (client-only,
		 *  skipped under prefers-reduced-motion). Duration via --chart-animate-ms. */
		animate?: boolean;
		/** Override the hover tooltip body; receives (xValue, points, row). The
		 *  appended `endTotal` column has no source row, so `row` is undefined there. */
		tooltip?: Snippet<[unknown, TooltipPoint[], T | undefined]>;
	}

	let {
		data,
		x,
		value,
		label,
		format,
		isTotal,
		start = 0,
		endTotal = false,
		endTotalLabel = 'Total',
		connectors = true,
		width = 640,
		height = 400,
		title,
		description,
		animate = false,
		tooltip
	}: Props = $props();

	// The walk: pure value-space bars (y0 → y1 + the running total), from the core.
	const bars = $derived(
		waterfallBars(data, { x: x.value, value, isTotal, start, endTotal, endTotalLabel })
	);

	const margin = $derived({
		top: 18,
		right: 18,
		bottom: 40 + (x.label ? 22 : 0),
		left: 52 + (label ? 20 : 0)
	});
	const plot = $derived({
		left: margin.left,
		right: width - margin.right,
		top: margin.top,
		bottom: height - margin.bottom
	});

	const xScale = $derived(
		bandScale(
			bars.map((b) => b.category),
			[plot.left, plot.right]
		)
	);
	// zero:true keeps the baseline visible — total columns are measured from it.
	const yScale = $derived(
		linearScale(waterfallExtent(bars), [plot.bottom, plot.top], { zero: true, nice: true })
	);
	const zeroY = $derived(yScale.map(0));

	const fmt = (v: number): string =>
		format ? format(v) : Number.isFinite(v) ? v.toLocaleString('en-US') : String(v);
	// Contributions read as movements, so a rise carries its plus sign; negatives
	// already carry the minus from the number itself.
	const signed = (v: number): string => (v > 0 ? `+${fmt(v)}` : fmt(v));
	const catLabel = (cat: unknown): string => (cat === null || cat === undefined ? '' : String(cat));
	const yFormat = (v: unknown): string => fmt(Number(v));

	const fillOf = (bar: WaterfallBar): string =>
		bar.kind === 'total'
			? 'var(--chart-total, #4c78a8)'
			: bar.kind === 'fall'
				? 'var(--chart-fall, #c2543d)'
				: 'var(--chart-rise, #3f8f4f)';

	const ariaLabel = (bar: WaterfallBar): string => {
		const cat = catLabel(bar.category);
		if (bar.kind === 'total') return `${cat}: ${fmt(bar.total)} total`;
		if (bar.blank) return `${cat}: no change (total ${fmt(bar.total)})`;
		return `${cat}: ${signed(bar.value)} (total ${fmt(bar.total)})`;
	};

	interface Rect {
		key: string;
		x: number;
		y: number;
		width: number;
		height: number;
		fill: string;
		flat: boolean; // zero-thickness (a blank or a genuine no-op) → drawn as a marker
		label: string;
	}

	// A bar spans its two value levels; a zero contribution would be invisible, so
	// it gets a minimum thickness and reads as "the walk passed through here".
	const MIN_H = 2;
	const rects = $derived.by<Rect[]>(() => {
		const out: Rect[] = [];
		for (const bar of bars) {
			const bx = xScale.map(bar.category);
			if (Number.isNaN(bx)) continue;
			const top = yScale.map(bar.y1);
			const base = yScale.map(bar.y0);
			if (!Number.isFinite(top) || !Number.isFinite(base)) continue;
			const h = Math.abs(top - base);
			const flat = h < MIN_H;
			out.push({
				key: bar.key,
				x: bx,
				y: flat ? Math.min(top, base) - MIN_H / 2 : Math.min(top, base),
				width: xScale.bandwidth,
				height: flat ? MIN_H : h,
				fill: fillOf(bar),
				flat,
				label: ariaLabel(bar)
			});
		}
		return out;
	});

	interface Step {
		key: string;
		x1: number;
		x2: number;
		y: number;
	}

	// Step lines: each bar's end level carried across the gap to the next bar's
	// start. The level is the same number on both sides (the next bar's y0 IS this
	// bar's y1), so one horizontal line per adjacent pair.
	const steps = $derived.by<Step[]>(() => {
		if (!connectors) return [];
		const out: Step[] = [];
		for (let i = 0; i < bars.length - 1; i++) {
			const a = bars[i];
			const b = bars[i + 1];
			const ax = xScale.map(a.category);
			const bx = xScale.map(b.category);
			const y = yScale.map(a.y1);
			if (Number.isNaN(ax) || Number.isNaN(bx) || !Number.isFinite(y)) continue;
			out.push({ key: `${a.key}->${b.key}`, x1: ax, x2: bx + xScale.bandwidth, y });
		}
		return out;
	});

	// ── Hover tooltip (client-only enhancement) ──────────────────────────────
	// SSR-inert: `mounted` starts false, so the static SVG is byte-identical with
	// or without JS. The pointer snaps to the nearest band center via nearestIndex.
	let svgEl: SVGSVGElement | undefined = $state();
	let mounted = $state(false);
	let hoverIdx = $state<number | null>(null);

	// Draw-in reveal: a client-only left-to-right clip wipe on mount (skipped under
	// prefers-reduced-motion). Never present in SSR markup — a pure enhancement.
	let revealed = $state(false);
	let animating = $state(false);
	const clipId = `chart-waterfall-clip-${Math.random().toString(36).slice(2)}`;
	const clipActive = $derived(animate && mounted && animating);
	const PAD = 32; // clip padding so marks near the plot edge aren't cut once revealed

	onMount(() => {
		mounted = true;
		const reduce =
			typeof window !== 'undefined' &&
			window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;
		if (animate && !reduce) {
			animating = true;
			requestAnimationFrame(() => requestAnimationFrame(() => (revealed = true)));
		}
	});

	// Band center per bar, sorted ascending — the anchors nearestIndex searches.
	const anchors = $derived(
		bars
			.map((bar, i) => ({ i, px: xScale.map(bar.category) + xScale.bandwidth / 2 }))
			.filter((a) => Number.isFinite(a.px))
			.sort((a, b) => a.px - b.px)
	);

	function onMove(e: PointerEvent) {
		if (!svgEl || anchors.length === 0) return;
		const rect = svgEl.getBoundingClientRect();
		const lx = ((e.clientX - rect.left) / rect.width) * width;
		const k = nearestIndex(
			anchors.map((a) => a.px),
			lx
		);
		hoverIdx = k < 0 ? null : anchors[k].i;
	}
	function onLeave() {
		hoverIdx = null;
	}

	interface Hover {
		px: number;
		leftPct: number;
		topPct: number;
		xValue: unknown;
		xLabel: string;
		points: TooltipPoint[];
		row: T | undefined; // the appended endTotal column has no source row
	}
	const hover = $derived.by<Hover | null>(() => {
		if (!mounted || hoverIdx === null) return null;
		const bar = bars[hoverIdx];
		if (bar === undefined) return null;
		const bx = xScale.map(bar.category);
		if (Number.isNaN(bx)) return null;
		const px = bx + xScale.bandwidth / 2;

		// A total column has nothing to say about a change — just the total. Every
		// other bar shows both: what moved, and where the walk stands after it.
		const points: TooltipPoint[] =
			bar.kind === 'total'
				? [
						{
							key: 'total',
							label: 'Total',
							value: bar.total,
							formatted: fmt(bar.total),
							color: fillOf(bar)
						}
					]
				: [
						{
							key: 'change',
							label: label ?? 'Change',
							value: bar.blank ? null : bar.value,
							formatted: bar.blank ? '—' : signed(bar.value),
							color: fillOf(bar)
						},
						{
							key: 'total',
							label: 'Running total',
							value: bar.total,
							formatted: fmt(bar.total),
							color: 'var(--chart-total, #4c78a8)'
						}
					];

		const topY = Math.min(yScale.map(bar.y0), yScale.map(bar.y1));

		return {
			px,
			leftPct: (px / width) * 100,
			topPct: (Number.isFinite(topY) ? topY : (plot.top + plot.bottom) / 2) / height * 100,
			xValue: bar.category,
			xLabel: x.format ? x.format(bar.category) : catLabel(bar.category),
			points,
			// bars[] runs parallel to data[] until the appended total column.
			row: hoverIdx < data.length ? data[hoverIdx] : undefined
		};
	});
</script>

<div class="chart-root">
	<div class="plot-wrap">
		<svg
			class="chart"
			viewBox="0 0 {width} {height}"
			role="img"
			aria-label={title}
			preserveAspectRatio="xMidYMid meet"
			bind:this={svgEl}
			onpointermove={onMove}
			onpointerleave={onLeave}
		>
			<title>{title}</title>
			{#if description}<desc>{description}</desc>{/if}

			{#if clipActive}
				<clipPath id={clipId}>
					<rect
						class="wipe"
						class:run={revealed}
						x={plot.left - PAD}
						y={plot.top - PAD}
						width={plot.right - plot.left + PAD * 2}
						height={plot.bottom - plot.top + PAD * 2}
						style:transform-origin="{plot.left - PAD}px {(plot.top + plot.bottom) / 2}px"
					/>
				</clipPath>
			{/if}

			{#if hover}
				<line class="guide" x1={hover.px} y1={plot.top} x2={hover.px} y2={plot.bottom} />
			{/if}

			<Axis
				orientation="left"
				scale={yScale}
				left={plot.left}
				right={plot.right}
				top={plot.top}
				bottom={plot.bottom}
				format={yFormat}
				gridlines
				{label}
			/>

			<g class="marks" clip-path={clipActive ? `url(#${clipId})` : undefined}>
				<g class="steps">
					{#each steps as step (step.key)}
						<line class="step" x1={step.x1} y1={step.y} x2={step.x2} y2={step.y} />
					{/each}
				</g>
				<g class="bars">
					{#each rects as rect (rect.key)}
						<rect
							x={rect.x}
							y={rect.y}
							width={rect.width}
							height={rect.height}
							fill={rect.fill}
							class:flat={rect.flat}
							aria-label={rect.label}
						/>
					{/each}
				</g>
			</g>

			<!-- zero baseline: total columns rise from it, and a walk that goes
			     negative crosses it -->
			<line class="zero-line" x1={plot.left} y1={zeroY} x2={plot.right} y2={zeroY} />

			<Axis
				orientation="bottom"
				scale={xScale}
				left={plot.left}
				right={plot.right}
				top={plot.top}
				bottom={plot.bottom}
				format={x.format}
				label={x.label}
			/>
		</svg>

		{#if hover}
			<ChartTooltip
				xLabel={hover.xLabel}
				xValue={hover.xValue}
				points={hover.points}
				left={hover.leftPct}
				top={hover.topPct}
				row={hover.row}
				{tooltip}
			/>
		{/if}
	</div>
</div>

<style>
	.chart-root {
		display: block;
		width: 100%;
	}
	.plot-wrap {
		position: relative;
		width: 100%;
	}
	.chart {
		display: block;
		width: 100%;
		height: auto;
		color: var(--chart-fg, currentColor);
		font-size: var(--chart-font-size, 13px);
		font-family: inherit;
		background: var(--chart-bg, transparent);
	}
	.guide {
		stroke: var(--chart-axis, color-mix(in srgb, currentColor 55%, transparent));
		stroke-width: 1;
		stroke-dasharray: 3 3;
		pointer-events: none;
	}
	/* The step lines are connective tissue, not data — dimmer than the bars. */
	.step {
		stroke: var(--chart-step, color-mix(in srgb, currentColor 40%, transparent));
		stroke-width: 1;
		stroke-dasharray: 4 3;
	}
	/* A zero-thickness bar: keep it visible as a marker rather than a blank slot. */
	.bars rect.flat {
		opacity: 0.55;
	}
	.zero-line {
		stroke: var(--chart-axis, color-mix(in srgb, currentColor 55%, transparent));
		stroke-width: 1.25;
	}
	/* Draw-in reveal: the clip rect scales from the left edge of the plot box. */
	.wipe {
		transform-box: view-box;
		transform: scaleX(0);
	}
	.wipe.run {
		transform: scaleX(1);
		transition: transform var(--chart-animate-ms, 850ms) cubic-bezier(0.22, 1, 0.36, 1);
	}
	@media (prefers-reduced-motion: reduce) {
		.wipe {
			transform: none;
		}
	}
</style>
