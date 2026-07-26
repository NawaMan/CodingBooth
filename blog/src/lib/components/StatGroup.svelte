<!--
  StatGroup — a row (or grid) of Stat tiles with shared spacing and dividers.

  Lays a set of <Stat>s in a responsive flex row that wraps, evenly spaced, with
  optional hairline dividers between them. It shares an alignment default with
  its Stats over context, so you set `align` once on the group instead of on
  every tile. Purely presentational — the Stats keep their own props.

  Usage:

    <script>
      import StatGroup from '$lib/components/StatGroup.svelte';
      import Stat      from '$lib/components/Stat.svelte';
    </script>

    <StatGroup>
      <Stat value="99.9%" label="Uptime"  trend="up"   delta="+0.4%" />
      <Stat value="42ms"  label="p95"     trend="down" delta="−12%"  />
      <Stat value="1.2M"  label="Req/day" accent />
    </StatGroup>

  Props:
    align    — 'center' (default) | 'start'. Inherited by child Stats that don't
               set their own `align`.
    dividers — draw hairline rules between tiles (default true). Suppressed when
               tiles wrap onto multiple rows would look odd, but kept simple: a
               left rule on every tile after the first.
    gap      — spacing between tiles (any CSS length; default '2.4em').
    columns  — fix the number of columns (switches to a grid). Omit for a
               free-flowing wrapping row.
    style    — extra inline CSS appended to the group.

  Like the other components it hugs its content in normal flow; wrap in a <Block>
  to pin/size the whole group on a slide.
-->
<script lang="ts">
	import { setContext } from 'svelte';

	/** Alignment inherited by child Stats that don't set their own. */
	export let align: 'center' | 'start' = 'center';
	/** Hairline rules between tiles. Applies to the wrapping row layout; a fixed
	    `columns` grid reads as a clean grid on its own, so dividers are skipped there. */
	export let dividers: boolean = true;
	/** Spacing between tiles (any CSS length). */
	export let gap: string = '2.4em';
	/** Fix the column count (grid). Omit for a wrapping row. */
	export let columns: number | null = null;
	/** Wrap the tiles in a raised panel (background + border + padding) so the row
	    lifts off the slide surface. Off by default — bare tiles suit most slides. */
	export let card: boolean = false;
	/** Extra inline CSS appended to the group. */
	export let style: string = '';
	/** DOM id for the root element. */
	export let id: string = '';
	/** Extra class(es) for the root element. NOTE: a slide's own style block is scoped, so a
	    class defined there will NOT match — use global CSS (global.css / roles.css / a
	    :global(...) block) or a utility class. See AGENTS.md. */
	let klass: string = '';
	export { klass as class };

	setContext('statGroupAlign', align);
</script>

<div
	class="stat-group {klass}"
	class:dividers
	class:card
	class:grid={columns != null}
	id={id || undefined}
	style="--stat-gap: {gap};{columns != null ? ` --stat-cols: ${columns};` : ''} {style}"
>
	<slot />
</div>

<style>
	.stat-group {
		display: flex;
		flex-wrap: wrap;
		align-items: stretch;
		justify-content: center;
		gap: var(--stat-gap, 2.4em);
		box-sizing: border-box;
	}
	/* Fixed-column mode: an even grid instead of a free-flowing row. */
	.stat-group.grid {
		display: grid;
		grid-template-columns: repeat(var(--stat-cols, 3), 1fr);
	}

	/* Card: a raised panel so the row reads as a distinct block on the surface. The
	   border is softened from the divider ink so it doesn't glare on a dark deck. */
	.stat-group.card {
		background: var(--stat-card-bg, #1e1e1e);
		border: 1px solid color-mix(in srgb, var(--stat-card-border, #c0f1ff) 30%, transparent);
		border-radius: 12px;
		padding: 1.4em 1.8em;
		box-shadow: 0 8px 28px color-mix(in srgb, var(--BACKDROP, #000000) 45%, transparent);
	}

	/* Divider (row mode only): a hairline left rule on every tile after the first,
	   sitting centred in the gutter. A fixed-column grid can't know its row breaks
	   in pure CSS, so it reads as a clean grid without rules. */
	.stat-group.dividers:not(.grid) > :global(.stat + .stat) {
		border-left: 1px solid color-mix(in srgb, var(--stat-divider, #c0f1ff) 22%, transparent);
		padding-left: var(--stat-gap, 2.4em);
		margin-left: calc(-1 * var(--stat-gap, 2.4em) / 2);
	}
</style>
