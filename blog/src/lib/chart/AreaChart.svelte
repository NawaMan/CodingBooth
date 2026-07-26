<!--
  AreaChart — a filled region under each series over a linear (or time) x-scale.
  Unlike the LineChart, an area reads MAGNITUDE, so its y-axis always includes a
  zero baseline: the fill is "how much", measured up from zero.

  Two layouts (mirroring the BarChart):
    • overlaid (default): each series is its own translucent region from the zero
      baseline to its value, drawn back-to-front. A blank / uncoercible y BREAKS
      that region into a gap (areaPath restarts), never dipping through 0 — the
      same blank semantics as the line it's built on.
    • stacked (`stacked` prop): series stack into one cumulative band each, via
      the same stackSeries machinery the stacked bars use. A blank contributes 0
      — the band pinches to zero thickness and everything above keeps stacking
      (a running total, so a missing part is "nothing added here").

  Each region carries a crisp top stroke (linePath) so overlapping fills stay
  legible. Colors come from --chart-series-N by series index (SeriesDef.color
  overrides), toggled by the optional legend.

  Wiring + SVG only; all math is pure in chartCore.ts:

      data → x + per-series y values → linear scales → area paths (+ top line) → SVG

  SSR-safe (full <svg> from props alone; the hover tooltip and the optional
  `animate` draw-in are client-only enhancements gated on onMount, so the static
  markup is byte-identical without JS). Accessible: role="img" with a required
  `title` (→ <title>) and optional `description` (→ <desc>); each region carries
  an aria-label with its series name. Theme via --chart-*.
