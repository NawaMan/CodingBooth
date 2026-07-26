<!--
  DrawHandle — internal point-handle primitive for ADJUST-mode shape editing.
  Not part of the public API.

  An SVG knob bound to a Point in canvas units (it scales with the deck,
  exactly like Block's chrome) and draggable via the shared trackPointer
  helper: grid snapping, Shift to lock the drag to H/V from the grab point,
  Esc-cancel restoring the drag's start point, and a commit callback that
  fires only when the point actually moved (the caller records undo/redo).

  Screen→canvas scale: SVG elements have no offsetWidth, so the scale is the
  owner svg's rendered width ÷ the canvas width from Draw's context.

  Styled like the existing grips: --ctrl-strong-bg knob with an --on-accent
  ring; `kind="control"` is the hollow variant for Bézier control points,
  `kind="bend"` the accent variant for the arc's apex handle.
-->
<script lang="ts">
	import { getContext } from 'svelte';
	import { trackPointer } from '$lib/utils/drag';
	import { snapToAngles } from './drawCore';
	import { DRAW_CONTEXT_KEY, type DrawContext, type Point } from './types';

	interface Props {
		point: Point;
		/** Snap step in canvas px while dragging (1 = freeform). */
		grid?: number;
		kind?: 'point' | 'control' | 'bend';
		/** Whether the owning shape is selected. Unselected shapes show smaller,
		 *  quieter connectors so the selected shape's handles stand out (and the
		 *  surface reads less cluttered when several shapes are editable at once).
		 *  Defaults true, so callers that only render handles once selected keep
		 *  full-size knobs. */
		selected?: boolean;
		/** For a keyframe-stop connector: this stop's percent on the timeline, and
		 *  the live playhead percent. When both are given the knob reads the
		 *  timeline: stops BEFORE the playhead (exclusive) are dashed, the stop AT
		 *  or AFTER it solid, and the ring thickens the closer the stop sits to the
		 *  playhead. Omitted for plain (non-animated) endpoint handles. */
		pct?: number | null;
		playhead?: number | null;
		/** Tooltip (SVG <title>). */
		title?: string;
		/** Live position during the drag. */
		onmove: (p: Point) => void;
		/** Gesture committed with a net change — record undo/redo here. */
		oncommit?: (before: Point, after: Point) => void;
		/** Pointer went down on the handle — select the owning shape. */
		onselect?: () => void;
	}

	let {
		point,
		grid = 1,
		kind = 'point',
		title,
		onmove,
		oncommit,
		onselect,
		selected = true,
		pct = null,
		playhead = null
	}: Props = $props();

	const ctx = getContext<DrawContext | undefined>(DRAW_CONTEXT_KEY);
	let el = $state<SVGCircleElement>();

	// Full knob when the shape is selected; HALF size when it isn't, so an
	// unselected shape's connectors stay visible/grabbable without shouting.
	const r = $derived((kind === 'control' ? 8 : 10) * (selected ? 1 : 0.5));

	// Timeline-aware styling for keyframe-stop handles (pct + live playhead).
	const timeline = $derived(typeof pct === 'number' && typeof playhead === 'number');
	// BEFORE the playhead (exclusive) = already passed = dashed; AT/AFTER = solid.
	const before = $derived(timeline && (pct as number) < (playhead as number));
	// Bolder the closer this stop sits to the playhead: 1px when ≥50% away, then
	// +1px per 10% closer (capped at 6px right on the playhead).
	const dist = $derived(timeline ? Math.abs((pct as number) - (playhead as number)) : 0);
	const tlWidth = $derived(Math.max(1, Math.min(6, 6 - Math.floor(dist / 10))));
	// Inline style wins over the class rules, so timeline handles override both
	// the default and the `.quiet` stroke width / dash.
	const tlStyle = $derived(
		timeline ? `stroke-width:${tlWidth}px; stroke-dasharray:${before ? '3 3' : 'none'};` : ''
	);

	const snap = (n: number) => (grid > 1 ? Math.round(n / grid) * grid : Math.round(n));

	function start(event: PointerEvent) {
		event.preventDefault();
		event.stopPropagation();
		// Hold Draw's select-to-front hoist for the length of the gesture BEFORE
		// selecting: on an unselected shape, onselect() would otherwise re-parent
		// this very knob into the top chrome layer mid-press, destroying the node
		// trackPointer is about to capture the pointer on. See DrawContext.
		ctx?.beginGesture?.();
		onselect?.();
		const [sx, sy] = point;
		let current: Point = [sx, sy];
		trackPointer(event, {
			scaleFrom: () => {
				const svg = el?.ownerSVGElement;
				if (!svg || !ctx) return 1;
				return svg.getBoundingClientRect().width / ctx.width || 1;
			},
			onMove: (dx, dy, e) => {
				let p: Point = [snap(sx + dx), snap(sy + dy)];
				// Shift locks the point to a single axis from the GRAB point — X or Y,
				// whichever the pointer moved further (the same feel as Block's Shift).
				// snapToAngles' default 90° detents project onto that axis. Deliberately
				// relative to the grab point, NOT the shape's other end: a near-horizontal
				// line's endpoint must still be draggable straight up/down.
				if (e.shiftKey) p = snapToAngles(p, [sx, sy]);
				current = p;
				onmove(p);
			},
			onEnd: () => {
				// trackPointer has already torn its listeners down and released the
				// capture, so the hoist that lands here can safely re-home this knob.
				ctx?.endGesture?.();
				if (current[0] === sx && current[1] === sy) return;
				oncommit?.([sx, sy], current);
			},
			onCancel: () => {
				ctx?.endGesture?.();
				onmove([sx, sy]);
			}
		});
	}
</script>

<!-- svelte-ignore a11y_no_static_element_interactions -->
<circle
	bind:this={el}
	class="draw-handle {kind}"
	class:quiet={!selected}
	cx={point[0]}
	cy={point[1]}
	{r}
	style={tlStyle}
	onpointerdown={start}
>
	{#if title}<title>{title}</title>{/if}
</circle>

<style>
	/* The surface is pointer-events:none; handles re-enable it — the ONLY
	   elements that do, and they exist only in ADJUST mode. */
	.draw-handle {
		pointer-events: all;
		cursor: grab;
		touch-action: none;
		fill: var(--ctrl-strong-bg, #2980b9);
		stroke: var(--on-accent, #ffffff);
		stroke-width: 2.5;
	}
	.draw-handle:active {
		cursor: grabbing;
	}
	/* Unselected shape: a thinner ring to match the smaller radius, and a touch
	   of transparency so the connectors recede until you select the shape. */
	.draw-handle.quiet {
		stroke-width: 1.75;
		opacity: 0.7;
	}
	/* Bézier control points: hollow, so they read as satellites of the
	   endpoints they steer. */
	.draw-handle.control {
		fill: var(--ctrl-bg, #181818);
		stroke: var(--ctrl-strong-bg, #2980b9);
	}
	/* The arc's bend handle: accent-colored, one per arc, at the apex. */
	.draw-handle.bend {
		fill: var(--ctrl-selected-bg, #00b356);
	}
</style>
