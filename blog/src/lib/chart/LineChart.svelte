<!--
  LineChart — one line per series over a linear x-scale and a linear y-scale
  (y does NOT force zero by default — a line reads relative change, not
  magnitude-from-zero). A blank / uncoercible y BREAKS THAT LINE INTO A GAP
  (linePath restarts with a fresh M), never dipping through 0. Points are drawn
  in array order, so the caller sorts rows by x (same pipeline philosophy as the
  table) — the x-scale places each point at its true value, so uneven spacing
  shows as uneven gaps.

  MULTI-SERIES (Phase 2): pass `series` as an array — one line each, colored from
  --chart-series-N by series index (SeriesDef.color overrides). By default the y
  extent spans every series so they share one axis. With `dualAxis` (exactly two
  series) the first series gets the LEFT y-axis and the second the RIGHT, each on
  its own scale and tinted to match — so two very different magnitudes (e.g.
  requests vs cost) both read legibly instead of one lying flat.

  Wiring + SVG only; all math is pure in chartCore.ts:

      data → x + per-series y values → linear scales → line paths (+ dots) → SVG

  SSR-safe (full <svg> from props alone). Accessible: role="img" with a required
  `title` (→ <title>) and optional `description` (→ <desc>); each line carries an
  aria-label with its series name. Theme via --chart-*. Optional dots via `points`.