-->
<script lang="ts" generics="T">
	import { onMount, type Snippet } from 'svelte';
	import Axis from './Axis.svelte';
	import ChartLegend from './ChartLegend.svelte';
	import ChartTooltip from './ChartTooltip.svelte';
	import {
		areaPath,
		keyString,
		linePath,
		linearScale,
		nearestIndex,
		numericExtent,
		seriesColor,
		stackExtent,
		stackSeries,
		timeTicks,
		toNumber,
		toTime,
		valueOf
	} from './chartCore';
	import type { Accessor, AxisDef, Point, SeriesDef, TooltipPoint } from './types';

	interface Props {
		data: T[];
		x: AxisDef<T>;
		/** One series (single region) or many (overlaid / stacked). */
		series: SeriesDef<T> | SeriesDef<T>[];
		/** Stack the series into cumulative bands instead of overlaying them. */
		stacked?: boolean;
		/** Show a clickable legend that toggles series visibility. */
		legend?: boolean;
		/** Hidden series keys — bindable so a parent can drive/observe visibility. */
		hidden?: Set<string>;
		width?: number;
		height?: number;
		/** Accessible name (SVG <title>) — required. */
		title: string;
		description?: string;
		/** Draw a dot at each (finite) data point. */
		points?: boolean;
		/** Row keys (from `rowKeyAccessor`) to emphasise; matching point markers are
		 *  revealed and the rest dim — the chart-side hook for a DataTable's
		 *  `bind:selected`. */
		highlighted?: unknown[];
		/** How to read a row's key, matched against `highlighted`. */
		rowKeyAccessor?: Accessor<T>;
		/** Play a one-off left-to-right draw-in when the chart mounts (client-only,
		 *  skipped under prefers-reduced-motion). Duration via --chart-animate-ms. */
		animate?: boolean;
		/** Override the hover tooltip body; receives (xValue, points, row). */
		tooltip?: Snippet<[unknown, TooltipPoint[], T]>;
	}

	let {
		data,
		x,
		series,
		stacked = false,
		legend = false,
		hidden = $bindable(new Set<string>()),
		width = 640,
		height = 400,
		title,
		description,
		points = false,
		highlighted,
		rowKeyAccessor,
		animate = false,
		tooltip
	}: Props = $props();

	// Selection highlighting: with a non-empty `highlighted` list + a
	// `rowKeyAccessor`, matching point markers are emphasised and the rest dim.
	const hlKeys = $derived(new Set((highlighted ?? []).map(keyString)));
	const hlActive = $derived(!!rowKeyAccessor && hlKeys.size > 0);
	const isHighlighted = (row: T): boolean =>
		hlActive && hlKeys.has(keyString(valueOf(row, rowKeyAccessor!)));
	const showDots = $derived(points || hlActive);

	const seriesList = $derived(Array.isArray(series) ? series : [series]);
	// Visible series drive the y extent — hiding one re-fits the axis.
	const shown = $derived(seriesList.filter((s) => !hidden.has(s.key)));
	const multi = $derived(seriesList.length > 1);

	const leftLabel = $derived(!multi ? shown[0]?.label : undefined);
	const margin = $derived({
		top: 18,
		right: 18,
		bottom: 40 + (x.label ? 22 : 0),
		left: 52 + (leftLabel ? 20 : 0)
	});
	const plot = $derived({
		left: margin.left,
		right: width - margin.right,
		top: margin.top,
		bottom: height - margin.bottom
	});

	// Time axis: x values coerce to ms timestamps; the numeric scale then works
	// unchanged and only the ticks/labels become calendar-aware (mirrors LineChart).
	const isTime = $derived(x.type === 'time');
	const xNum = (row: T): number =>
		isTime ? toTime(valueOf(row, x.value)) : toNumber(valueOf(row, x.value));
	const xPix = (row: T): number => xScale.map(xNum(row));

	const xScale = $derived(
		linearScale(
			numericExtent(data, (r: T) => xNum(r)),
			[plot.left, plot.right],
			{ nice: !isTime }
		)
	);
	const timeT = $derived(
		isTime ? timeTicks(xScale.domain[0], xScale.domain[1], x.ticks ?? 6) : null
	);
	const xAxisScale = $derived(
		timeT ? { map: xScale.map, ticks: timeT.ticks, domain: xScale.domain } : xScale
	);
	const xTickText = (v: unknown): string => {
		if (timeT) return x.format ? x.format(new Date(v as number)) : timeT.format(v as number);
		return x.format ? x.format(v) : v === null || v === undefined ? '' : String(v);
	};

	// Stacked totals (used both for the y extent and the bands); one entry per row.
	const stacks = $derived(stacked ? stackSeries(data, shown) : []);

	// y extent always includes zero (area = magnitude up from a baseline). Stacked
	// spans the tallest stack; overlaid spans the widest [min, max] across series.
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

	interface Dot extends Point {
		hl: boolean; // this point's row is in the highlighted set
	}
	interface Area {
		key: string;
		label: string;
		color: string;
		fill: string; // the filled region path
		stroke: string; // the crisp top edge (linePath)
		dots: Dot[];
	}

	// One region per visible series. Overlaid: from the zero baseline to the value
	// (a blank breaks the region). Stacked: between this series' cumulative y0 and
	// y1 edges (a blank pinches to zero thickness). Color by a series' position in
	// the FULL list so hiding one doesn't recolor the rest (legend swatches match).
	const areas = $derived.by<Area[]>(() =>
		shown.map((s, si) => {
			const idx = seriesList.findIndex((o) => o.key === s.key);
			const top: Dot[] = data.map((row, i) => {
				const px = xPix(row);
				const y = stacked
					? yScale.map(stacks[i]?.[si]?.y1 ?? NaN)
					: yScale.map(valueOf(row, s.value));
				return { x: px, y, hl: isHighlighted(row) };
			});
			const base: Point[] = data.map((row, i) => ({
				x: xPix(row),
				y: stacked ? yScale.map(stacks[i]?.[si]?.y0 ?? NaN) : zeroY
			}));
			return {
				key: s.key,
				label: s.label,
				color: seriesColor(s.color, idx),
				fill: areaPath(top, base),
				stroke: linePath(top),
				dots: top.filter((p) => Number.isFinite(p.x) && Number.isFinite(p.y))
			};
		})
	);

	// The visible top of the stack/region at a row — where the hover anchors.
	const topEdgeY = (row: T, rowIdx: number): number => {
		const ys = shown
			.map((s, si) =>
				stacked ? yScale.map(stacks[rowIdx]?.[si]?.y1 ?? NaN) : yScale.map(valueOf(row, s.value))
			)
			.filter((y) => Number.isFinite(y));
		return ys.length ? Math.min(...ys) : plot.top + (plot.bottom - plot.top) / 2;
	};

	// ── Hover tooltip (client-only enhancement) ──────────────────────────────
	// SSR-inert: `mounted` starts false, so the static SVG is byte-identical with
	// or without JS. Pointer tracking snaps to the nearest data x via nearestIndex.
	let svgEl: SVGSVGElement | undefined = $state();
	let mounted = $state(false);
	let hoverIdx = $state<number | null>(null);

	// Draw-in reveal: a client-only left-to-right clip wipe on mount (skipped under
	// prefers-reduced-motion). Never present in SSR markup — a pure enhancement.
	let revealed = $state(false);
	let animating = $state(false);
	const clipId = `chart-area-clip-${Math.random().toString(36).slice(2)}`;
	const clipActive = $derived(animate && mounted && animating);
	const PAD = 32; // clip rect padding so marks near the plot edge aren't cut once revealed

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

	// Finite x pixel per row, sorted ascending — the anchors nearestIndex searches.
	const anchors = $derived(
		data
			.map((row, i) => ({ i, px: xPix(row) }))
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
		const px = xPix(row);
		if (!Number.isFinite(px)) return null;

		const pts: TooltipPoint[] = shown.map((s) => {
			const num = toNumber(valueOf(row, s.value));
			const blank = Number.isNaN(num);
			const idx = seriesList.findIndex((o) => o.key === s.key);
			return {
				key: s.key,
				label: s.label,
				value: blank ? null : num,
				formatted: blank ? '—' : s.format ? s.format(num) : num.toLocaleString('en-US'),
				color: seriesColor(s.color, idx)
			};
		});

		return {
			px,
			leftPct: (px / width) * 100,
			topPct: (topEdgeY(row, hoverIdx) / height) * 100,
			xValue: valueOf(row, x.value),
			xLabel: isTime ? xTickText(xNum(row)) : xTickText(valueOf(row, x.value)),
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

			<Axis
				orientation="left"
				scale={yScale}
				left={plot.left}
				right={plot.right}
				top={plot.top}
				bottom={plot.bottom}
				format={yFormat}
				gridlines
				label={leftLabel}
			/>
			<Axis
				orientation="bottom"
				scale={xAxisScale}
				left={plot.left}
				right={plot.right}
				top={plot.top}
				bottom={plot.bottom}
				format={xTickText}
				label={x.label}
			/>

			<g class="marks" clip-path={clipActive ? `url(#${clipId})` : undefined}>
				<g class="areas">
					{#each areas as area (area.key)}
						<path
							class="area"
							class:dim={hlActive}
							d={area.fill}
							fill={area.color}
							stroke="none"
							aria-label={area.label}
						/>
						<path
							class="edge"
							class:dim={hlActive}
							d={area.stroke}
							fill="none"
							stroke={area.color}
						/>
						{#if showDots}
							<g class="dots">
								{#each area.dots as p, i (i)}
									<circle
										cx={p.x}
										cy={p.y}
										r={p.hl ? 4.5 : 3}
										fill={area.color}
										class:hl={p.hl}
										class:dim={hlActive && !p.hl}
									/>
								{/each}
							</g>
						{/if}
					{/each}
				</g>
			</g>

			<!-- zero baseline: where the regions originate -->
			<line class="zero-line" x1={plot.left} y1={zeroY} x2={plot.right} y2={zeroY} />

			{#if hover}
				<line class="guide" x1={hover.px} y1={plot.top} x2={hover.px} y2={plot.bottom} />
			{/if}
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
	.area {
		fill-opacity: var(--chart-area-opacity, 0.35);
		transition: opacity 0.15s ease;
	}
	.edge {
		stroke-width: 2;
		stroke-linejoin: round;
		stroke-linecap: round;
		transition: opacity 0.15s ease;
	}
	/* Selection highlighting: fade the fills so the marked points read. */
	.area.dim {
		opacity: 0.5;
	}
	.edge.dim {
		opacity: 0.55;
	}
	.dots circle {
		transition: opacity 0.15s ease;
	}
	.dots circle.dim {
		opacity: 0.3;
	}
	.dots circle.hl {
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
