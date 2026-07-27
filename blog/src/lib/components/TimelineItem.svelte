<!--
  TimelineItem — one event on a Timeline's spine.

  A marker dot threaded on the spine, plus a time/phase label, a title, and a
  body (a `text` prop or the default slot, the same escape hatch Quote / Callout
  use). Each part is independent — omit any and the survivors close up, leaving no
  empty box (the ContentPage / Quote discipline). Pure CSS, purely declarative, so
  it prerenders.

  It learns its orientation and which side of the spine to sit on from the
  enclosing Timeline (over context); used on its own it defaults to a vertical
  spine on the left. The dot, time label and (optional) icon pull the accent; a
  per-item `color` retints just that event, so one milestone can stand out.

  Usage (inside a <Timeline>):

    <TimelineItem time="2021" title="Series A" icon="★" color="#f0a33e">
      Ten million users; the servers held.
    </TimelineItem>

    <TimelineItem time="Today" title="You are here" active
                  text="Shipping daily." />

  Props:
    time   — the date / phase label (a small accent line by the title).
    title  — the event heading.
    text   — the body. Omit to use the default slot instead.
    icon   — a glyph inside the marker (emoji or a character); enlarges the dot.
    color  — retint just this event's dot + time label (any CSS colour).
    active — highlight this event with a halo ring (e.g. "we are here now").
    style  — extra inline CSS appended to the item.
-->
<script lang="ts">
	import { getContext } from 'svelte';
	import type { Readable } from 'svelte/store';

	type Ctx = { orientation: 'vertical' | 'horizontal'; side: string };

	/** The date / phase label — a small line by the title. */
	export let time: string = '';
	/** The event heading. */
	export let title: string = '';
	/** The body; `''` falls through to the default slot. */
	export let text: string = '';
	/** A glyph inside the marker (emoji or character). Enlarges the dot. */
	export let icon: string = '';
	/** Retint just this event's dot + time label (any CSS colour). */
	export let color: string = '';
	/** Highlight this event with a halo ring. */
	export let active: boolean = false;
	/** Extra inline CSS appended to the item. */
	export let style: string = '';
	/** DOM id for the root element. */
	export let id: string = '';
	/** Extra class(es) for the root element. NOTE: a slide's own style block is scoped, so a
	    class defined there will NOT match — use global CSS (global.css / roles.css / a
	    :global(...) block) or a utility class. See AGENTS.md. */
	let klass: string = '';
	export { klass as class };

	// The Timeline shares orientation + side over context; standalone falls to a
	// vertical spine on the left ('right'). A store, since the parent's props are
	// reactive.
	const ctx = getContext<Readable<Ctx>>('timeline');
	$: orientation = ctx ? $ctx.orientation : 'vertical';
	$: side = ctx ? $ctx.side : 'right';

	$: colorVar = color ? `--tl-color: ${color};` : '';
</script>

<li
	class="item orient-{orientation} side-{side} {klass}"
	class:active
	class:has-icon={icon}
	id={id || undefined}
	style="{colorVar} {style}"
