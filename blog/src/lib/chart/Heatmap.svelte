<!--
  Heatmap — the 2-D DISTRIBUTION chart: a matrix of cells, one per
  (column category × row category), each tinted by its value along a sequential
  colour ramp. The counterpart to the Histogram (a 1-D distribution) and to
  BarChart's categorical bars; here BOTH axes are categorical bands and the third
  dimension is the cell's colour.

  All the pivoting is pure in chartCore.ts (`heatmapMatrix`): rows are bucketed
  into the distinct x/y categories (first-seen order), rows sharing a cell are
  AVERAGED (blanks excluded, never zeroed), and each cell's value is normalised to
  t ∈ [0,1] across the colour-scale domain. A cell with no measurement is blank
  (drawn empty, not as the low-end colour). The component only wires the matrix →
  scales → rects → SVG:

      data → heatmapMatrix → band-x (columns) + band-y (rows) → coloured rects

  The colour is a `color-mix` between two theme tokens (`--chart-heat-low` →
  `--chart-heat-high`) at the cell's `t` — so the ramp is themeable per deck and
  needs no continuous palette baked in. `color-mix(in oklab, …)` keeps the steps
  perceptually even.

  SSR-safe: the full <svg> renders from props alone; the hover tooltip + the
  animate wipe are client-only and never reach the prerender (exactly as in the
  other charts). Accessible: role="img" with a required `title`, and one
  aria-label per cell ("Mon × 09:00: 42" / "… : no data"). A static gradient
  legend maps colour back to value.
