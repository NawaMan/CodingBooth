<!--
  ScatterChart — one dot per row on TWO linear axes (x and y both continuous),
  the chart for correlation/distribution rather than trend or magnitude. Unlike
  the LineChart nothing is connected and rows need no sorting; unlike the
  BarChart neither axis forces a zero baseline (a scatter reads position, not
  size-from-zero). A blank / uncoercible x OR y drops that point entirely (it's
  never plotted at 0) — the same blank semantics as the rest of the family.

  MULTI-SERIES: pass `series` as an array — each series is its own point cloud
  over the shared x, colored from --chart-series-N by series index (SeriesDef.
  color overrides), toggled by the optional legend.

  BUBBLE MODE: give a series a `size` accessor and each dot's AREA scales with
  that value (via bubbleRadius — area, not radius, is proportional, the honest
  encoding). The size scale is shared across every sized series so bubbles are
  comparable; `sizeRange` sets the [min, max] radii. Without `size`, dots are a
  uniform `pointRadius`.

  Wiring + SVG only; all math is pure in chartCore.ts:

      data → x + per-series y (+ size) values → linear scales → dots → SVG

  SSR-safe (full <svg> from props alone; the hover tooltip is a client-only
  enhancement gated on onMount, so the static markup is byte-identical without
  JS). Accessible: role="img" with a required `title` (→ <title>) and optional
  `description` (→ <desc>); each dot carries an aria-label with its coordinates.
  Theme via --chart-*.
