<!--
  BarChart — vertical bars over a categorical (band) x-scale and a linear y-scale
  with a FORCED ZERO baseline: the y domain always includes 0, so bars grow from
  a visible zero line and negative values hang below it. Blank / uncoercible
  values render no bar (never a zero-height stub at the baseline).

  MULTI-SERIES (Phase 2): pass `series` as an array. Two layouts:
    • grouped (default): each category band is subdivided, one bar per series.
    • stacked (`stacked` prop): series stack into one bar per category. A blank
      contributes 0 — the segment has zero thickness and everything above it
      keeps stacking (contrast with lines, where a blank breaks the line). See
      stackSeries in chartCore.ts.
  Colors come from --chart-series-N by series index (SeriesDef.color overrides).

  Wiring + SVG only; all math is pure in chartCore.ts, flowing through the
  chained pipeline (each stage its own $derived, never merged):

      data → categories/series → band-x + linear-y scales → bar rects → SVG

  SSR-safe: the full <svg> renders from props alone. Accessible: role="img" with
  a required `title` (→ <title>), optional `description` (→ <desc>), and one
  aria-label per bar ("us-east: 320", or "us-east — Requests: 320" multi-series).
  Theme via --chart-*.
-->
<script lang="ts" generics="T">
	import { onMount, type Snippet } from 'svelte';
	import Axis from './Axis.svelte';
	import ChartLegend from './ChartLegend.svelte';
	import ChartTooltip from './ChartTooltip.svelte';
	import {
		bandScale,
		keyString,
		linearScale,
		nearestIndex,
		numericExtent,
		seriesColor,
		stackExtent,
		stackSeries,
		toNumber,
		valueOf
	} from './chartCore';
	import type { Accessor, AxisDef, SeriesDef, TooltipPoint } from './types';

	interface Props {
		data: T[];
		x: AxisDef<T>;
		/** One series (single bars) or many (grouped / stacked). */
		series: SeriesDef<T> | SeriesDef<T>[];
		/** Stack series into one bar per category instead of grouping them. */
		stacked?: boolean;
		/** Show a clickable legend that toggles series visibility. */
		legend?: boolean;
		/** Hidden series keys — bindable so a parent can drive/observe visibility. */
		hidden?: Set<string>;
		/** Row keys (as produced by `rowKeyAccessor`) to emphasise; every other
		 *  bar dims. The chart-side hook for a DataTable's `bind:selected` — the
		 *  parent maps selected rows to keys. Empty/undefined → no highlighting. */
		highlighted?: unknown[];
		/** How to read a row's key, matched against `highlighted` (field name or
		 *  function — the same identity the table selects by). */
		rowKeyAccessor?: Accessor<T>;
		width?: number;
		height?: number;
		/** Accessible name (SVG <title>) — required. */
		title: string;
		description?: string;
		/** Play a one-off left-to-right draw-in when the chart mounts (client-only,
		 *  skipped under prefers-reduced-motion). Duration via --chart-animate-ms. */
		animate?: boolean;
		/** Override the hover tooltip body; receives (xValue, points, row) — a bar
		 *  hover snaps to one source row, passed so the tooltip can show columns the
		 *  chart itself never plots (e.g. `row.label`). */
		tooltip?: Snippet<[unknown, TooltipPoint[], T]>;
	}

	let {
		data,
		x,
		series,
		stacked = false,
		legend = false,
		hidden = $bindable(new Set<string>()),
		highlighted,
		rowKeyAccessor,
		width = 640,
		height = 400,
		title,
		description,
		animate = false,
		tooltip
	}: Props = $props();

	// Selection highlighting: with a non-empty `highlighted` list + a
	// `rowKeyAccessor`, bars whose row key is in the list are emphasised and the
	// rest dim. No coupling to the DataTable — just row keys in, matched by value.
	const hlKeys = $derived(new Set((highlighted ?? []).map(keyString)));
	const hlActive = $derived(!!rowKeyAccessor && hlKeys.size > 0);
	const isHighlighted = (row: T): boolean =>
		hlActive && hlKeys.has(keyString(valueOf(row, rowKeyAccessor!)));

	const seriesList = $derived(Array.isArray(series) ? series : [series]);
	// Visible series drive every scale — hiding one re-fits the y axis.
	const shown = $derived(seriesList.filter((s) => !hidden.has(s.key)));
	const multi = $derived(seriesList.length > 1);

	// Color by a series' position in the FULL list (not `shown`), so hiding one
	// doesn't recolor the rest and the legend swatches always match the bars.
	const colorOf = $derived((key: string) => {
		const i = seriesList.findIndex((s) => s.key === key);
		return seriesColor(seriesList[i]?.color, i);
	});

	// Margins leave room for tick labels and (when present) axis labels. The y
	// axis label only makes sense for a single series; multi-series is labelled
	// by the legend, so drop the left axis label then.
	const yAxisLabel = $derived(!multi ? shown[0]?.label : undefined);
	const margin = $derived({
		top: 18,
		right: 18,
		bottom: 40 + (x.label ? 22 : 0),
		left: 52 + (yAxisLabel ? 20 : 0)
	});
	const plot = $derived({
		left: margin.left,
		right: width - margin.right,
		top: margin.top,
		bottom: height - margin.bottom
	});

	const categories = $derived(data.map((row) => valueOf(row, x.value)));
	const xScale = $derived(bandScale(categories, [plot.left, plot.right]));

	// Stacked totals (used both for the y extent and the rects); one entry per row.
	const stacks = $derived(stacked ? stackSeries(data, shown) : []);

	// y extent: stacked → tallest stack (already spans 0); grouped → the widest
	// [min, max] across every visible series. zero:true keeps a visible baseline.
	const yExtent = $derived.by<[number, number]>(() => {
		if (stacked) return stackExtent(stacks);
		let min = Infinity;
		let max = -Infinity;
		for (const s of shown) {
			const [lo, hi] = numericExtent(data, s.value);
			if (Number.isFinite(lo) && lo < min) min = lo;
			if (Number.isFinite(hi) && hi > max) max = hi;
		}
		return min === Infinity ? [NaN, NaN] : [min, max];
	});
	const yScale = $derived(
		linearScale(yExtent, [plot.bottom, plot.top], { zero: true, nice: true })
	);
	const zeroY = $derived(yScale.map(0));

	const yFormat = (v: unknown): string => {
		const n = Number(v);
		const fmt = !multi ? shown[0]?.format : undefined;
		return fmt ? fmt(n) : Number.isFinite(n) ? n.toLocaleString('en-US') : String(v);
	};
	const catLabel = (cat: unknown): string => (cat === null || cat === undefined ? '' : String(cat));
	const fmtSeries = (s: SeriesDef<T>, v: number): string =>
		s.format ? s.format(v) : v.toLocaleString('en-US');
	const ariaLabel = (cat: unknown, s: SeriesDef<T>, v: number): string =>
		multi
			? `${catLabel(cat)} — ${s.label}: ${fmtSeries(s, v)}`
			: `${catLabel(cat)}: ${fmtSeries(s, v)}`;

	interface Bar {
		x: number;
		y: number;
		width: number;
		height: number;
		fill: string;
		key: string;
		label: string;
		hl: boolean; // this bar's row is in the highlighted set
	}

	// The bars: grouped subdivides each band per series; stacked layers segments.
	const bars = $derived.by<Bar[]>(() => {
		const out: Bar[] = [];
		if (stacked) {
			data.forEach((row, i) => {
				const cat = valueOf(row, x.value);
				const bx = xScale.map(cat);
				if (Number.isNaN(bx)) return;
				const hl = isHighlighted(row);
				stacks[i]?.forEach((seg, si) => {
					if (seg.value === 0) return; // blank or zero → no rect
					const s = shown[si];
					const yTop = yScale.map(seg.y1);
					const yBase = yScale.map(seg.y0);
					out.push({
						x: bx,
						y: Math.min(yTop, yBase),
						width: xScale.bandwidth,
						height: Math.abs(yTop - yBase),
						fill: colorOf(s.key),
						key: `${catLabel(cat)}|${s.key}`,
						label: ariaLabel(cat, s, seg.value),
						hl
					});
				});
			});
			return out;
		}

		// grouped: an inner band scale places each series' bar inside the category.
		const keys = shown.map((s) => s.key);
		for (const row of data) {
			const cat = valueOf(row, x.value);
			const bx = xScale.map(cat);
			if (Number.isNaN(bx)) continue;
			const inner = bandScale(keys, [bx, bx + xScale.bandwidth], {
				paddingInner: multi ? 0.12 : 0,
				paddingOuter: 0
			});
			const hl = isHighlighted(row);
			shown.forEach((s, si) => {
				const v = toNumber(valueOf(row, s.value));
				if (Number.isNaN(v)) return; // blank → no bar
				const vy = yScale.map(v);
				const sx = inner.map(s.key);
				out.push({
					x: sx,
					y: Math.min(vy, zeroY),
					width: inner.bandwidth,
					height: Math.abs(vy - zeroY),
					fill: colorOf(s.key),
					key: `${catLabel(cat)}|${s.key}`,
					label: ariaLabel(cat, s, v),
					hl
				});
			});
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
	const clipId = `chart-bar-clip-${Math.random().toString(36).slice(2)}`;
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

	// Band center per row, sorted ascending — the anchors nearestIndex searches.
	const anchors = $derived(
		data
			.map((row, i) => {
				const bx = xScale.map(valueOf(row, x.value));
				return { i, px: bx + xScale.bandwidth / 2 };
			})
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
		row: T; // the one source row under the pointer (forwarded to the tooltip snippet)
	}
	const hover = $derived.by<Hover | null>(() => {
		if (!mounted || hoverIdx === null) return null;
		const row = data[hoverIdx];
		if (row === undefined) return null;
		const cat = valueOf(row, x.value);
		const bx = xScale.map(cat);
		if (Number.isNaN(bx)) return null;
		const px = bx + xScale.bandwidth / 2;

		const pts: TooltipPoint[] = shown.map((s) => {
			const num = toNumber(valueOf(row, s.value));
			const blank = Number.isNaN(num);
			return {
				key: s.key,
				label: s.label,
				value: blank ? null : num,
				formatted: blank ? '—' : fmtSeries(s, num),
				color: colorOf(s.key)
			};
		});

		// Vertical anchor: the top of the tallest bar in this category.
		const catBars = bars.filter((b) => b.key.startsWith(`${catLabel(cat)}|`));
		const topY = catBars.length
			? Math.min(...catBars.map((b) => b.y))
			: plot.top + (plot.bottom - plot.top) / 2;

		return {
			px,
			leftPct: (px / width) * 100,
			topPct: (topY / height) * 100,
			xValue: cat,
			xLabel: x.format ? x.format(cat) : catLabel(cat),
			points: pts,
			row
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
				label={yAxisLabel}
			/>

			<g class="marks" clip-path={clipActive ? `url(#${clipId})` : undefined}>
				<g class="bars">
					{#each bars as bar (bar.key)}
						<rect
							x={bar.x}
							y={bar.y}
							width={bar.width}
							height={bar.height}
							fill={bar.fill}
							class:hl={bar.hl}
							class:dim={hlActive && !bar.hl}
							aria-label={bar.label}
						/>
					{/each}
				</g>
			</g>

			<!-- zero baseline: where bars originate; negatives hang below it -->
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

	{#if legend}
		<ChartLegend series={seriesList} bind:hidden />
	{/if}
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
		transition:
			opacity 0.15s ease,
			stroke-width 0.15s ease;
	}
	/* Selection highlighting: emphasise the chosen bars, dim the rest. */
	.bars rect.dim {
		opacity: 0.32;
	}
	.bars rect.hl {
		stroke: var(--chart-highlight, color-mix(in srgb, currentColor 85%, transparent));
		stroke-width: 2;
		paint-order: stroke;
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
