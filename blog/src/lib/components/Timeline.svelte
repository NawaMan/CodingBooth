<!--
  Timeline — a narrative event spine (distinct from the chart family).

  A run of milestones threaded on a single line, vertical or horizontal: each
  event is a marker dot on the spine, a time/phase label, a title, and a body.
  The classic "2019 → founded · 2021 → Series A · today → you are here" roadmap
  slide. Pure CSS, no deps; the container half of a Timeline / TimelineItem pair,
  the same shape as StatGroup / Stat and Columns / Column.

  It owns nothing but the spine, its orientation and the side the content sits on:
  those are shared with the items over context, so you set them once on the
  Timeline instead of on every event. The items keep their own props.

  Every colour is a roles.css token (--timeline-*): the spine reads as a dim rule,
  the markers and the time label pull the accent, titles read in ink and bodies
  are ink dimmed — so a theme reskins the whole timeline by moving those.

  Usage:

    <script>
      import Timeline     from '$lib/components/Timeline.svelte';
      import TimelineItem from '$lib/components/TimelineItem.svelte';
    </script>

    <Timeline>
      <TimelineItem time="2019" title="Founded">Two people, one garage.</TimelineItem>
      <TimelineItem time="Today" title="You are here" active>Shipping daily.</TimelineItem>
    </Timeline>

    <Timeline orientation="horizontal" side="alternate">
      <TimelineItem time="v1.0" title="Launch" />
      <TimelineItem time="v2.0" title="Plugins" />
    </Timeline>

  A very long horizontal timeline pans nicely inside a <ScrollDiv axis="x">, since
  each event has a fixed width — give ScrollDiv an innerWidth of roughly
  events × itemWidth.

  Props:
    orientation — 'vertical' (default) — spine runs top-to-bottom; or
                  'horizontal' — spine runs left-to-right, events in a row.
    side  — where the content sits relative to the spine:
            vertical   → 'right' (default) | 'left' | 'alternate' (zig-zag);
            horizontal → 'below' (default) | 'above' | 'alternate'.
            The cross names alias sensibly ('left'≈'above', 'right'≈'below'), and
            an unknown value falls back to that orientation's default.
    gap   — space between events (any CSS length; default '1.6em'). The gutter the
            spine bridges: vertical space when vertical, horizontal when not.
    band  — horizontal only: the height of the event band (default '9em'). Content
            above/below the spine lives inside it; raise it for taller events.
    itemWidth — horizontal only: the width of each event (default '12em'). Fixed,
            so the dots space evenly and the whole thing pans cleanly in a ScrollDiv.
    style — extra inline CSS appended to the list.

  Like the other components it hugs its content in normal flow (a horizontal
  timeline is as wide as its events, as tall as `band`); wrap it in a <Block> to
  pin and size it, or a <ScrollDiv> to pan an over-long one.
-->
<script lang="ts">
	import { setContext } from 'svelte';
	import { writable } from 'svelte/store';

	type Orientation = 'vertical' | 'horizontal';
	type Side = 'right' | 'left' | 'above' | 'below' | 'alternate';
	type ResolvedSide = 'right' | 'left' | 'above' | 'below' | 'alternate';

	/** Spine direction: 'vertical' (top-to-bottom) or 'horizontal' (left-to-right). */
	export let orientation: Orientation = 'vertical';
	/** Which side of the spine the events sit on (orientation-dependent). */
	export let side: Side = 'right';
	/** Space between events (any CSS length) — the gutter the spine bridges. */
	export let gap: string = '1.6em';
	/** Horizontal only: the height of the event band. */
	export let band: string = '9em';
	/** Horizontal only: the width of each event (fixed, so dots space evenly). */
	export let itemWidth: string = '12em';
	/** Extra inline CSS appended to the list. */
	export let style: string = '';
	/** DOM id for the root element. */
	export let id: string = '';
	/** Extra class(es) for the root element. NOTE: a slide's own style block is scoped, so a
	    class defined there will NOT match — use global CSS (global.css / roles.css / a
	    :global(...) block) or a utility class. See AGENTS.md. */
	let klass: string = '';
	export { klass as class };

	$: resolvedOrientation = orientation === 'horizontal' ? 'horizontal' : 'vertical';

	// Resolve `side` into an orientation-appropriate value. 'alternate' passes
	// through; the two edge names alias across orientations (left≈above, right≈
	// below) so an author's habit reads sensibly either way; anything else — and any
	// cross-orientation name — falls back to that orientation's default rather than
	// emitting a class that matches nothing (ContentPage / Quote discipline).
	function resolveSide(o: string, s: string): ResolvedSide {
		if (s === 'alternate') return 'alternate';
		if (o === 'horizontal') return s === 'above' || s === 'left' ? 'above' : 'below';
		return s === 'left' || s === 'above' ? 'left' : 'right';
	}
	$: resolvedSide = resolveSide(resolvedOrientation, side);

	// The items read orientation + side from here (default vertical / 'right' when
	// used standalone), so each TimelineItem lays its marker + content out the same
	// way without the author repeating them on every event. A store, since the props
	// are reactive.
	const ctx = writable({ orientation: resolvedOrientation, side: resolvedSide });
	$: ctx.set({ orientation: resolvedOrientation, side: resolvedSide });
	setContext('timeline', ctx);
</script>

<ol
	class="timeline orient-{resolvedOrientation} side-{resolvedSide} {klass}"
	id={id || undefined}
	style="--timeline-gap: {gap}; --tl-band: {band}; --tl-item: {itemWidth}; {style}"
>
	<slot />
</ol>

<style>
	.timeline {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		gap: var(--timeline-gap, 1.6em);
		box-sizing: border-box;
		min-width: 0;
		color: var(--timeline-body-fg, #c0f1ff);
	}
	/* Vertical: events stack; the list is as tall as its content. */
	.orient-vertical {
		flex-direction: column;
	}
	/* Horizontal: events sit in a row of fixed-height band; the dots space evenly
	   because each item is a fixed width, which is also what lets an over-long one
	   pan cleanly inside a ScrollDiv. */
	.orient-horizontal {
		flex-direction: row;
		align-items: stretch;
		height: var(--tl-band, 9em);
		width: max-content;
	}
</style>