-->
<script lang="ts" generics="T">
	import { onMount, type Snippet } from 'svelte';
	import Axis from './Axis.svelte';
	import ChartLegend from './ChartLegend.svelte';
	import ChartTooltip from './ChartTooltip.svelte';
	import {
		keyString,
		linePath,
		linearScale,
		nearestIndex,
		numericExtent,
		seriesColor,
		timeTicks,
		toNumber,
		toTime,
		valueOf
	} from './chartCore';
	import type { Accessor, AxisDef, Point, SeriesDef, TooltipPoint } from './types';

	interface Props {
		data: T[];
		x: AxisDef<T>;
		/** One series (single line) or many (a line each). */
		series: SeriesDef<T> | SeriesDef<T>[];
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
		/** Row keys (from `rowKeyAccessor`) to emphasise; matching points are
		 *  marked and the rest dim — the chart-side hook for a DataTable's
		 *  `bind:selected`. Highlighting reveals the point markers even when
		 *  `points` is off, so a selection is visible on the line. */
		highlighted?: unknown[];
		/** How to read a row's key, matched against `highlighted`. */
		rowKeyAccessor?: Accessor<T>;
		/** Two series of different magnitudes on independent axes: the first series
		 *  on the left y-axis, the second on the right, each with its own scale.
		 *  Requires exactly two series (ignored otherwise). */
		dualAxis?: boolean;
		/** Play a one-off left-to-right draw-in when the chart mounts (client-only,
		 *  skipped under prefers-reduced-motion). Duration via --chart-animate-ms. */
		animate?: boolean;
		/** Override the hover tooltip body; receives (xValue, points, row) — a line
		 *  hover snaps to one source row, passed so the tooltip can show columns the
		 *  chart itself never plots (e.g. `row.label`). */
		tooltip?: Snippet<[unknown, TooltipPoint[], T]>;
	}

	let {
		data,
		x,
		series,
		legend = false,
		hidden = $bindable(new Set<string>()),
		width = 640,
		height = 400,
		title,
		description,
		points = false,
		dualAxis = false,
		highlighted,
		rowKeyAccessor,
		animate = false,
		tooltip
	}: Props = $props();

	// Selection highlighting: with a non-empty `highlighted` list + a
	// `rowKeyAccessor`, matching point markers are emphasised and the rest dim
	// (and the markers show even when `points` is off, so the selection reads).
	const hlKeys = $derived(new Set((highlighted ?? []).map(keyString)));
	const hlActive = $derived(!!rowKeyAccessor && hlKeys.size > 0);
	const isHighlighted = (row: T): boolean =>
		hlActive && hlKeys.has(keyString(valueOf(row, rowKeyAccessor!)));
	const showDots = $derived(points || hlActive);

	const seriesList = $derived(Array.isArray(series) ? series : [series]);
	// Visible series drive the y extent — hiding one re-fits the axis.
	const shown = $derived(seriesList.filter((s) => !hidden.has(s.key)));
	const multi = $derived(seriesList.length > 1);

	// Dual-axis: exactly two series, first → left axis, second → right, each on
	// its own scale so wildly different magnitudes both read legibly.
	const dual = $derived(dualAxis && seriesList.length === 2);
	const sA = $derived(seriesList[0]);
	const sB = $derived(seriesList[1]);
	const colorA = $derived(sA ? seriesColor(sA.color, 0) : '');
	const colorB = $derived(sB ? seriesColor(sB.color, 1) : '');

	// Axis labels: single-series labels the (one) left axis; dual labels both
	// sides; plain multi-series is labelled by the legend instead.
	const leftLabel = $derived(dual ? sA?.label : !multi ? shown[0]?.label : undefined);
	const rightLabel = $derived(dual ? sB?.label : undefined);
	const margin = $derived({
		top: 18,
		right: dual ? 52 + (rightLabel ? 20 : 0) : 18,
		bottom: 40 + (x.label ? 22 : 0),
		left: 52 + (leftLabel ? 20 : 0)
	});
	const plot = $derived({
		left: margin.left,
		right: width - margin.right,
		top: margin.top,
		bottom: height - margin.bottom
	});

	// Time axis: x values coerce to ms timestamps (Date / ISO string / number;
	// invalid dates are blanks). The numeric scale then works unchanged; only the
	// ticks and their labels become calendar-aware (see timeTicks below).
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

	// Calendar ticks + default label formatter for a time axis; AxisDef.format
	// (given a Date) overrides the labels.
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

	// y extent spans every visible series so they share one axis. zero:false —
	// lines don't force a zero baseline.
	const yExtent = $derived.by<[number, number]>(() => {
		let min = Infinity;
		let max = -Infinity;
		for (const s of shown) {
			const [lo, hi] = numericExtent(data, s.value);
			if (Number.isFinite(lo) && lo < min) min = lo;
			if (Number.isFinite(hi) && hi > max) max = hi;
		}
		return min === Infinity ? [NaN, NaN] : [min, max];
	});
	const yScale = $derived(linearScale(yExtent, [plot.bottom, plot.top], { nice: true }));

	// Dual axis: an independent scale per side (each fitted to its own series);
	// both fall back to the shared yScale when not dual.
	const yA = $derived(
		dual
			? linearScale(numericExtent(data, sA.value), [plot.bottom, plot.top], { nice: true })
			: yScale
	);
	const yB = $derived(
		dual
			? linearScale(numericExtent(data, sB.value), [plot.bottom, plot.top], { nice: true })
			: yScale
	);
	const yFor = (key: string) => (dual ? (key === sA.key ? yA : yB) : yScale);

	const fmtAxis = (s: SeriesDef<T> | undefined) => (v: unknown) => {
		const n = Number(v);
		return s?.format ? s.format(n) : Number.isFinite(n) ? n.toLocaleString('en-US') : String(v);
	};

	interface Dot extends Point {
		hl: boolean; // this point's row is in the highlighted set
	}
	interface Line {
		key: string;
		label: string;
		color: string;
		d: string;
		dots: Dot[];
	}

	// One line per visible series; a blank y yields a non-finite point, which
	// linePath turns into a gap and the dots skip. Color by a series' position in
	// the FULL list so hiding one doesn't recolor the rest (legend swatches match).
	const lines = $derived.by<Line[]>(() =>
		shown.map((s) => {
			const idx = seriesList.findIndex((o) => o.key === s.key);
			const scale = yFor(s.key);
			const pts: Dot[] = data.map((row) => ({
				x: xPix(row),
				y: scale.map(valueOf(row, s.value)),
				hl: isHighlighted(row)
			}));
			return {
				key: s.key,
				label: s.label,
				color: seriesColor(s.color, idx),
				d: linePath(pts),
				dots: pts.filter((p) => Number.isFinite(p.x) && Number.isFinite(p.y))
			};
		})
	);

	const yFormat = (v: unknown): string => {
		const n = Number(v);
		const fmt = !multi ? shown[0]?.format : undefined;
		return fmt ? fmt(n) : Number.isFinite(n) ? n.toLocaleString('en-US') : String(v);
	};

	// ── Hover tooltip (client-only enhancement) ──────────────────────────────
	// Nothing here renders during SSR: `mounted` starts false, so the static SVG
	// is byte-identical with or without JS. Pointer tracking snaps to the nearest
	// data x via the pure nearestIndex binary search.
	let svgEl: SVGSVGElement | undefined = $state();
	let mounted = $state(false);
	let hoverIdx = $state<number | null>(null);

	// Draw-in reveal: a client-only left-to-right clip wipe on mount (skipped under
	// prefers-reduced-motion). Never present in SSR markup — a pure enhancement.
	let revealed = $state(false);
	let animating = $state(false);
	const clipId = `chart-line-clip-${Math.random().toString(36).slice(2)}`;
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

		// Vertical anchor: the highest (smallest y) finite series point at this x.
		const ys = shown
			.map((s) => yFor(s.key).map(valueOf(row, s.value)))
			.filter((y) => Number.isFinite(y));
		const topY = ys.length ? Math.min(...ys) : plot.top + (plot.bottom - plot.top) / 2;

		return {
			px,
			leftPct: (px / width) * 100,
			topPct: (topY / height) * 100,
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
				scale={dual ? yA : yScale}
				left={plot.left}
				right={plot.right}
				top={plot.top}
				bottom={plot.bottom}
				format={dual ? fmtAxis(sA) : yFormat}
				color={dual ? colorA : undefined}
				gridlines
				label={leftLabel}
			/>
			{#if dual}
				<Axis
					orientation="right"
					scale={yB}
					left={plot.left}
					right={plot.right}
					top={plot.top}
					bottom={plot.bottom}
					format={fmtAxis(sB)}
					color={colorB}
					label={rightLabel}
				/>
			{/if}
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
				<g class="lines">
					{#each lines as line (line.key)}
						<path
							class="line"
							class:dim={hlActive}
							d={line.d}
							fill="none"
							stroke={line.color}
							aria-label={line.label}
						/>
						{#if showDots}
							<g class="dots">
								{#each line.dots as p, i (i)}
									<circle
										cx={p.x}
										cy={p.y}
										r={p.hl ? 4.5 : 3}
										fill={line.color}
										class:hl={p.hl}
										class:dim={hlActive && !p.hl}
									/>
								{/each}
							</g>
						{/if}
					{/each}
				</g>
			</g>

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
	.line {
		stroke-width: 2;
		stroke-linejoin: round;
		stroke-linecap: round;
		transition: opacity 0.15s ease;
	}
	/* Selection highlighting: fade the line so the marked points read, emphasise
	   the selected point markers and dim the rest. */
	.line.dim {
		opacity: 0.45;
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
