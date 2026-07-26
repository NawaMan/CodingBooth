<!--
  Histogram — the DISTRIBUTION chart: a sample of raw numbers binned into
  contiguous buckets, bar heights = how many values fell in each bucket. The
  counterpart to BarChart (which plots one bar per pre-made category); here the
  categories ARE the bins, computed from the data.

  All the binning is pure in chartCore.ts (`histogramBins`): nice round edges via
  the axes' own `niceTicks`, a Sturges default bin count, and `bins`/`domain`/
  `edges` overrides. Blanks and non-finite values are dropped (never counted as
  0). The component only wires bins → scales → rects → SVG:

      data → values → histogramBins → linear-x (edges) + linear-y (count) → rects

  Unlike a BarChart the x scale is LINEAR and continuous, so the bars touch
  (a small `gap` separates them only visually) and the axis ticks are round
  values, not one label per bar.

  SSR-safe: the full <svg> renders from props alone (the hover tooltip + animate
  wipe are client-only, exactly as in BarChart). Accessible: role="img" with a
  required `title`, optional `description`, and one aria-label per bar
  ("12–14: 5"). Theme via --chart-*.
-->
<script lang="ts" generics="T">
	import { onMount, type Snippet } from 'svelte';
	import Axis from './Axis.svelte';
	import ChartTooltip from './ChartTooltip.svelte';
	import { histogramBins, linearScale, nearestIndex, seriesColor, toNumber, valueOf } from './chartCore';
	import type { Accessor, TooltipPoint } from './types';

	interface Props {
		data: T[];
		/** The numeric field to bin (field name or accessor). Blanks are dropped. */
		value: Accessor<T>;
		/** Desired bin count (snapped to round edges). Ignored when `edges` given. */
		bins?: number;
		/** Clamp the binned range; values outside are dropped. */
		domain?: [number, number];
		/** Explicit bin boundaries (≥2), overriding `bins`/`domain`. */
		edges?: number[];
		width?: number;
		height?: number;
		/** Accessible name (SVG <title>) — required. */
		title: string;
		description?: string;
		/** Y-axis label (the count dimension). */
		label?: string;
		/** X-axis label (the binned variable). */
		xLabel?: string;
		/** Format a bin edge for tick + aria/tooltip text. */
		format?: (value: number) => string;
		/** Bar fill; defaults to --chart-series-1. */
		color?: string;
		/** Visual gap between bars, in logical px. The bins themselves are
		 *  contiguous; this only insets each rect so adjacent bars read apart. */
		gap?: number;
		/** Play a one-off left-to-right draw-in on mount (client-only, skipped
		 *  under prefers-reduced-motion). Duration via --chart-animate-ms. */
		animate?: boolean;
		/** Override the hover tooltip body; receives (binLabel, points, undefined) —
		 *  a histogram bin is not one source row, so no row is forwarded. */
		tooltip?: Snippet<[unknown, TooltipPoint[], undefined]>;
	}

	let {
		data,
		value,
		bins: binCount,
		domain,
		edges,
		width = 640,
		height = 400,
		title,
		description,
		label = 'Frequency',
		xLabel,
		format,
		color,
		gap = 1,
		animate = false,
		tooltip
	}: Props = $props();

	const fill = $derived(seriesColor(color, 0));

	// The binned distribution — pure, in chartCore. One entry per bucket.
	const binList = $derived(histogramBins(data.map((row) => valueOf(row, value)), { bins: binCount, domain, edges }));

	const margin = $derived({
		top: 18,
		right: 18,
		bottom: 40 + (xLabel ? 22 : 0),
		left: 52 + (label ? 20 : 0)
	});
	const plot = $derived({
		left: margin.left,
		right: width - margin.right,
		top: margin.top,
		bottom: height - margin.bottom
	});

	// x spans exactly the outer bin edges (nice:false → no extra niced margin, so
	// the first/last bars sit flush to the axis ends); its own nice ticks label it.
	const xDomain = $derived<[number, number]>(
		binList.length ? [binList[0].x0, binList[binList.length - 1].x1] : [0, 1]
	);
	const xScale = $derived(linearScale(xDomain, [plot.left, plot.right], { nice: false }));

	const maxCount = $derived(binList.reduce((m, b) => Math.max(m, b.count), 0));
	const yScale = $derived(
		linearScale([0, maxCount], [plot.bottom, plot.top], { zero: true, nice: true })
	);
	const zeroY = $derived(yScale.map(0));

	const fmtEdge = (v: number): string =>
		format ? format(v) : Number.isFinite(v) ? v.toLocaleString('en-US') : String(v);
	const yFormat = (v: unknown): string => {
		const n = Number(v);
		return Number.isFinite(n) ? Math.round(n).toLocaleString('en-US') : String(v);
	};
	const binLabel = (b: { x0: number; x1: number }): string => `${fmtEdge(b.x0)}–${fmtEdge(b.x1)}`;

	interface Bar {
		x: number;
		y: number;
		width: number;
		height: number;
		key: string;
		label: string;
	}

	// One rect per non-empty bin. An empty bin draws nothing (a gap), never a
	// zero-height stub — the same rule BarChart follows for a blank value.
	const bars = $derived.by<Bar[]>(() => {
		const out: Bar[] = [];
		for (let i = 0; i < binList.length; i++) {
			const b = binList[i];
			if (b.count <= 0) continue;
			const bx0 = xScale.map(b.x0);
			const bx1 = xScale.map(b.x1);
			if (Number.isNaN(bx0) || Number.isNaN(bx1)) continue;
			const top = yScale.map(b.count);
			out.push({
				x: bx0 + gap / 2,
				y: Math.min(top, zeroY),
				width: Math.max(0, bx1 - bx0 - gap),
				height: Math.abs(zeroY - top),
				key: `${b.x0}|${b.x1}`,
				label: `${binLabel(b)}: ${b.count.toLocaleString('en-US')}`
			});
		}
		return out;
	});

	// ── Hover tooltip (client-only enhancement) ──────────────────────────────
	// SSR-inert: `mounted` starts false, so the static SVG is byte-identical with
	// or without JS. The pointer snaps to the nearest bin center via nearestIndex.
	let svgEl: SVGSVGElement | undefined = $state();
	let mounted = $state(false);
	let hoverIdx = $state<number | null>(null);

	// Draw-in reveal: a client-only left-to-right clip wipe on mount.
	let revealed = $state(false);
	let animating = $state(false);
	const clipId = `chart-hist-clip-${Math.random().toString(36).slice(2)}`;
	const clipActive = $derived(animate && mounted && animating);
	const PAD = 32;

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

	// Bin center px, ascending — the anchors nearestIndex searches. Every bin
	// (even empty ones) is hoverable, so a gap still reports its "0".
	const anchors = $derived(
		binList
			.map((b, i) => ({ i, px: (xScale.map(b.x0) + xScale.map(b.x1)) / 2 }))
			.filter((a) => Number.isFinite(a.px))
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
		xLabel: string;
		points: TooltipPoint[];
	}
	const hover = $derived.by<Hover | null>(() => {
		if (!mounted || hoverIdx === null) return null;
		const b = binList[hoverIdx];
		if (b === undefined) return null;
		const px = (xScale.map(b.x0) + xScale.map(b.x1)) / 2;
		if (Number.isNaN(px)) return null;
		const top = b.count > 0 ? yScale.map(b.count) : zeroY;
		return {
			px,
			leftPct: (px / width) * 100,
			topPct: (top / height) * 100,
			xLabel: binLabel(b),
			points: [
				{
					key: 'count',
					label,
					value: b.count,
					formatted: b.count.toLocaleString('en-US'),
					color: fill
				}
			]
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
				<g class="bars">
					{#each bars as bar (bar.key)}
						<rect
							x={bar.x}
							y={bar.y}
							width={bar.width}
							height={bar.height}
							{fill}
							aria-label={bar.label}
						/>
					{/each}
				</g>
			</g>

			<!-- baseline the bars grow from -->
			<line class="zero-line" x1={plot.left} y1={zeroY} x2={plot.right} y2={zeroY} />

			<Axis
				orientation="bottom"
				scale={xScale}
				left={plot.left}
				right={plot.right}
				top={plot.top}
				bottom={plot.bottom}
				format={(v) => fmtEdge(Number(v))}
				label={xLabel}
			/>
		</svg>

		{#if hover}
			<ChartTooltip
				xLabel={hover.xLabel}
				points={hover.points}
				left={hover.leftPct}
				top={hover.topPct}
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
	.bars rect {
		transition: opacity 0.15s ease;
	}
	.zero-line {
		stroke: var(--chart-axis, color-mix(in srgb, currentColor 55%, transparent));
		stroke-width: 1.25;
	}
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