-->
<script lang="ts" generics="T">
	import { onMount, type Snippet } from 'svelte';
	import Axis from './Axis.svelte';
	import ChartLegend from './ChartLegend.svelte';
	import ChartTooltip from './ChartTooltip.svelte';
	import {
		bubbleRadius,
		keyString,
		linearScale,
		nearestPoint,
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
		/** One series (single cloud) or many (a cloud each). */
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
		/** Dot radius when a series has no `size` accessor (uniform dots). */
		pointRadius?: number;
		/** [min, max] radii for bubble mode (a series with a `size` accessor). */
		sizeRange?: [number, number];
		/** Row keys (from `rowKeyAccessor`) to emphasise; matching dots are marked
		 *  and the rest dim — the chart-side hook for a DataTable's `bind:selected`. */
		highlighted?: unknown[];
		/** How to read a row's key, matched against `highlighted`. */
		rowKeyAccessor?: Accessor<T>;
		/** Play a one-off left-to-right draw-in when the chart mounts (client-only,
		 *  skipped under prefers-reduced-motion). Duration via --chart-animate-ms. */
		animate?: boolean;
		/** Override the hover tooltip body; receives (xValue, points, row) — a
		 *  scatter hover maps to exactly one dot, so the hovered source row is
		 *  passed too (show `row.name` etc. that the chart itself never sees). */
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
		pointRadius = 6,
		sizeRange = [5, 22],
		highlighted,
		rowKeyAccessor,
		animate = false,
		tooltip
	}: Props = $props();

	// Selection highlighting: with a non-empty `highlighted` list + a
	// `rowKeyAccessor`, matching dots are emphasised and the rest dim.
	const hlKeys = $derived(new Set((highlighted ?? []).map(keyString)));
	const hlActive = $derived(!!rowKeyAccessor && hlKeys.size > 0);
	const isHighlighted = (row: T): boolean =>
		hlActive && hlKeys.has(keyString(valueOf(row, rowKeyAccessor!)));

	const seriesList = $derived(Array.isArray(series) ? series : [series]);
	// Visible series drive the y (and size) extent — hiding one re-fits them.
	const shown = $derived(seriesList.filter((s) => !hidden.has(s.key)));
	const multi = $derived(seriesList.length > 1);

	// Axis labels: single-series labels the (one) left axis; multi is labelled by
	// the legend instead.
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

	// y extent spans every visible series so they share one axis. zero:false — a
	// scatter reads position, not a zero baseline.
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

	// Shared size extent across every visible SIZED series, so bubbles are
	// comparable between series (and NaN when no series carries a size accessor).
	const sizeExtent = $derived.by<[number, number]>(() => {
		let min = Infinity;
		let max = -Infinity;
		for (const s of shown) {
			if (!s.size) continue;
			const [lo, hi] = numericExtent(data, s.size);
			if (Number.isFinite(lo) && lo < min) min = lo;
			if (Number.isFinite(hi) && hi > max) max = hi;
		}
		return min === Infinity ? [NaN, NaN] : [min, max];
	});

	const yFormat = (v: unknown): string => {
		const n = Number(v);
		const fmt = !multi ? shown[0]?.format : undefined;
		return fmt ? fmt(n) : Number.isFinite(n) ? n.toLocaleString('en-US') : String(v);
	};
	const fmtSeries = (s: SeriesDef<T>, v: number): string =>
		s.format ? s.format(v) : v.toLocaleString('en-US');

	interface Dot extends Point {
		r: number;
		color: string;
		key: string; // unique per (series, row) for keyed #each
		label: string; // aria-label
		hl: boolean;
		si: number; // index into `shown`
		rowIdx: number;
	}

	// One dot per (visible series, row). A blank x OR y yields a non-finite
	// coordinate and the dot is dropped (never plotted at 0). Color by a series'
	// position in the FULL list so hiding one doesn't recolor the rest.
	const dots = $derived.by<Dot[]>(() => {
		const out: Dot[] = [];
		shown.forEach((s, si) => {
			const idx = seriesList.findIndex((o) => o.key === s.key);
			const color = seriesColor(s.color, idx);
			data.forEach((row, rowIdx) => {
				const cx = xScale.map(xNum(row));
				const cy = yScale.map(valueOf(row, s.value));
				if (!Number.isFinite(cx) || !Number.isFinite(cy)) return; // blank → drop
				const r = s.size ? bubbleRadius(valueOf(row, s.size), sizeExtent, sizeRange) : pointRadius;
				const yNum = toNumber(valueOf(row, s.value));
				const coord = `(${xTickText(isTime ? xNum(row) : valueOf(row, x.value))}, ${fmtSeries(s, yNum)})`;
				out.push({
					x: cx,
					y: cy,
					r,
					color,
					key: `${s.key}|${rowIdx}`,
					label: multi ? `${s.label} — ${coord}` : coord,
					hl: isHighlighted(row),
					si,
					rowIdx
				});
			});
		});
		return out;
	});

	// ── Hover tooltip (client-only enhancement) ──────────────────────────────
	// SSR-inert: `mounted` starts false, so the static SVG is byte-identical with
	// or without JS. The pointer snaps to the nearest dot in 2D via nearestPoint,
	// and only within `hoverRadius` logical px so empty space pops no tooltip.
	const hoverRadius = 44;
	let svgEl: SVGSVGElement | undefined = $state();
	let mounted = $state(false);
	let hoverIdx = $state<number | null>(null);

	// Draw-in reveal: a client-only left-to-right clip wipe on mount (skipped under
	// prefers-reduced-motion). Never present in SSR markup — a pure enhancement.
	let revealed = $state(false);
	let animating = $state(false);
	const clipId = `chart-scatter-clip-${Math.random().toString(36).slice(2)}`;
	const clipActive = $derived(animate && mounted && animating);
	const PAD = 32; // clip padding so dots/bubbles near the plot edge aren't cut once revealed

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

	function onMove(e: PointerEvent) {
		if (!svgEl || dots.length === 0) return;
		const rect = svgEl.getBoundingClientRect();
		const lx = ((e.clientX - rect.left) / rect.width) * width;
		const ly = ((e.clientY - rect.top) / rect.height) * height;
		const k = nearestPoint(dots, lx, ly);
		if (k < 0) {
			hoverIdx = null;
			return;
		}
		const d = dots[k];
		const within = (d.x - lx) ** 2 + (d.y - ly) ** 2 <= hoverRadius ** 2;
		hoverIdx = within ? k : null;
	}
	function onLeave() {
		hoverIdx = null;
	}

	interface Hover {
		dot: Dot;
		leftPct: number;
		topPct: number;
		xValue: unknown;
		xLabel: string;
		points: TooltipPoint[];
		row: T; // the one source row this dot came from (passed to the tooltip snippet)
	}
	const hover = $derived.by<Hover | null>(() => {
		if (!mounted || hoverIdx === null) return null;
		const dot = dots[hoverIdx];
		if (!dot) return null;
		const s = shown[dot.si];
		const row = data[dot.rowIdx];
		if (!s || row === undefined) return null;
		const num = toNumber(valueOf(row, s.value));
		const idx = seriesList.findIndex((o) => o.key === s.key);
		const pts: TooltipPoint[] = [
			{
				key: s.key,
				label: s.label,
				value: Number.isNaN(num) ? null : num,
				formatted: Number.isNaN(num) ? '—' : fmtSeries(s, num),
				color: seriesColor(s.color, idx)
			}
		];
		return {
			dot,
			leftPct: (dot.x / width) * 100,
			topPct: (dot.y / height) * 100,
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
				<g class="dots">
					{#each dots as d (d.key)}
						<circle
							cx={d.x}
							cy={d.y}
							r={d.r}
							fill={d.color}
							class:hl={d.hl}
							class:dim={(hlActive && !d.hl) || (hover && hover.dot.key !== d.key)}
							aria-label={d.label}
						/>
					{/each}
				</g>
			</g>

			{#if hover}
				<line class="guide" x1={hover.dot.x} y1={plot.top} x2={hover.dot.x} y2={plot.bottom} />
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
	.dots circle {
		fill-opacity: 0.75;
		stroke: var(--chart-bg, transparent);
		stroke-width: 1;
		transition:
			opacity 0.15s ease,
			fill-opacity 0.15s ease;
	}
	/* Hover / selection: emphasise the focused dot, fade the rest. */
	.dots circle.dim {
		opacity: 0.28;
	}
	.dots circle.hl {
		fill-opacity: 1;
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
