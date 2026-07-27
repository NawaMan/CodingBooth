<!--
  PieChart — a pie (or donut, via `innerRadius`) of one series' values, one slice
  per row. Slice angles come from each row's share of the visible total; the
  slice LABEL is the x accessor's value (x.format formats it). A slice smaller
  than `minSliceLabel` (a fraction of the whole) gets NO in-slice label so the
  centre doesn't turn to confetti — the legend and the hover tooltip still carry
  it, and its per-slice aria-label always states value + percentage.

  Only finite, positive values become slices: a blank / zero / negative row is
  skipped (a pie shows parts of a positive whole — it can't render "nothing" or
  "less than nothing"). Hiding a slice via the legend re-normalises the rest to
  100%.

  Wiring + SVG only; the arc geometry is the pure arcPath in chartCore.ts:

      data → finite positive values → cumulative angles → arc paths → SVG

  SSR-safe: the full <svg> renders from props alone (the hover tooltip mounts
  client-side only). Accessible: role="img" with a required `title` (→ <title>),
  optional `description` (→ <desc>) — and when a DataTable of the same data sits
  alongside (Phase 3 composition), that table is the accessible representation;
  say so in `description`. Theme via --chart-*.
-->
<script lang="ts" generics="T">
	import { onMount, type Snippet } from 'svelte';
	import ChartLegend from './ChartLegend.svelte';
	import ChartTooltip from './ChartTooltip.svelte';
	import { arcPath, keyString, seriesColor, toNumber, valueOf } from './chartCore';
	import type { Accessor, AxisDef, SeriesDef, TooltipPoint } from './types';

	interface Props {
		data: T[];
		/** The slice label: x.value names each slice, x.format formats it. */
		x: AxisDef<T>;
		/** One series — its `value` accessor is each slice's size. */
		series: SeriesDef<T>;
		/** Donut hole as a fraction (0–1) of the radius; 0 (default) = solid pie. */
		innerRadius?: number;
		/** Slices below this fraction of the whole get no in-slice label
		 *  (the legend and tooltip still name them). Default 0.04 (4%). */
		minSliceLabel?: number;
		/** Show a clickable legend listing every slice (toggles re-normalise). */
		legend?: boolean;
		/** Hidden slice keys — bindable so a parent can drive/observe them. */
		hidden?: Set<string>;
		/** Row keys (from `rowKeyAccessor`) to emphasise; every other slice dims —
		 *  the chart-side hook for a DataTable's `bind:selected`. */
		highlighted?: unknown[];
		/** How to read a row's key, matched against `highlighted`. */
		rowKeyAccessor?: Accessor<T>;
		width?: number;
		height?: number;
		/** Accessible name (SVG <title>) — required. */
		title: string;
		description?: string;
		/** Override the hover tooltip body; receives (xValue, points). */
		tooltip?: Snippet<[unknown, TooltipPoint[]]>;
	}

	let {
		data,
		x,
		series,
		innerRadius = 0,
		minSliceLabel = 0.04,
		legend = false,
		hidden = $bindable(new Set<string>()),
		highlighted,
		rowKeyAccessor,
		width = 640,
		height = 400,
		title,
		description,
		tooltip
	}: Props = $props();

	const TAU = Math.PI * 2;

	// Selection highlighting: with a non-empty `highlighted` list + a
	// `rowKeyAccessor`, matching slices are emphasised and the rest dim.
	const hlKeys = $derived(new Set((highlighted ?? []).map(keyString)));
	const hlActive = $derived(!!rowKeyAccessor && hlKeys.size > 0);
	const isHighlighted = (row: T): boolean =>
		hlActive && hlKeys.has(keyString(valueOf(row, rowKeyAccessor!)));

	// Stable per-slice key (mirrors bandScale/groupRows keying) so equal
	// categories/dates collapse and legend toggling has a stable handle.
	const keyOf = (value: unknown): string =>
		value instanceof Date
			? 'd:' + value.getTime()
			: value !== null && typeof value === 'object'
				? 'o:' + JSON.stringify(value)
				: 't:' + String(value);
	const catLabel = (cat: unknown): string =>
		cat === null || cat === undefined ? '' : x.format ? x.format(cat) : String(cat);
	const fmtValue = (v: number): string =>
		series.format ? series.format(v) : v.toLocaleString('en-US');

	// Geometry: centre the disc in the box; leave a small margin for label text.
	const cx = $derived(width / 2);
	const cy = $derived(height / 2);
	const radius = $derived(Math.max(0, Math.min(width, height) / 2 - 16));
	const innerR = $derived(radius * Math.min(Math.max(innerRadius, 0), 0.95));
	// In-slice labels ride the mid-radius (donut) or a little in from the edge (pie).
	const labelRadius = $derived(innerR > 0 ? (innerR + radius) / 2 : radius * 0.64);

	interface RawSlice {
		row: T;
		i: number; // original data index → stable palette color
		cat: unknown;
		key: string;
		value: number; // finite & > 0 for a real slice, else NaN/≤0
	}
	const rawSlices = $derived.by<RawSlice[]>(() =>
		data.map((row, i) => {
			const cat = valueOf(row, x.value);
			return { row, i, cat, key: keyOf(cat), value: toNumber(valueOf(row, series.value)) };
		})
	);
	// A "real" slice: finite, positive. Blank/zero/negative rows aren't parts of
	// the whole and get no wedge (and no legend entry).
	const drawable = $derived(rawSlices.filter((s) => Number.isFinite(s.value) && s.value > 0));
	const shown = $derived(drawable.filter((s) => !hidden.has(s.key)));
	const total = $derived(shown.reduce((sum, s) => sum + s.value, 0));

	interface Slice extends RawSlice {
		frac: number;
		start: number;
		end: number;
		mid: number;
		color: string;
		labelText: string;
		pct: number;
		d: string;
		lx: number;
		ly: number;
		aria: string;
		hl: boolean; // this slice's row is in the highlighted set
	}
	const slices = $derived.by<Slice[]>(() => {
		const out: Slice[] = [];
		let acc = 0;
		for (const s of shown) {
			const frac = total > 0 ? s.value / total : 0;
			const start = acc * TAU;
			acc += frac;
			const end = acc * TAU;
			const mid = (start + end) / 2;
			const color = seriesColor(undefined, s.i);
			const pct = Math.round(frac * 100);
			out.push({
				...s,
				frac,
				start,
				end,
				mid,
				color,
				pct,
				labelText: catLabel(s.cat),
				d: arcPath(cx, cy, radius, innerR, start, end),
				lx: cx + labelRadius * Math.sin(mid),
				ly: cy - labelRadius * Math.cos(mid),
				aria: `${catLabel(s.cat)}: ${fmtValue(s.value)} (${pct}%)`,
				hl: isHighlighted(s.row)
			});
		}
		return out;
	});

	// Legend lists every drawable slice (even sub-threshold ones), coloured to
	// match. Each entry's explicit `color` makes the swatch mirror its wedge.
	const legendSeries = $derived<SeriesDef<T>[]>(
		drawable.map((s) => ({
			key: s.key,
			label: catLabel(s.cat),
			value: series.value,
			color: seriesColor(undefined, s.i)
		}))
	);

	// ── Hover tooltip (client-only enhancement) ──────────────────────────────
	// SSR-inert: `mounted` starts false and hoverKey null, so the static SVG has
	// no tooltip. The pointer is mapped to a logical angle+radius and matched to
	// the slice it falls in (handler on the <svg>, mirroring the bar/line charts).
	let svgEl: SVGSVGElement | undefined = $state();
	let mounted = $state(false);
	let hoverKey = $state<string | null>(null);
	onMount(() => {
		mounted = true;
	});

	function onMove(e: PointerEvent) {
		if (!svgEl) return;
		const rect = svgEl.getBoundingClientRect();
		const lx = ((e.clientX - rect.left) / rect.width) * width;
		const ly = ((e.clientY - rect.top) / rect.height) * height;
		const dx = lx - cx;
		const dy = ly - cy;
		const dist = Math.hypot(dx, dy);
		if (dist > radius || dist < innerR) {
			hoverKey = null; // outside the ring / in the donut hole
			return;
		}
		// Angle measured clockwise from 12 o'clock, matching the slice geometry.
		let angle = Math.atan2(dx, -dy);
		if (angle < 0) angle += TAU;
		const hit = slices.find((s) => angle >= s.start && angle < s.end);
		hoverKey = hit ? hit.key : null;
	}

	interface Hover {
		leftPct: number;
		topPct: number;
		xLabel: string;
		xValue: unknown;
		points: TooltipPoint[];
	}
	const hover = $derived.by<Hover | null>(() => {
		if (!mounted || hoverKey === null) return null;
		const s = slices.find((sl) => sl.key === hoverKey);
		if (!s) return null;
		return {
			leftPct: (s.lx / width) * 100,
			topPct: (s.ly / height) * 100,
			xLabel: `${s.labelText} · ${s.pct}%`,
			xValue: s.cat,
			points: [
				{
					key: series.key,
					label: series.label,
					value: s.value,
					formatted: fmtValue(s.value),
					color: s.color
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
			onpointerleave={() => (hoverKey = null)}
		>
			<title>{title}</title>
			{#if description}<desc>{description}</desc>{/if}

			<g class="slices">
				{#each slices as s (s.key)}
					<path
						class="slice"
						class:hl={s.hl}
						class:dim={(hoverKey !== null && hoverKey !== s.key) || (hlActive && !s.hl)}
						d={s.d}
						fill={s.color}
						role="img"
						aria-label={s.aria}
					/>
				{/each}
			</g>

			<g class="labels" aria-hidden="true">
				{#each slices as s (s.key)}
					{#if s.frac >= minSliceLabel}
						<text
							class="slice-label"
							x={s.lx}
							y={s.ly}
							text-anchor="middle"
							dominant-baseline="middle">{s.labelText}</text
						>
					{/if}
				{/each}
			</g>
		</svg>

		{#if hover}
			<ChartTooltip
				xLabel={hover.xLabel}
				xValue={hover.xValue}
				points={hover.points}
				left={hover.leftPct}
				top={hover.topPct}
				{tooltip}
			/>
		{/if}
	</div>

	{#if legend}
		<ChartLegend series={legendSeries} bind:hidden />
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
	.slice {
		stroke: var(--chart-bg, #fff);
		stroke-width: 1.5;
		stroke-linejoin: round;
		transition: opacity 0.15s ease;
	}
	/* Dim the other slices while one is hovered or a selection is active. */
	.slice.dim {
		opacity: 0.42;
	}
	/* Selection highlight: a bold outline in the highlight colour. */
	.slice.hl {
		stroke: var(--chart-highlight, color-mix(in srgb, currentColor 85%, transparent));
		stroke-width: 2.5;
	}
	.slice-label {
		fill: var(--chart-slice-label, #fff);
		font-size: 0.95em;
		font-weight: 600;
		paint-order: stroke;
		pointer-events: none;
	}
</style>
