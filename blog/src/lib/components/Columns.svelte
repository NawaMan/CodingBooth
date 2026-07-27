<!--
  Columns — a thin CSS-grid wrapper for 2–3 column and media/text split layouts.

  This is also the "Split": a split IS a Columns with unequal tracks, so there is
  one component rather than two that differ only in a default. `widths` sets the
  ratio; `columns` sets an even count.

    <Columns>                     two even columns
    <Columns columns={3}>         three even columns
    <Columns widths={[3, 2]}>     a 3:2 media/text split
    <Columns widths="360px 1fr">  a fixed rail beside a fluid column

  Usage:

    <script>
      import Columns from '$lib/components/Columns.svelte';
      import Column  from '$lib/components/Column.svelte';
    </script>

    <Columns widths={[3, 2]} align="center" divider>
      <Column><img src={shot} alt="" /></Column>
      <Column>The prose beside the picture.</Column>
    </Columns>

  Props:
    columns  — even track count (default 2). Ignored when `widths` yields tracks.
    widths   — the ratio: a number array (`[3, 2]` → `3fr 2fr`), a mixed array
               (`['360px', 1]`), or your own `grid-template-columns` string.
               Junk entries are dropped; if nothing survives, `columns` decides.
    gap      — gutter between columns (any CSS length). Omit to take the theme's
               `--columns-gap`.
    align    — block-axis alignment of the columns: 'stretch' (default) | 'start'
               | 'center' | 'end' | 'baseline'. A `<Column>` may override its own.
    divider  — hairline rules in the gutters (default false). Needs `<Column>`
               children; see the caveat below.
    resizable— let a VIEWER drag the gutters during the talk (default false). In
               ADJUST mode they are draggable regardless, `resizable` or not.
    minTrack — narrowest a track may be dragged, in canvas px (default 40).
    stack    — collapse to a single column, spans and rules included. The switch a
               slide flips when the same content wants stacking rather than splitting.
    style    — extra inline CSS appended to the group.

  Dragging a divider (see `resizable`):

  - `1fr` is a share of the space left over, so the *authored* widths can't be
    dragged — only the widths the browser resolved. Columns measures them from
    `getComputedStyle(...).gridTemplateColumns`, which is why the handles are
    client-only and never prerender.
  - A drag redistributes ONLY the two tracks the gutter separates; their sum is
    invariant, so the grid never resizes and no other divider moves.
  - It leaves the tracks as `fr` weights taken from the measured px. That is exact
    (an `fr` track gets its share of the free space, and the measured widths already
    sum to it), so nothing jumps on the first frame — but a track authored as a fixed
    `'360px'` rail comes out proportional. A drag is a RATIO editor.
  - **Nothing is saved.** Each slide is its own page load, so a drag is gone the
    moment you page away. In ADJUST mode a `widths` chip copies the dragged ratio to
    the clipboard, to paste back into source — the same bargain every ADJUST gesture
    makes. Double-click any divider to reset it to the authored widths.
  - A focused handle owns ←/→ (Shift for a bigger step). It is the only control in
    the deck that may: `NavigationBar` claims the arrows on `window` in the bubble
    phase, so stopping the event at a *focused* handle is both sufficient and
    scoped — the arrows page the deck again the instant focus leaves.

  Children get `min-width: 0` and the tracks are `minmax(0, 1fr)`, so a long URL or
  a wide <pre> scrolls or wraps inside its column instead of blowing the grid wider
  than the canvas — the one thing a naive grid gets wrong.

  It hugs its content in normal flow; wrap it in a <Block> to pin and size the whole
  group on a slide (Block fills its content, so the grid stretches to the box and a
  ADJUST-mode resize rubber-bands the columns).

  Two caveats, both consequences of CSS rather than choices:

  - `divider` draws the rule as each `<Column>`'s leading edge, so it assumes ONE
    row: more children than tracks wraps them, and the first child of the second row
    would carry a rule with no column to its left. `Columns` is a single row by
    definition — the same line StatGroup's dividers draw. It also means the rule is
    exactly as tall as the column carrying it: under the default `stretch` every
    column is the row's height and the rules are full-height, while `align="center"`
    (etc.) shrinks the columns to their content and the rules with them.
  - The narrow-window collapse is `text`-mode ONLY. A presentation is authored on a
    fixed 1920x1080 canvas that SlideDeck *transform-scales* to the window, so the
    canvas is 1920px wide no matter how small the window gets: a width media query
    would fire on the window and collapse a slide that never actually narrowed. A
    Text artifact has no canvas — its width really is the window's — so there the
    columns stack under 720px, which is the only place stacking is meaningful.