>
	<div class="marker" aria-hidden="true">
		<span class="dot">{#if icon}<span class="icon">{icon}</span>{/if}</span>
	</div>
	<div class="content">
		{#if time}<div class="time">{time}</div>{/if}
		{#if title}<div class="title">{title}</div>{/if}
		{#if text}<div class="body">{text}</div>{:else if $$slots.default}<div class="body"><slot /></div>{/if}
	</div>
</li>

<style>
	.item {
		box-sizing: border-box;
		min-width: 0;
	}

	/* ── Shared: the dot's look, the marker glyph, the halo, and the typography.
	   Only the dot's *position* is orientation-specific (set below); its size and
	   skin are one definition. The dot is pinned by its geometric centre (absolute
	   + translate(-50%,-50%)), so an icon-enlarged dot grows around the same point
	   and never shifts the spine or breaks the end-trim maths. */
	.dot {
		position: absolute;
		transform: translate(-50%, -50%);
		display: flex;
		align-items: center;
		justify-content: center;
		width: 0.85em;
		height: 0.85em;
		border-radius: 50%;
		background: var(--tl-color, var(--timeline-dot, #2980b9));
		/* A ring in the deck backdrop so the dot reads as a bead sitting on the
		   spine rather than a flat disc touching it. */
		box-shadow: 0 0 0 0.18em var(--page-bg, #000000);
	}
	.has-icon .dot {
		width: 1.7em;
		height: 1.7em;
		box-shadow:
			0 0 0 0.18em var(--page-bg, #000000),
			inset 0 0 0 0.12em color-mix(in srgb, var(--page-bg, #000000) 55%, transparent);
	}
	.icon {
		font-size: 0.9em;
		line-height: 1;
		color: var(--timeline-icon-fg, #ffffff);
	}
	/* Active: a soft halo so "you are here" reads at a glance without motion. */
	.active .dot {
		box-shadow:
			0 0 0 0.18em var(--page-bg, #000000),
			0 0 0 0.42em color-mix(in srgb, var(--tl-color, var(--timeline-dot, #2980b9)) 28%, transparent);
	}

	/* Time / phase kicker — small, accent, tracking a touch wide. */
	.time {
		font-size: 0.72em;
		font-weight: 700;
		letter-spacing: 0.04em;
		text-transform: uppercase;
		color: var(--tl-color, var(--timeline-time-fg, #2980b9));
		line-height: 1.2;
	}
	.title {
		font-size: 1.05em;
		font-weight: 700;
		color: var(--timeline-title-fg, #c0f1ff);
		line-height: 1.25;
		margin-top: 0.1em;
	}
	/* Body reads in the same ink as the title, dimmed — so it tracks the theme
	   instead of needing a separate (theme-fragile) muted token (Stat / Quote). */
	.body {
		font-size: 0.92em;
		color: var(--timeline-body-fg, #c0f1ff);
		opacity: 0.72;
		line-height: 1.4;
		margin-top: 0.15em;
	}
	.body :global(p:first-child) {
		margin-top: 0;
	}
	.body :global(p:last-child) {
		margin-bottom: 0;
	}

	/* ═══ VERTICAL ═══════════════════════════════════════════════════════════════
	   Each event is a two- or three-cell grid: the spine's marker column is fixed-
	   width so the dots line up across events whatever their content, and the
	   content sits in the remaining track. `side` swaps which track that is. The
	   height is the content's own, so events flow naturally. */
	.orient-vertical.item {
		display: grid;
		align-items: start;
		--tl-track: 2.4em; /* the fixed marker column */
		--tl-dot-center: 0.62em; /* the dot's centre, from the top of the event */
	}
	.orient-vertical.side-right {
		grid-template-columns: var(--tl-track) 1fr;
	}
	.orient-vertical.side-left {
		grid-template-columns: 1fr var(--tl-track);
	}
	.orient-vertical.side-left .marker {
		grid-column: 2;
	}
	.orient-vertical.side-left .content {
		grid-column: 1;
		grid-row: 1;
		text-align: right;
	}
	.orient-vertical.side-alternate {
		grid-template-columns: 1fr var(--tl-track) 1fr;
	}
	.orient-vertical.side-alternate .marker {
		grid-column: 2;
	}
	/* Odd events (1st, 3rd…) to the right of the spine; even ones to the left. */
	.orient-vertical.side-alternate .content {
		grid-column: 3;
		grid-row: 1;
	}
	.orient-vertical.side-alternate:nth-child(even) .content {
		grid-column: 1;
		text-align: right;
	}

	.orient-vertical .marker {
		position: relative;
		width: var(--tl-track);
		align-self: stretch;
	}
	/* The spine: a thin rule down the centre of the marker column, drawn behind the
	   dot and extended past the bottom by the list gap so it bridges into the next
	   event's segment as one continuous line. */
	.orient-vertical .marker::before {
		content: '';
		position: absolute;
		left: 50%;
		top: 0;
		bottom: calc(-1 * var(--timeline-gap, 1.6em));
		width: var(--tl-line-weight, 2px);
		transform: translateX(-50%);
		background: color-mix(in srgb, var(--timeline-line, #c0f1ff) 32%, transparent);
	}
	/* Trim the ends so the spine runs dot to dot, not past the first / last event. */
	.orient-vertical.item:first-child .marker::before {
		top: var(--tl-dot-center);
	}
	.orient-vertical.item:last-child .marker::before {
		bottom: auto;
		height: var(--tl-dot-center);
	}
	.orient-vertical.item:first-child:last-child .marker::before {
		display: none;
	}

	.orient-vertical .dot {
		left: 50%;
		top: var(--tl-dot-center);
	}

	.orient-vertical .content {
		padding: 0 0.2em 0 0.6em;
		min-width: 0;
	}
	.orient-vertical.side-left .content,
	.orient-vertical.side-alternate:nth-child(even) .content {
		padding: 0 0.6em 0 0.2em;
	}

	/* ═══ HORIZONTAL ═════════════════════════════════════════════════════════════
	   A fixed-height band with the spine at a constant vertical position, and the
	   dot + content absolutely placed off it. Absolute (not a per-item grid) is what
	   keeps the spine dead straight across the row even when events above and below
	   carry different amounts of text — a grid would let the taller content push its
	   dot out of line. */
	.orient-horizontal.item {
		position: relative;
		flex: 0 0 auto;
		width: var(--tl-item, 12em);
		height: 100%;
	}
	/* The spine's vertical position within the band, per side. */
	.orient-horizontal.side-below {
		--tl-spine-y: 1.5em;
	}
	.orient-horizontal.side-above {
		--tl-spine-y: calc(100% - 1.5em);
	}
	.orient-horizontal.side-alternate {
		--tl-spine-y: 50%;
	}

	.orient-horizontal .marker {
		position: absolute;
		inset: 0;
	}
	.orient-horizontal .marker::before {
		content: '';
		position: absolute;
		left: 0;
		right: calc(-1 * var(--timeline-gap, 1.6em));
		top: var(--tl-spine-y);
		height: var(--tl-line-weight, 2px);
		transform: translateY(-50%);
		background: color-mix(in srgb, var(--timeline-line, #c0f1ff) 32%, transparent);
	}
	/* Trim the ends so the spine runs dot to dot. */
	.orient-horizontal.item:first-child .marker::before {
		left: 50%;
	}
	.orient-horizontal.item:last-child .marker::before {
		right: 50%;
	}
	.orient-horizontal.item:first-child:last-child .marker::before {
		display: none;
	}

	.orient-horizontal .dot {
		left: 50%;
		top: var(--tl-spine-y);
	}

	.orient-horizontal .content {
		position: absolute;
		left: 0;
		right: 0;
		padding: 0 0.4em;
		text-align: center;
	}
	/* Content hangs just off the dot, below or above the spine. */
	.orient-horizontal.side-below .content,
	.orient-horizontal.side-alternate .content {
		top: calc(var(--tl-spine-y) + 0.9em);
	}
	.orient-horizontal.side-above .content,
	.orient-horizontal.side-alternate:nth-child(even) .content {
		top: auto;
		bottom: calc(100% - var(--tl-spine-y) + 0.9em);
	}
</style>
