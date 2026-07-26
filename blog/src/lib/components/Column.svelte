<!--
  Column — one cell of a <Columns> grid.

  A plain element is a perfectly good grid item, and <Columns> gives every child the
  blowout guard, so a Column is not required. It earns its place by knowing things a
  bare <div> cannot: how many tracks the group has (so a `span` can be clamped to
  them instead of silently growing the grid), and whether the group draws gutter
  rules (so the rule can be its own leading edge rather than a cross-component
  selector reaching into someone else's markup).

  Usage:

    <Columns columns={3} divider>
      <Column span={2}>The wide half.</Column>
      <Column align="center">The narrow one, vertically centred.</Column>
    </Columns>

  Props:
    span   — tracks to span (default 1). Clamped to the group's track count; a group
             built from a raw `grid-template-columns` string can't be counted, so
             there the number is trusted as written.
    align  — this column's block-axis alignment: 'stretch' | 'start' | 'center' |
             'end' | 'baseline'. Omit to inherit the group's `align`.
    style  — extra inline CSS appended to the column.

  Used outside a <Columns> it is an ordinary block: no span, no rule, no complaint.
-->
<script lang="ts">
	import { getContext } from 'svelte';
	import { readable } from 'svelte/store';
	import type { Readable } from 'svelte/store';
	import { COLUMNS_CONTEXT, alignment, clampSpan } from '$lib/utils/columnsCore';

	/** Tracks to span; clamped to the group's track count. */
	export let span: number = 1;
	/** Override the group's block-axis alignment for this column alone. */
	export let align: string | null = null;
	/** Extra inline CSS appended to the column. */
	export let style: string = '';
	/** DOM id for the root element. */
	export let id: string = '';
	/** Extra class(es) for the root element. NOTE: a slide's own style block is scoped, so a
	    class defined there will NOT match — use global CSS (global.css / roles.css / a
	    :global(...) block) or a utility class. See AGENTS.md. */
	let klass: string = '';
	export { klass as class };

	type Shared = { count: number | null; divider: boolean };
	// Outside a <Columns> there is no group: one track, no rule, no complaint.
	const shared: Readable<Shared> =
		getContext<Readable<Shared> | undefined>(COLUMNS_CONTEXT) ??
		readable({ count: 1, divider: false });

	$: tracks = clampSpan(span, $shared.count);
	// An unrecognized alignment inherits the group's rather than emitting a value the
	// stylesheet doesn't know. `align-self: auto` IS "whatever the group said".
	$: self = alignment(align, null);

	// Emit only what departs from the default, so a plain <Column> carries no style.
	$: vars =
		(tracks > 1 ? `--column-span: ${tracks};` : '') + (self ? ` --column-align: ${self};` : '');
</script>

<div class="gp-column {klass}" class:divided={$shared.divider} id={id || undefined} style="{vars} {style}">
	<slot />
</div>

<style>
	.gp-column {
		/* The anchor for the gutter rule below. */
		position: relative;
		box-sizing: border-box;
		/* Repeats <Columns>' guard, so a Column nested in someone else's grid keeps it. */
		min-width: 0;
		grid-column: span var(--column-span, 1);
		align-self: var(--column-align, auto);
	}

	/* The gutter rule is the column's own leading edge, centred in the gap — so it is
	   drawn once per gutter, never at the grid's outer edges, and it needs no selector
	   reaching across into <Columns>. `display` rides an inherited custom property
	   (rather than a rule in the parent) because inheritance ignores specificity:
	   that is how the text-mode collapse switches every rule off at once. */
	.gp-column.divided:not(:first-child)::before {
		content: '';
		display: var(--columns-rule, block);
		position: absolute;
		top: 0;
		bottom: 0;
		left: calc(var(--columns-gap, 2em) / -2);
		border-left: 1px solid color-mix(in srgb, var(--columns-divider, #c0f1ff) 22%, transparent);
	}
</style>
