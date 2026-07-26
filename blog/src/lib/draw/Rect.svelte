<!--
  Rect — an outlined box in canvas pixels, for framing a region:

      <Rect x={860} y={480} width={400} height={120} rounded={12} />

  Box geometry, deliberately Block-shaped (x/y/width/height, not corner
  pairs): in ADJUST mode this shape registers its box with <Draw>, which
  hosts a real <Block tag="Rect"> for it — move, resize, aspect-lock, grid,
  bounds, undo, and Copy arrive wholesale, and Copy emits `<Rect …/>`, not
  `<Block>`. Stroke-only by default (fill none); `fill` or --draw-fill adds
  one.
-->
<script lang="ts">
	import { getContext, untrack } from 'svelte';
	import { boxTag, fmtNum, newEditorId, sharedAttrs } from './editing';
	import { finite } from './drawCore';
	import { guardStyle } from '$lib/adjust/styleGuardCore';
	import {
		DRAW_CONTEXT_KEY,
		type DrawContext,
		type DrawOnEditor,
		type DrawOnProps,
		type ShapeStyleProps
	} from './types';

	interface Props extends ShapeStyleProps, DrawOnProps {
		/** Top-left position and size, in canvas pixels. */
		x: number;
		y: number;
		width: number;
		height: number;
		/** Corner radius in canvas px. */
		rounded?: number;
		/** Fill color; overrides --draw-fill (default none). */
		fill?: string;
		/** Shown in the editing readout + copied tag (mirrors Block's). */
		name?: string;
		/** Snap step (canvas px) while dragging/resizing. 1 = freeform. */
		grid?: number;
		/** Block's aspect lock while resizing (see Block.svelte). */
		aspect?: number | boolean | null;
		/** Block's drag bounds: keep inside the canvas, or roam free. */
		bounds?: 'canvas' | 'none';
		/** Inline style for the root element, applied last so it wins. */
		style?: string;
		/** DOM id for the root element. */
		id?: string;
		/** Extra class(es) for the root element. NOTE: a slide's own scoped styles
		 *  will NOT match — use global CSS (global.css / roles.css / a :global(...)
		 *  block) or a utility class. See AGENTS.md. */
		class?: string;
	}

	let {
		x,
		y,
		width,
		height,
		rounded = 0,
		color,
		thickness,
		dash = false,
		fill,
		label,
		draw,
		drawDelay,
		name = '',
		grid = 1,
		aspect = null,
		bounds = 'canvas',
		style = '',
		id = '',
		class: klass = ''
	}: Props = $props();

	// Live draw-on overrides (panel-editable reveal duration / delay, via the
	// hosted Block's toolbar).
	let liveDraw = $state<number | null>(null);
	let liveDrawDelay = $state<number | null>(null);
	const drawVal = $derived(liveDraw ?? draw);
	const drawDelayVal = $derived(liveDrawDelay ?? drawDelay);

	// Draw-on (the outline traces itself): pathLength=1 works on every SVG
	// geometry element, so the dash trick needs no perimeter math. drawDelay
	// staggers shapes into a sequence on one AnimationBar timeline.
	const drawSecs = $derived(drawVal && Number.isFinite(drawVal) && drawVal > 0 ? drawVal : null);
	const delaySecs = $derived(
		drawSecs && drawDelayVal && Number.isFinite(drawDelayVal) && drawDelayVal > 0 ? drawDelayVal : 0
	);

	// ADJUST-mode editing overrides (finder state, driven by Draw's hosted
	// Block; reset on reload — Copy → paste is the only persistence).
	let live = $state<{ x: number; y: number; w: number; h: number } | null>(null);
	const X = $derived(live?.x ?? finite(x));
	const Y = $derived(live?.y ?? finite(y));

	// NaN-safe, and SVG errors on negative width/height — clamp to 0 (renders nothing).
	const w = $derived(Math.max(0, live?.w ?? finite(width)));
	const h = $derived(Math.max(0, live?.h ?? finite(height)));

	const stroke = $derived(color ?? 'var(--draw-stroke, currentColor)');
	const strokeWidth = $derived(thickness ?? 'var(--draw-thickness, 4)');
	const fillValue = $derived(fill ?? 'var(--draw-fill, none)');
	const dasharray = $derived(dash === true ? '12 8' : dash === false ? undefined : dash);

	// x/y/width/height reach the <rect> as PRESENTATION attributes, which any css —
	// an inline style included — outranks. So an author's `style="width: 50px"`
	// would silently cancel the geometry this shape is drawing, and the ADJUST Block
	// hosting it would drag a box that never moves. Same rule as Block: the props own
	// the geometry, cosmetics pass through. (`rx` is NOT reserved — here it means
	// corner rounding, not a radius.) See adjust/styleGuardCore.ts.
	const guard = $derived(guardStyle(style));

	// --- ADJUST-mode editing: register the box with Draw, which hosts the
	// editing <Block tag="Rect"> (registered post-render via $effect so a
	// child never mutates the parent's state mid-render).
	const ctx = getContext<DrawContext | undefined>(DRAW_CONTEXT_KEY);

	const attrsWith = (dr: number | undefined, dd: number | undefined) =>
		(rounded ? ` rounded={${fmtNum(rounded)}}` : '') +
		(fill ? ` fill="${fill}"` : '') +
		sharedAttrs({ color, thickness, dash, label, draw: dr, drawDelay: dd, grid, id, class: klass, style });
	// Live attrs (drive the hosted Block's render + its Copy); source attrs
	// use the original draw timing for the "Copy changed" OLD side.
	const extraAttrs = $derived(attrsWith(drawVal, drawDelayVal));
	const sourceAttrs = $derived(attrsWith(draw, drawDelay));

	// Live vs source opening tags (Block's exact emission format) — the
	// "Copy changed" patch pairs them as NEW/OLD.
	const liveTag = $derived(boxTag('Rect', name, extraAttrs, X, Y, w, h, aspect));
	const sourceTag = $derived(
		boxTag('Rect', name, sourceAttrs, finite(x), finite(y), Math.max(0, finite(width)), Math.max(0, finite(height)), aspect)
	);

	const drawApi: DrawOnEditor = {
		get seconds() {
			return finite(drawVal ?? 0);
		},
		get delay() {
			return finite(drawDelayVal ?? 0);
		},
		setSeconds(v: number) {
			liveDraw = Math.max(0, finite(v));
		},
		setDelay(v: number) {
			liveDrawDelay = Math.max(0, finite(v));
		}
	};

	$effect(() => {
		if (!ctx?.registerBlock) return;
		// untrack: registering reads+writes Draw's shape list; tracking it here
		// would re-run this effect on every registration (infinite loop).
		return untrack(() =>
			ctx.registerBlock({
			id: newEditorId(),
			tag: 'Rect',
			get name() {
				return name;
			},
			get style() {
				return style;
			},
			get grid() {
				return grid;
			},
			get attrs() {
				return extraAttrs;
			},
			get aspect() {
				return aspect;
			},
			get bounds() {
				return bounds;
			},
			get snippet() {
				return liveTag;
			},
			get sourceSnippet() {
				return sourceTag;
			},
			get dirty() {
				return liveTag !== sourceTag;
			},
			get drawEdit() {
				return drawSecs ? drawApi : null;
			},
			get x() {
				return X;
			},
			set x(v) {
				live = { x: v, y: Y, w, h };
			},
			get y() {
				return Y;
			},
			set y(v) {
				live = { x: X, y: v, w, h };
			},
			get width() {
				return w;
			},
			set width(v) {
				live = { x: X, y: Y, w: v, h };
			},
			get height() {
				return h;
			},
			set height(v) {
				live = { x: X, y: Y, w, h: v };
			}
			})
		);
	});
</script>

<rect
	id={id || undefined}
	class="draw-rect {klass}"
	class:draw-anim={drawSecs}
	x={X}
	y={Y}
	width={w}
	height={h}
	rx={Math.max(0, finite(rounded)) || undefined}
	pathLength={drawSecs ? 1 : undefined}
	style="stroke:{stroke}; stroke-width:{strokeWidth}; fill:{fillValue};{drawSecs
		? ` animation-duration:${drawSecs}s;${delaySecs ? ` animation-delay:${delaySecs}s;` : ''}`
		: ''}{guard.safe}"
	stroke-dasharray={drawSecs ? undefined : dasharray}
	aria-label={label}
	role={label ? 'img' : undefined}
/>

<style>
	/* Draw-on: the outline traces itself; duration/delay come inline. */
	rect.draw-anim {
		stroke-dasharray: 1;
		stroke-dashoffset: 1;
		animation-name: draw-on;
		animation-timing-function: ease-in-out;
		animation-fill-mode: forwards;
	}
	@keyframes draw-on {
		to {
			stroke-dashoffset: 0;
		}
	}
</style>
