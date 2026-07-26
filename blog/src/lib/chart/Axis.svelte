<!--
  Axis — renders one axis (x/bottom or y/left) from a scale: the axis line, tick
  marks, tick labels (via `format`), optional gridlines across the plot area, and
  an optional axis label. Pure presentation over a scale from chartCore.ts — it
  reads `ticks`/`domain` off the scale and places them, computing no data itself.

  Works with either scale kind: a LinearScale (ticks at each nice value) or a
  BandScale (one tick centered under each category). Theme via --chart-axis
  (lines), --chart-grid (gridlines), --chart-fg (text).
-->
<script lang="ts">
	import type { BandScale, LinearScale } from './types';

	interface Props {
		/** 'bottom' = horizontal x axis; 'left'/'right' = vertical y axis. */
		orientation: 'bottom' | 'left' | 'right';
		scale: LinearScale | BandScale;
		/** Plot-area rectangle in logical px (the axis frames this box). */
		left: number;
		right: number;
		top: number;
		bottom: number;
		format?: (value: unknown) => string;
		gridlines?: boolean;
		label?: string;
		/** Tint the axis line, ticks and labels (e.g. to match a series on a
		 *  dual-axis chart). Falls back to the neutral --chart-axis/--chart-fg. */
		color?: string;
	}

	let {
		orientation,
		scale,
		left,
		right,
		top,
		bottom,
		format,
		gridlines = false,
		label,
		color
	}: Props = $props();

	const isBand = $derived('bandwidth' in scale);
	const isBottom = $derived(orientation === 'bottom');
	const isRight = $derived(orientation === 'right');
	// The x pixel of a vertical axis: the plot's right edge for 'right', else left.
	const vx = $derived(isRight ? right : left);

	interface Tick {
		value: unknown;
		pos: number;
	}

	// Linear: a mark at every nice tick value. Band: one mark centered under each
	// category (map() gives the band start; add half a bandwidth).
	const ticks = $derived.by<Tick[]>(() => {
		if (isBand) {
			const s = scale as BandScale;
			return s.domain.map((value) => ({ value, pos: s.map(value) + s.bandwidth / 2 }));
		}
		const s = scale as LinearScale;
		return s.ticks.map((value) => ({ value, pos: s.map(value) }));
	});

	const text = (value: unknown): string =>
		format ? format(value) : value === null || value === undefined ? '' : String(value);
</script>

<g class="axis" class:tinted={color} style:--axis-color={color} aria-hidden="true">
	{#if gridlines}
		<g class="grid">
			{#each ticks as t (t.pos)}
				{#if isBottom}
					<line x1={t.pos} y1={top} x2={t.pos} y2={bottom} />
				{:else}
					<line x1={left} y1={t.pos} x2={right} y2={t.pos} />
				{/if}
			{/each}
		</g>
	{/if}

	<!-- axis line -->
	{#if isBottom}
		<line class="axis-line" x1={left} y1={bottom} x2={right} y2={bottom} />
	{:else}
		<line class="axis-line" x1={vx} y1={top} x2={vx} y2={bottom} />
	{/if}

	<g class="ticks">
		{#each ticks as t (t.pos)}
			{#if isBottom}
				<line class="tick" x1={t.pos} y1={bottom} x2={t.pos} y2={bottom + 6} />
				<text class="tick-label" x={t.pos} y={bottom + 9} text-anchor="middle" dominant-baseline="hanging">
					{text(t.value)}
				</text>
			{:else if isRight}
				<line class="tick" x1={vx} y1={t.pos} x2={vx + 6} y2={t.pos} />
				<text class="tick-label" x={vx + 9} y={t.pos} text-anchor="start" dominant-baseline="middle">
					{text(t.value)}
				</text>
			{:else}
				<line class="tick" x1={vx - 6} y1={t.pos} x2={vx} y2={t.pos} />
				<text class="tick-label" x={vx - 9} y={t.pos} text-anchor="end" dominant-baseline="middle">
					{text(t.value)}
				</text>
			{/if}
		{/each}
	</g>

	{#if label}
		{#if isBottom}
			<text class="axis-label" x={(left + right) / 2} y={bottom + 34} text-anchor="middle" dominant-baseline="hanging">
				{label}
			</text>
		{:else if isRight}
			<text
				class="axis-label"
				x={vx + 44}
				y={(top + bottom) / 2}
				text-anchor="middle"
				dominant-baseline="text-before-edge"
				transform="rotate(90 {vx + 44} {(top + bottom) / 2})"
			>
				{label}
			</text>
		{:else}
			<text
				class="axis-label"
				x={vx - 42}
				y={(top + bottom) / 2}
				text-anchor="middle"
				dominant-baseline="text-after-edge"
				transform="rotate(-90 {vx - 42} {(top + bottom) / 2})"
			>
				{label}
			</text>
		{/if}
	{/if}
</g>

<style>
	.axis-line,
	.tick {
		stroke: var(--chart-axis, color-mix(in srgb, currentColor 45%, transparent));
		stroke-width: 1;
	}
	.grid line {
		stroke: var(--chart-grid, color-mix(in srgb, currentColor 14%, transparent));
		stroke-width: 1;
		shape-rendering: crispEdges;
	}
	.tick-label,
	.axis-label {
		fill: var(--chart-fg, currentColor);
		font-size: 1em;
	}
	.axis-label {
		font-size: 1.05em;
		opacity: 0.85;
	}
	/* Dual-axis tint: colour the line, ticks and labels to match the series.
	   Gridlines above deliberately keep --chart-grid, staying neutral. */
	.tinted .axis-line,
	.tinted .tick {
		stroke: var(--axis-color);
	}
	.tinted .tick-label,
	.tinted .axis-label {
		fill: var(--axis-color);
	}
</style>