-->
<script lang="ts" generics="T">
	import { onMount, type Snippet } from 'svelte';
	import Axis from './Axis.svelte';
	import ChartTooltip from './ChartTooltip.svelte';
	import { bandScale, heatmapMatrix, nearestPoint } from './chartCore';
	import type { Accessor, TooltipPoint } from './types';

	interface Props {
		data: T[];
		/** The column category (field name or accessor) — the x axis. */
		x: Accessor<T>;
		/** The row category (field name or accessor) — the y axis. */
		y: Accessor<T>;
		/** The numeric field that colours each cell. Blanks leave a cell empty. */
		value: Accessor<T>;
		/** Clamp the colour scale to [min, max]; values still render, t clamps. */
		domain?: [number, number];
		width?: number;
		height?: number;
		/** Accessible name (SVG <title>) — required. */
		title: string;
		description?: string;
		/** X-axis (column) caption. */
		xLabel?: string;
		/** Y-axis (row) caption. */
		yLabel?: string;
		/** Format a cell's value for its aria-label, tooltip and the legend ends. */
		format?: (value: number) => string;
		/** Format a column category for its axis tick + aria-label. Default: String. */
		xFormat?: (value: unknown) => string;
		/** Format a row category for its axis tick + aria-label. Default: String. */
		yFormat?: (value: unknown) => string;
		/** Visual gap between cells, in logical px (insets each rect; the grid
		 *  itself is contiguous). */
		gap?: number;
		/** Print each cell's value inside it (only legible on a small matrix). */
		showValues?: boolean;
		/** Draw the colour-ramp legend below the plot. */
		legend?: boolean;
		/** Play a one-off left-to-right reveal on mount (client-only, skipped under
		 *  prefers-reduced-motion). Duration via --chart-animate-ms. */
		animate?: boolean;
		/** Override the hover tooltip body; receives (cellLabel, points, undefined). */
		tooltip?: Snippet<[unknown, TooltipPoint[], undefined]>;
	}

	let {
		data,
		x,
		y,
		value,
		domain,
		width = 640,
		height = 400,
		title,
		description,
		xLabel,
		yLabel,
		format,
		xFormat,
		yFormat,
		gap = 1,
		showValues = false,
		legend = true,
		animate = false,
		tooltip
	}: Props = $props();

	// Fallback ramp ends (ColorBrewer "Blues"-ish) behind the theme tokens — a
	// heatmap still reads if the deck sets no --chart-heat-* vars.
	const LOW = '#e8f1fb';
	const HIGH = '#08519c';
	const EMPTY = 'rgba(120, 140, 160, 0.12)';
	const rampLow = 'var(--chart-heat-low, ' + LOW + ')';
	const rampHigh = 'var(--chart-heat-high, ' + HIGH + ')';
	const rampEmpty = 'var(--chart-heat-empty, ' + EMPTY + ')';

	// The pivoted matrix — pure, in chartCore. Full grid, row-major.
	const matrix = $derived(heatmapMatrix(data, { x, y, value, domain }));

	const margin = $derived({
		top: 18,
		right: 18,
		bottom: 40 + (xLabel ? 22 : 0),
		left: 64 + (yLabel ? 22 : 0)
	});
	const plot = $derived({
		left: margin.left,
		right: width - margin.right,
		top: margin.top,
		bottom: height - margin.bottom
	});

	// Both axes are categorical bands. Padding 0 → the cells tile the plot area
	// edge-to-edge; `gap` insets each rect so neighbours read apart.
	const xScale = $derived(
		bandScale(matrix.xs, [plot.left, plot.right], { paddingInner: 0, paddingOuter: 0 })
	);
	const yScale = $derived(
		bandScale(matrix.ys, [plot.top, plot.bottom], { paddingInner: 0, paddingOuter: 0 })
	);

	const fmtValue = (v: number): string =>
		format ? format(v) : Number.isFinite(v) ? v.toLocaleString('en-US') : String(v);
	const fmtX = (v: unknown): string => (xFormat ? xFormat(v) : v == null ? '' : String(v));
	const fmtY = (v: unknown): string => (yFormat ? yFormat(v) : v == null ? '' : String(v));

	// The cell fill: a color-mix along the ramp at the cell's t (blank → empty).
	const cellFill = (t: number): string =>
		Number.isFinite(t)
			? `color-mix(in oklab, ${rampHigh} ${(t * 100).toFixed(1)}%, ${rampLow})`
			: rampEmpty;

	interface Rect {
		x: number;
		y: number;
		width: number;
		height: number;
		cx: number;
		cy: number;
		fill: string;
		empty: boolean;
		raw: number | null;
		valueText: string;
		header: string;
		label: string;
		dark: boolean;
		key: string;
	}

	// One rect per cell (blank cells included, drawn empty — the matrix stays whole).
	const rects = $derived.by<Rect[]>(() => {
		const out: Rect[] = [];
		for (const cell of matrix.cells) {
			const bx = xScale.map(cell.x);
			const by = yScale.map(cell.y);
			if (Number.isNaN(bx) || Number.isNaN(by)) continue;
			const empty = cell.value === null;
			const valueText = empty ? '' : fmtValue(cell.value as number);
			const header = `${fmtX(cell.x)} × ${fmtY(cell.y)}`;
			const label = `${header}: ${empty ? 'no data' : valueText}`;
			out.push({
				x: bx + gap / 2,
				y: by + gap / 2,
				width: Math.max(0, xScale.bandwidth - gap),
				height: Math.max(0, yScale.bandwidth - gap),
				cx: bx + xScale.bandwidth / 2,
				cy: by + yScale.bandwidth / 2,
				fill: cellFill(cell.t),
				empty,
				raw: cell.value,
				valueText,
				header,
				// A cell past the ramp's midpoint carries dark ink; below it, light.
				dark: Number.isFinite(cell.t) && cell.t > 0.55,
				label,
				key: `${cell.col}-${cell.row}`
			});
		}
		return out;
	});

	// ── Hover tooltip (client-only enhancement) ──────────────────────────────
	// SSR-inert: `mounted` starts false, so the static SVG is byte-identical with
	// or without JS. The pointer snaps to the nearest cell centre (2-D, nearestPoint).
	let svgEl: SVGSVGElement | undefined = $state();
	let mounted = $state(false);
	let hoverIdx = $state<number | null>(null);

	// Draw-in reveal: a client-only left-to-right clip wipe on mount (as Histogram).
	let revealed = $state(false);
	let animating = $state(false);
	const clipId = `chart-heat-clip-${Math.random().toString(36).slice(2)}`;
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

	function onMove(e: PointerEvent) {
		if (!svgEl || rects.length === 0) return;
		const box = svgEl.getBoundingClientRect();
		const lx = ((e.clientX - box.left) / box.width) * width;
		const ly = ((e.clientY - box.top) / box.height) * height;
		const k = nearestPoint(
			rects.map((r) => ({ x: r.cx, y: r.cy })),
			lx,
			ly
		);
		// Only report a hit if the pointer is actually over the plot cells.
		hoverIdx = k < 0 || lx < plot.left || lx > plot.right || ly < plot.top || ly > plot.bottom ? null : k;
	}
	function onLeave() {
		hoverIdx = null;
	}

	interface Hover {
		rect: Rect;
		leftPct: number;
		topPct: number;
		points: TooltipPoint[];
	}
	const hover = $derived.by<Hover | null>(() => {
		if (!mounted || hoverIdx === null) return null;
		const r = rects[hoverIdx];
		if (r === undefined) return null;
		return {
			rect: r,
			leftPct: (r.cx / width) * 100,
			topPct: (r.y / height) * 100,
			points: [
				{
					key: 'value',
					label: 'Value',
					value: r.raw,
					formatted: r.empty ? '—' : r.valueText,
					color: r.empty ? rampEmpty : r.fill
				}
			]
		};
	});

	// ── Static colour-ramp legend ────────────────────────────────────────────
	const hasScale = $derived(Number.isFinite(matrix.min) && Number.isFinite(matrix.max));
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

			<g class="marks" clip-path={clipActive ? `url(#${clipId})` : undefined}>
				<g class="cells">
					{#each rects as r (r.key)}
						<rect
							x={r.x}
							y={r.y}
							width={r.width}
							height={r.height}
							fill={r.fill}
							class:empty={r.empty}
							aria-label={r.label}
						/>
						{#if showValues && !r.empty}
							<text
								class="cell-value"
								class:dark={r.dark}
								x={r.cx}
								y={r.cy}
								text-anchor="middle"
								dominant-baseline="central"
								aria-hidden="true"
							>
								{r.valueText}
							</text>
						{/if}
					{/each}
				</g>
			</g>

			{#if hover}
				<rect
					class="cell-focus"
					x={hover.rect.x}
					y={hover.rect.y}
					width={hover.rect.width}
					height={hover.rect.height}
				/>
			{/if}

			<Axis
				orientation="left"
				scale={yScale}
				left={plot.left}
				right={plot.right}
				top={plot.top}
				bottom={plot.bottom}
				format={fmtY}
				label={yLabel}
			/>
			<Axis
				orientation="bottom"
				scale={xScale}
				left={plot.left}
				right={plot.right}
				top={plot.top}
				bottom={plot.bottom}
				format={fmtX}
				label={xLabel}
			/>
		</svg>

		{#if hover}
			<ChartTooltip
				xLabel={hover.rect.header}
				points={hover.points}
				left={hover.leftPct}
				top={hover.topPct}
				{tooltip}
			/>
		{/if}
	</div>

	{#if legend && hasScale}
		<div class="legend" aria-hidden="true">
			<span class="legend-end">{fmtValue(matrix.min)}</span>
			<span class="ramp"></span>
			<span class="legend-end">{fmtValue(matrix.max)}</span>
		</div>
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
	.cells rect {
		transition: opacity 0.15s ease;
		stroke: var(--chart-heat-grid, color-mix(in srgb, currentColor 10%, transparent));
		stroke-width: 0.5;
		shape-rendering: crispEdges;
	}
	.cells rect.empty {
		stroke: none;
	}
	.cell-value {
		font-size: 0.85em;
		pointer-events: none;
	}
	/* On a dark (high-value) cell the ink flips to the ramp's LIGHT end; on a
	   light (low-value) cell it takes the ramp's DARK end — so the number stays
	   legible whatever the fill. */
	.cell-value.dark {
		fill: var(--chart-heat-low, #e8f1fb);
	}
	.cell-value:not(.dark) {
		fill: var(--chart-heat-high, #08519c);
	}
	.cell-focus {
		fill: none;
		stroke: var(--chart-fg, currentColor);
		stroke-width: 2;
		pointer-events: none;
	}
	.legend {
		display: flex;
		align-items: center;
		gap: 0.5em;
		margin: 0.5em auto 0;
		width: max-content;
		max-width: 100%;
		color: var(--chart-fg, currentColor);
		font-size: var(--chart-font-size, 13px);
	}
	.legend-end {
		font-variant-numeric: tabular-nums;
		opacity: 0.85;
	}
	.ramp {
		display: block;
		width: 160px;
		max-width: 40vw;
		height: 0.7em;
		border-radius: 3px;
		background: linear-gradient(
			in oklab to right,
			var(--chart-heat-low, #e8f1fb),
			var(--chart-heat-high, #08519c)
		);
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
