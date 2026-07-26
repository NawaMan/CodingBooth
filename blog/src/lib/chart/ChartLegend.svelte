<!--
  ChartLegend — a swatch + label per series, each a real <button aria-pressed>
  that toggles the series' visibility. Shared by BarChart / LineChart (rendered
  when their `legend` prop is set) and usable standalone.

  Visibility is a Set<string> of hidden series keys, exposed via `bind:hidden`
  so a parent can drive or observe it (the bind:state philosophy from the
  DataTable). Toggling reassigns a fresh Set so the charts' $derived pipeline
  re-fits its scales — hiding the larger series re-scales the axis to the smaller.

  Server-safe: nothing here needs the DOM, so it prerenders with the chart.
  Accessible: aria-pressed reflects "series shown"; hidden series are visibly
  dimmed and struck through, not signalled by color alone.
-->
<script lang="ts" generics="T">
	import { seriesColor } from './chartCore';
	import type { SeriesDef } from './types';

	interface Props {
		series: SeriesDef<T>[];
		/** Hidden series keys — bindable so a parent can drive/observe visibility. */
		hidden?: Set<string>;
	}

	let { series, hidden = $bindable(new Set<string>()) }: Props = $props();

	function toggle(key: string) {
		// Reassign a new Set so the bound $derived scales recompute (mutating a Set
		// in place doesn't trip Svelte's reactivity).
		const next = new Set(hidden);
		if (next.has(key)) next.delete(key);
		else next.add(key);
		hidden = next;
	}
</script>

<ul class="legend" aria-label="Series">
	{#each series as s, i (s.key)}
		{@const isHidden = hidden.has(s.key)}
		<li>
			<button
				type="button"
				class="item"
				class:hidden={isHidden}
				aria-pressed={!isHidden}
				onclick={() => toggle(s.key)}
			>
				{#if s.mark === 'line'}
					<!-- line chip: a stroke with a node, so shape (not just color) reads -->
					<span class="swatch line" aria-hidden="true">
						<span class="line-bar" style:background={seriesColor(s.color, i)}></span>
						<span class="line-node" style:background={seriesColor(s.color, i)}></span>
					</span>
				{:else}
					<span class="swatch" style:background={seriesColor(s.color, i)} aria-hidden="true"></span>
				{/if}
				<span class="label">{s.label}</span>
			</button>
		</li>
	{/each}
</ul>

<style>
	.legend {
		display: flex;
		flex-wrap: wrap;
		gap: 0.15em 0.9em;
		justify-content: center;
		list-style: none;
		margin: 0.2em 0 0;
		padding: 0;
		font-size: var(--chart-font-size, 13px);
	}
	.legend li {
		margin: 0;
	}
	.item {
		display: inline-flex;
		align-items: center;
		gap: 0.4em;
		padding: 0.15em 0.35em;
		border: 0;
		border-radius: 5px;
		background: transparent;
		color: var(--chart-fg, currentColor);
		font: inherit;
		line-height: 1.2;
		cursor: pointer;
	}
	.item:hover {
		background: var(--chart-grid, color-mix(in srgb, currentColor 12%, transparent));
	}
	.item:focus-visible {
		outline: 2px solid var(--chart-axis, currentColor);
		outline-offset: 1px;
	}
	.swatch {
		width: 0.85em;
		height: 0.85em;
		border-radius: 2px;
		flex: none;
	}
	/* line chip: a horizontal stroke with a centered node */
	.swatch.line {
		position: relative;
		background: none;
		border-radius: 0;
		display: inline-flex;
		align-items: center;
		justify-content: center;
	}
	.swatch.line .line-bar {
		width: 100%;
		height: 2px;
		border-radius: 1px;
	}
	.swatch.line .line-node {
		position: absolute;
		width: 0.4em;
		height: 0.4em;
		border-radius: 50%;
	}
	.item.hidden {
		opacity: 0.5;
	}
	.item.hidden .label {
		text-decoration: line-through;
	}
	.item.hidden .swatch {
		/* dimmed AND desaturated, so hidden state doesn't rely on color alone */
		filter: grayscale(1);
		opacity: 0.6;
	}
</style>