-->
<script lang="ts">
	import { onMount, setContext, tick } from 'svelte';
	import { writable } from 'svelte/store';
	import { getMode } from '$lib/presentation';
	import { canAdjust, adjustMode } from '$lib/stores/adjustMode';
	import { trackPointer } from '$lib/utils/drag';
	import {
		COLUMNS_CONTEXT,
		alignment,
		formatWidths,
		gutterCenters,
		parseGapPx,
		parseTrackPx,
		resizeTracks,
		trackCount,
		trackTemplate,
		weightsTemplate
	} from '$lib/utils/columnsCore';
	import type { Track } from '$lib/utils/columnsCore';

	/** Even track count. Ignored when `widths` yields tracks. */
	export let columns: number = 2;
	/** The ratio: `[3, 2]`, `['360px', 1]`, or a raw `grid-template-columns` string. */
	export let widths: string | Track[] | null = null;
	/** Gutter between columns (any CSS length). `''` → the theme's `--columns-gap`. */
	export let gap: string = '';
	/** Block-axis alignment of the columns; a `<Column>` may override its own. */
	export let align: string = 'stretch';
	/** Hairline rules in the gutters. Needs `<Column>` children. */
	export let divider: boolean = false;
	/** Collapse to a single column, spans and rules included. */
	export let stack: boolean = false;
	/** Let a VIEWER drag the gutters. ADJUST mode makes them draggable regardless. */
	export let resizable: boolean = false;
	/** Narrowest a track may be dragged, in canvas px. */
	export let minTrack: number = 40;
	/** Extra inline CSS appended to the group. */
	export let style: string = '';
	/** DOM id for the root element. */
	export let id: string = '';
	/** Extra class(es) for the root element. NOTE: a slide's own style block is scoped, so a
	    class defined there will NOT match — use global CSS (global.css / roles.css / a
	    :global(...) block) or a utility class. See AGENTS.md. */
	let klass: string = '';
	export { klass as class };

	// A Text artifact is fluid; a presentation is a transform-scaled fixed canvas.
	// Only the former may honour a width media query — see the header.
	const isText = getMode() === 'text';

	// A Column clamps its `span` against the track count and draws its own rule, so
	// both ride a store: the props are reactive, and context is set once at init.
	const shared = writable<{ count: number | null; divider: boolean }>({
		count: null,
		divider: false
	});
	setContext(COLUMNS_CONTEXT, shared);

	// ADJUST mode is an authoring aid, available only where the deck allows it;
	// canAdjust keeps a published deck inert even if a stale adjustMode lingers.
	$: editing = $canAdjust && $adjustMode;
	// One divider can't be dragged: there is nothing on the other side of it.
	$: grabbable = (resizable || editing) && !stack;

	// ── Drag state ────────────────────────────────────────────────────────────
	// `tracksPx` is what the browser resolved, measured; `dirty` says a gesture has
	// since overruled the authored template. Handles never prerender (`mounted`) —
	// a server-rendered grip is a control that controls nothing, and it would sit at
	// x=0 until the first measurement anyway.
	let el: HTMLDivElement;
	let mounted = false;
	let tracksPx: number[] = [];
	let gapPx = 0;
	let dirty = false;
	let dragging: number | null = null;
	let copied = false;

	$: template = stack ? 'minmax(0, 1fr)' : trackTemplate(columns, widths);
	$: count = stack ? 1 : trackCount(columns, widths);
	$: rules = divider && !stack;
	$: shared.set({ count, divider: rules });

	// A live handle draws its own rule, so the decorative ::before on each Column
	// must stand down or the gutter carries two lines. `--columns-rule` is inherited,
	// which is how it reaches into Column without a :global() selector.
	$: showHandles = grabbable && mounted && tracksPx.length > 1;
	$: applied = dirty ? weightsTemplate(tracksPx) || template : template;
	$: centers = showHandles ? gutterCenters(tracksPx, gapPx) : [];

	// An unrecognized alignment falls back to the default rather than emitting a
	// value the stylesheet doesn't know.
	$: alignItems = alignment(align, 'stretch');

	// Only emit a gap when the author set one, so the theme token keeps its say.
	$: vars =
		`--columns-tracks: ${applied}; --columns-align: ${alignItems};` +
		(gap ? ` --columns-gap: ${gap};` : '') +
		(showHandles && rules ? ' --columns-rule: none;' : '');

	/** Read the tracks the browser actually laid out. `1fr` is a share of the space
	    left over, so only the used values — which only the browser knows — can be
	    dragged. A measurement that doesn't parse leaves `tracksPx` alone, and with it
	    the authored template. */
	function measure() {
		if (!el) return;
		const computed = getComputedStyle(el);
		const next = parseTrackPx(computed.gridTemplateColumns);
		if (!next.length) return;
		// Re-measuring while dirty is expected (the Block around us was resized): the
		// fr weights hold the ratio, and this refreshes the px the handles sit at. The
		// tolerance stops a measure → template → relayout → measure loop on rounding.
		if (next.length !== tracksPx.length || next.some((w, i) => Math.abs(w - tracksPx[i]) > 0.5)) {
			tracksPx = next;
		}
		gapPx = parseGapPx(computed.columnGap);
	}

	onMount(() => {
		mounted = true;
		measure();

		// The grid resizes when the Block around it does — in ADJUST mode, constantly.
		if (typeof ResizeObserver === 'undefined') return;
		const ro = new ResizeObserver(() => measure());
		ro.observe(el);
		return () => ro.disconnect();
	});

	// Re-measure when the authored template changes under us, but never while a
	// gesture owns the tracks.
	$: if (mounted && template && !dirty) tick().then(measure);

	function startDrag(index: number, event: PointerEvent) {
		if (event.button !== 0) return;
		const start = tracksPx.slice();
		const wasDirty = dirty;
		dragging = index;

		// trackPointer divides the pointer delta by the element's LIVE rendered scale,
		// so the gutter tracks the cursor in FITTED and in SCALED at any zoom.
		trackPointer(event, {
			scaleFrom: el,
			onMove: (dx) => {
				tracksPx = resizeTracks(start, index, dx, minTrack);
				dirty = true;
			},
			onEnd: () => (dragging = null),
			onCancel: () => {
				tracksPx = start;
				dirty = wasDirty;
				dragging = null;
			}
		});
	}

	function onKeydown(index: number, event: KeyboardEvent) {
		if (event.key !== 'ArrowLeft' && event.key !== 'ArrowRight') return;
		// NavigationBar claims the arrows on `window`, in the BUBBLE phase — so a
		// FOCUSED handle can take them back simply by not letting them get there. This
		// is the one control in the deck that legitimately owns ←/→, and it can only do
		// it while focused, which is exactly when the presenter means to resize.
		event.preventDefault();
		event.stopPropagation();

		const step = (event.shiftKey ? 64 : 16) * (event.key === 'ArrowRight' ? 1 : -1);
		tracksPx = resizeTracks(tracksPx, index, step, minTrack);
		dirty = true;
	}

	/** Back to the authored `widths`. The escape hatch from a drag gone wrong — and,
	    live in a talk, from a slide someone else resized. */
	function reset() {
		dirty = false;
		tick().then(measure);
	}

	/** The share of its pair that the left track holds — a splitter's aria-valuenow. */
	function share(index: number): number {
		const total = tracksPx[index] + tracksPx[index + 1];
		return total > 0 ? Math.round((tracksPx[index] / total) * 100) : 50;
	}

	async function copyWidths() {
		const snippet = formatWidths(tracksPx);
		if (!snippet) return;
		try {
			await navigator.clipboard.writeText(snippet);
			copied = true;
			setTimeout(() => (copied = false), 1200);
		} catch {
			// Clipboard blocked (insecure context / permission) — same fallback Block uses.
			window.prompt('Copy this snippet:', snippet);
		}
	}
