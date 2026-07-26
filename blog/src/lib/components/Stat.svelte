<!--
  Stat — a single big-number / KPI tile.

  One hero figure with a label and an optional trend chip: the classic
  "99.9% uptime · ▲ +0.4%" metric you drop on a results slide. Pure CSS, no
  deps; pairs with the chart family (a Stat row above a chart, or standalone).

  The figure, label and trend colours are all driven by roles.css tokens
  (--stat-*), so a theme reskins every Stat by moving those. The trend chip
  colours itself from the direction: up → positive, down → negative, flat →
  neutral (override with `tone`).

  Usage:

    <script>
      import Stat from '$lib/components/Stat.svelte';
    </script>

    <Stat value="99.9%" label="Uptime" trend="up" delta="+0.4%" />
    <Stat value="1.2M"  label="Requests / day" accent />

  Props:
    value  — the hero figure (string or number). Required in practice.
    label  — what it measures, shown beneath the figure.
    sub    — optional secondary caption under the label (dim).
    trend  — 'up' | 'down' | 'flat' | null. Shows an arrow + `delta` chip.
    delta  — chip text (e.g. "+12%"). With `trend` set but no delta, just the arrow.
    tone   — chip/accent colour: 'auto' (up→positive, down→negative, flat→neutral),
             or force 'positive' | 'negative' | 'neutral'.
    accent — tint the hero figure with the accent token instead of ink.
    align  — 'center' (default) or 'start'. Inside a StatGroup this inherits the
             group's alignment unless set explicitly.
    style  — extra inline CSS appended to the tile.

  In normal flow the tile hugs its content. Wrap in a <Block> to pin/size it —
  Block fills its content by default, so the tile stretches to the box.
-->
<script lang="ts">
	import { getContext } from 'svelte';

	type Trend = 'up' | 'down' | 'flat';
	type Tone = 'auto' | 'positive' | 'negative' | 'neutral';

	/** The hero figure. */
	export let value: string | number = '';
	/** What the figure measures, shown beneath it. */
	export let label: string = '';
	/** Optional dim secondary caption under the label. */
	export let sub: string = '';
	/** Delta direction; renders an arrow + `delta` chip. `null` → no chip. */
	export let trend: Trend | null = null;
	/** Chip text (e.g. "+12%"). Omit to show just the arrow. */
	export let delta: string = '';
	/** Chip/accent colour. 'auto' derives from `trend`. */
	export let tone: Tone = 'auto';
	/** Tint the hero figure with the accent token instead of ink. */
	export let accent: boolean = false;
	/** Text alignment; `null` inherits the enclosing StatGroup (or 'center'). */
	export let align: 'center' | 'start' | null = null;
	/** Extra inline CSS appended to the tile. */
	export let style: string = '';
	/** DOM id for the root element. */
	export let id: string = '';
	/** Extra class(es) for the root element. NOTE: a slide's own style block is scoped, so a
	    class defined there will NOT match — use global CSS (global.css / roles.css / a
	    :global(...) block) or a utility class. See AGENTS.md. */
	let klass: string = '';
	export { klass as class };

	// A StatGroup shares its alignment default over context; standalone falls to center.
	const groupAlign = getContext<'center' | 'start' | undefined>('statGroupAlign');
	$: resolvedAlign = align ?? groupAlign ?? 'center';

	// 'auto' maps the arrow direction to a semantic colour; otherwise honour `tone`.
	const ARROWS: Record<Trend, string> = { up: '▲', down: '▼', flat: '→' };
	const AUTO_TONE: Record<Trend, Exclude<Tone, 'auto'>> = {
		up: 'positive',
		down: 'negative',
		flat: 'neutral',
	};
	$: resolvedTone = tone === 'auto' ? (trend ? AUTO_TONE[trend] : 'neutral') : tone;
</script>

<div
	class="stat align-{resolvedAlign} {klass}"
	id={id || undefined}
	style={style}
>
	<div class="figure-row">
		<div class="figure" class:accent>{value}</div>
		{#if trend}
			<div class="chip tone-{resolvedTone}">
				<span class="arrow" aria-hidden="true">{ARROWS[trend]}</span>{#if delta}<span class="delta">{delta}</span>{/if}
			</div>
		{/if}
	</div>
	{#if label}
		<div class="label">{label}</div>
	{/if}
	{#if sub}
		<div class="sub">{sub}</div>
	{/if}
</div>

<style>
	.stat {
		display: flex;
		flex-direction: column;
		gap: 0.15em;
		box-sizing: border-box;
		min-width: 0;
	}
	.align-center {
		align-items: center;
		text-align: center;
	}
	.align-start {
		align-items: flex-start;
		text-align: left;
	}

	/* The figure and its chip sit on one baseline-ish row. */
	.figure-row {
		display: flex;
		align-items: baseline;
		gap: 0.4em;
		flex-wrap: wrap;
	}
	.align-center .figure-row {
		justify-content: center;
	}

	.figure {
		font-size: 3.2em;
		font-weight: 800;
		line-height: 1;
		letter-spacing: -0.02em;
		color: var(--stat-value-fg, #c0f1ff);
		/* Lining figures keep columns of numbers aligned. */
		font-variant-numeric: tabular-nums lining-nums;
	}
	.figure.accent {
		color: var(--stat-accent, #2980b9);
	}

	/* Label/sub are the same ink as the figure, just dimmed — so they track the
	   theme instead of needing a separate (theme-fragile) "dim ink" token. */
	.label {
		font-size: 1em;
		font-weight: 600;
		color: var(--stat-label-fg, #c0f1ff);
		opacity: 0.82;
	}
	.sub {
		font-size: 0.82em;
		color: var(--stat-label-fg, #c0f1ff);
		opacity: 0.58;
	}

	/* Trend chip — tinted background + border from a single tone colour (color-mix),
	   same self-tinting trick as Callout so a theme only moves the tone token. */
	.chip {
		display: inline-flex;
		align-items: center;
		gap: 0.2em;
		font-size: 0.82em;
		font-weight: 700;
		line-height: 1;
		padding: 0.25em 0.5em;
		border-radius: 999px;
		white-space: nowrap;
		color: var(--chip-tone, #555555);
		background: color-mix(in srgb, var(--chip-tone, #555555) 16%, transparent);
	}
	.tone-positive {
		--chip-tone: var(--stat-positive, #00b356);
	}
	.tone-negative {
		--chip-tone: var(--stat-negative, #e5484d);
	}
	.tone-neutral {
		--chip-tone: var(--stat-label-fg, #555555);
	}
	.arrow {
		font-size: 0.9em;
	}
</style>
