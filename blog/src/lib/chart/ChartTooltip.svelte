<!--
  ChartTooltip — the floating panel shown while hovering a chart: the hovered x
  value as a heading, then one row per visible series (swatch + label + its
  `format`-ted value). A `tooltip` snippet on the chart overrides the body,
  receiving (xValue, points, row) — `row` is the hovered source row when the chart
  can identify a single one. In this family's wide-format model a bar/line/area/
  combo hover snaps to exactly one row (its series are that row's columns) and a
  scatter hover is one dot = one row, so all of them forward `row`. It is
  `undefined` only for PieChart, whose slices come from an aggregated set.

  Purely presentational and positioned by the parent (left/top are percentages of
  the plot box). aria-hidden — this is pointer-transient; the accessible data is
  the series aria-labels and the paired DataTable (Phase 3). Rendered only while
  hovering, and only client-side, so it never appears in prerendered HTML and
  causes no layout shift (position: absolute, pointer-events: none).
-->
<script lang="ts" generics="T">
	import type { Snippet } from 'svelte';
	import type { TooltipPoint } from './types';

	interface Props {
		/** The hovered x value (already `format`-ted to a string by the chart). */
		xLabel: string;
		points: TooltipPoint[];
		/** left/top as percentages of the plot box (0–100). */
		left: number;
		top: number;
		/** Optional body override; receives the raw x value, the points, and (when
		 *  the chart can identify one) the hovered source row. */
		tooltip?: Snippet<[unknown, TooltipPoint[], T]>;
		xValue?: unknown;
		/** The hovered source row, forwarded to the `tooltip` snippet as its third
		 *  argument. Set by every chart whose hover maps to one row (bar/line/area/
		 *  combo/scatter); undefined for PieChart. */
		row?: T;
	}

	let { xLabel, points, left, top, tooltip, xValue, row }: Props = $props();
</script>

<div
	class="tooltip"
	class:flip={left > 60}
	style:left="{left}%"
	style:top="{top}%"
	aria-hidden="true"
>
	{#if tooltip}
		{@render tooltip(xValue, points, row as T)}
	{:else}
		<div class="x">{xLabel}</div>
		{#each points as p (p.key)}
			<div class="row">
				<span class="swatch" style:background={p.color}></span>
				<span class="label">{p.label}</span>
				<span class="val">{p.formatted}</span>
			</div>
		{/each}
	{/if}
</div>

<style>
	.tooltip {
		position: absolute;
		z-index: 2;
		transform: translate(0.6em, -50%);
		min-width: max-content;
		padding: 0.4em 0.6em;
		border-radius: 6px;
		/* Self-contained defaults: the tooltip renders in a div OUTSIDE the svg, so
		   it can't rely on the chart's --chart-fg/currentColor for contrast (that
		   inherits the surrounding page's text color and silently produces e.g. a
		   light box with light text on a dark deck). A fixed dark box + light text
		   is always legible; decks retint via --chart-tooltip-bg / --chart-tooltip-fg. */
		background: var(--chart-tooltip-bg, #1f2937);
		color: var(--chart-tooltip-fg, #f4f7fa);
		font-size: var(--chart-font-size, 13px);
		line-height: 1.35;
		box-shadow: 0 2px 10px rgba(0, 0, 0, 0.25);
		pointer-events: none;
		white-space: nowrap;
	}
	/* Flip to the left of the guide when near the right edge, so it stays in view. */
	.tooltip.flip {
		transform: translate(-100%, -50%) translateX(-0.6em);
	}
	.x {
		margin-bottom: 0.2em;
		font-weight: 600;
	}
	.row {
		display: flex;
		align-items: center;
		gap: 0.4em;
	}
	.swatch {
		width: 0.7em;
		height: 0.7em;
		border-radius: 2px;
		flex: none;
	}
	.label {
		opacity: 0.85;
	}
	.val {
		margin-left: auto;
		font-variant-numeric: tabular-nums;
		font-weight: 600;
	}
</style>