</script>

<div class="columns {klass}" class:text={isText} class:grabbable={showHandles} id={id || undefined} bind:this={el} style="{vars} {style}">
	<slot />

	{#each centers as center, i (i)}
		<!-- A focusable role=separator IS the ARIA window-splitter pattern, which the
		     linter doesn't recognise as interactive. It must NOT become a <button>: a
		     focused button swallows Space (spaceIntent stands down for one), and Space
		     is how the presenter advances the deck. pointerdown is stopped so a Block
		     wrapping us doesn't read the grab as the start of a move gesture. -->
		<!-- svelte-ignore a11y_no_noninteractive_tabindex -->
		<!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
		<div
			class="handle"
			class:ruled={rules}
			class:active={dragging === i}
			style="left: {center}px"
			role="separator"
			aria-orientation="vertical"
			aria-label="Resize columns {i + 1} and {i + 2}"
			aria-valuenow={share(i)}
			aria-valuemin="0"
			aria-valuemax="100"
			tabindex="0"
			on:pointerdown|stopPropagation={(e) => startDrag(i, e)}
			on:dblclick|stopPropagation={reset}
			on:keydown={(e) => onKeydown(i, e)}
		></div>
	{/each}

	{#if editing && mounted && tracksPx.length > 1}
		<button
			class="copy"
			type="button"
			on:pointerdown|stopPropagation
			on:click|stopPropagation={copyWidths}
		>
			{copied ? 'Copied' : 'widths'}
		</button>
	{/if}
</div>

<style>
	.columns {
		display: grid;
		grid-template-columns: var(--columns-tracks, minmax(0, 1fr) minmax(0, 1fr));
		align-items: var(--columns-align, stretch);
		gap: var(--columns-gap, 2em);
		box-sizing: border-box;
	}
	/* The containing block for the handles. They are absolutely positioned, so they
	   are OUT OF FLOW and never become grid items — the grid still sees only the
	   author's children. Applied only when there are handles, so a plain Columns
	   creates no stacking/positioning context it doesn't need. */
	.columns.grabbable {
		position: relative;
	}

	/* The blowout guard, applied to every child (not just <Column>): a grid item's
	   automatic minimum size is its min-content width, so one unbreakable token would
	   otherwise widen its track past its share of the grid. */
	.columns > :global(*) {
		min-width: 0;
	}

	/* Text mode only, and only once the window really is narrow: side-by-side prose
	   under ~720px is unreadable, and a Text artifact's width IS the window's. The
	   collapse must also undo what the columns were doing — the tracks, the spans a
	   <Column> set inline (hence !important: a stylesheet rule may beat an inline
	   declaration, an inherited custom property may not), and the gutter rules
	   (--columns-rule feeds the display of <Column>'s ::before, so it needs no
	   cross-component selector at all). */
	@media (max-width: 720px) {
		.columns.text {
			grid-template-columns: minmax(0, 1fr);
			--columns-rule: none;
		}
		.columns.text > :global(.gp-column) {
			--column-span: 1 !important;
		}
		/* Collapsed: there are no gutters, so the handles have nothing to sit in and
		   nothing to redistribute. (The measured `left` would also be stale.) */
		.columns.text .handle {
			display: none;
		}
	}

	/* ── The draggable divider ────────────────────────────────────────────────
	   A grab strip WIDER than the line it draws: the line is 1px, and nobody can
	   press a 1px target. The strip is invisible; the line inside it is the whole
	   visual. `touch-action: none` or the browser scrolls instead of dragging. */
	.handle {
		position: absolute;
		top: 0;
		bottom: 0;
		width: 14px;
		transform: translateX(-50%);
		cursor: col-resize;
		touch-action: none;
		background: none;
		border: 0;
		padding: 0;
	}

	/* The line itself. Hidden by default: with `divider` off, a resizable group has
	   no persistent rule — it advertises itself on hover and focus instead, which is
	   the same bargain WebSite's invisible shield makes. */
	.handle::before {
		content: '';
		position: absolute;
		top: 0;
		bottom: 0;
		left: 50%;
		width: 1px;
		transform: translateX(-50%);
		background: color-mix(in srgb, var(--columns-divider, #c0f1ff) 22%, transparent);
		opacity: 0;
		transition: opacity 120ms ease, width 120ms ease, background-color 120ms ease;
	}
	/* `divider` on → the rule is always drawn, and the Column's decorative ::before
	   has stood down (--columns-rule: none) so this is the only line in the gutter. */
	.handle.ruled::before {
		opacity: 1;
	}
	.handle:hover::before,
	.handle:focus-visible::before,
	.handle.active::before {
		opacity: 1;
		width: 3px;
		background: var(--columns-handle, #2980b9);
	}
	/* The strip is the target; the ring belongs on the line it draws. */
	.handle:focus {
		outline: none;
	}
	.handle:focus-visible::before {
		box-shadow: 0 0 0 2px color-mix(in srgb, var(--columns-handle, #2980b9) 35%, transparent);
	}

	/* ADJUST-mode Copy: the dragged ratio as a `widths={[…]}` you paste back into
	   source. Bottom-left, clear of Block's own Copy chip at the top. */
	.copy {
		position: absolute;
		left: 0;
		bottom: -1.9em;
		font-size: 0.62em;
		font-family: inherit;
		line-height: 1;
		padding: 0.35em 0.6em;
		border-radius: 4px;
		cursor: pointer;
		color: var(--ctrl-strong-fg, #ffffff);
		background: var(--ctrl-strong-bg, #2980b9);
		border: 1px solid var(--ctrl-strong-border, #2980b9);
	}

	/* A pointer-driven grip a touch reader can drag is fine; the hover-only reveal is
	   not, since there is no hover to reveal it with. Draw the line outright. */
	@media (hover: none) {
		.handle::before {
			opacity: 1;
		}
	}

	@media (prefers-reduced-motion: reduce) {
		.handle::before {
			transition: none;
		}
	}
</style>
