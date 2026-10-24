<!--
  Ellipse — the ellipse inscribed in a canvas-pixel box, for circling a
  region or a word:

      <Ellipse x={1300} y={200} width={360} height={200} />

  Same Block-shaped box geometry as Rect (x/y/width/height, NOT cx/cy/rx/ry):
  in ADJUST mode the box registers with <Draw>, which hosts a real
  <Block tag="Ellipse"> for it — move/resize/aspect/grid/undo/Copy arrive
  wholesale, and Copy emits `<Ellipse …/>`. "Draw an ellipse over that area"
  is how an author thinks about it anyway.
-->
<script lang="ts">
	import { getContext, untrack } from 'svelte';
	import { boxTag, newEditorId, sharedAttrs } from './editing';
	import { finite, round } from './drawCore';
	import { guardStyle } from '$lib/adjust/styleGuardCore';
	import {
		fillPolygon,
		hachurePath,
		resolveRoughness,
		roughEllipse,
		seedOf,
		shapeIdentity
	} from './roughCore';
	import {
		DRAW_CONTEXT_KEY,
		type DrawContext,
		type DrawOnEditor,
		type DrawOnProps,
		type RoughFillProps,
		type RoughProps,
		type ShapeStyleProps
	} from './types';

	interface Props extends ShapeStyleProps, DrawOnProps, RoughProps, RoughFillProps {
		/** The bounding box the ellipse is inscribed in, in canvas pixels. */
		x: number;
		y: number;
		width: number;
		height: number;
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
		color,
		thickness,
		dash = false,
		fill,
		rough,
		seed,
		fillStyle,
		hachureGap,
		hachureAngle,
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

	// The Draw surface we sit in. Read at init (getContext must be), and up here
	// rather than down with the editing registration because the hand-drawn
	// render below needs the surface's `rough` default.
	const ctx = getContext<DrawContext | undefined>(DRAW_CONTEXT_KEY);

	// Draw-on (the classic circle-that-word beat): pathLength=1 works on
	// every SVG geometry element, so the dash trick needs no perimeter math.
	// drawDelay staggers shapes into a sequence on one AnimationBar timeline.
	// Live draw-on overrides (panel-editable reveal duration / delay, via the
	// hosted Block's toolbar).
	let liveDraw = $state<number | null>(null);
	let liveDrawDelay = $state<number | null>(null);
	const drawVal = $derived(liveDraw ?? draw);
	const drawDelayVal = $derived(liveDrawDelay ?? drawDelay);

	const drawSecs = $derived(drawVal && Number.isFinite(drawVal) && drawVal > 0 ? drawVal : null);
	const delaySecs = $derived(
		drawSecs && drawDelayVal && Number.isFinite(drawDelayVal) && drawDelayVal > 0 ? drawDelayVal : 0
	);

	// ADJUST-mode editing overrides (finder state, driven by Draw's hosted
	// Block; reset on reload — Copy → paste is the only persistence).
	let live = $state<{ x: number; y: number; w: number; h: number } | null>(null);
	const X = $derived(live?.x ?? finite(x));
	const Y = $derived(live?.y ?? finite(y));
	const W = $derived(Math.max(0, live?.w ?? finite(width)));
	const H = $derived(Math.max(0, live?.h ?? finite(height)));

	const rx = $derived(round(W / 2));
	const ry = $derived(round(H / 2));
	const cx = $derived(round(X + rx));
	const cy = $derived(round(Y + ry));

	const stroke = $derived(color ?? 'var(--draw-stroke, currentColor)');
	const strokeWidth = $derived(thickness ?? 'var(--draw-thickness, 4)');
	const fillValue = $derived(fill ?? 'var(--draw-fill, none)');

	// --- Hand-drawn render ----------------------------------------------------
	// Our own `rough` overrides the surface's; null means the ordinary <ellipse>.
	const roughness = $derived(resolveRoughness(rough, ctx?.rough ?? null));
	// Seeded from the BASE box, so a resize in ADJUST keeps a steady wobble.
	const roughSeed = $derived(seedOf(seed, shapeIdentity(name || 'Ellipse', x, y, width, height)));
	const roughOpts = $derived(roughness != null ? { roughness, seed: roughSeed } : null);
	// A closed wobbly loop per pen pass — see roughEllipse.
	const outlineDs = $derived(roughOpts ? roughEllipse(X, Y, W, H, roughOpts, '') : []);
	// A drawn ellipse fills with pen strokes, not a flat wash. `fillStyle="solid"`
	// keeps the ordinary SVG fill; anything else needs a real `fill` colour to
	// stroke WITH, so an unfilled ellipse stays unfilled.
	const hasFill = $derived(!!fill && fill !== 'none');
	const inkStyle = $derived(fillStyle ?? 'hachure');
	const fillD = $derived(
		roughOpts && hasFill && inkStyle !== 'solid'
			? hachurePath(
					fillPolygon('ellipse', X, Y, W, H),
					{ ...roughOpts, gap: hachureGap, angle: hachureAngle },
					'',
					inkStyle
				)
			: ''
	);
	const dasharray = $derived(dash === true ? '12 8' : dash === false ? undefined : dash);

	// The props own the geometry — an author's `style="width: 50px"` must not cancel
	// the box the hosting ADJUST Block drags. (An <ellipse> is driven by cx/cy/rx/ry,
	// so the reserved box properties are inert here; guarding anyway keeps ONE rule
	// across every draggable, and the badge still tells the truth.) See
	// adjust/styleGuardCore.ts.
	const guard = $derived(guardStyle(style));

	// --- ADJUST-mode editing: register the box with Draw, which hosts the
	// editing <Block tag="Ellipse"> (see Rect.svelte).

	const attrsWith = (dr: number | undefined, dd: number | undefined) =>
		(fill ? ` fill="${fill}"` : '') +
		sharedAttrs({ color, thickness, dash, rough, seed, label, draw: dr, drawDelay: dd, grid, id, class: klass, style });
	const extraAttrs = $derived(attrsWith(drawVal, drawDelayVal));
	const sourceAttrs = $derived(attrsWith(draw, drawDelay));

	// Live vs source opening tags (Block's exact emission format) — the
	// "Copy changed" patch pairs them as NEW/OLD.
	const liveTag = $derived(boxTag('Ellipse', name, extraAttrs, X, Y, W, H, aspect));
	const sourceTag = $derived(
		boxTag('Ellipse', name, sourceAttrs, finite(x), finite(y), Math.max(0, finite(width)), Math.max(0, finite(height)), aspect)
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
			tag: 'Ellipse',
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
			get sourceBox() {
				return {
					x: finite(x),
					y: finite(y),
					width: Math.max(0, finite(width)),
					height: Math.max(0, finite(height))
				};
			},
			get drawEdit() {
				return drawSecs ? drawApi : null;
			},
			get x() {
				return X;
			},
			set x(v) {
				live = { x: v, y: Y, w: W, h: H };
			},
			get y() {
				return Y;
			},
			set y(v) {
				live = { x: X, y: v, w: W, h: H };
			},
			get width() {
				return W;
			},
			set width(v) {
				live = { x: X, y: Y, w: v, h: H };
			},
			get height() {
				return H;
			},
			set height(v) {
				live = { x: X, y: Y, w: W, h: v };
			}
			})
		);
	});
</script>

{#if roughOpts}
	<!-- Hand-drawn: a group of pen strokes rather than one <ellipse>. The fill
	     goes down first (under the outline, as a pen would), and every stroke
	     shares the one draw-on timing so the shape reveals as a single gesture. -->
	<g
		id={id || undefined}
		class="draw-ellipse {klass}"
		style={guard.safe || undefined}
		aria-label={label}
		role={label ? 'img' : undefined}
	>
		{#if hasFill && inkStyle === 'solid'}
			<!-- A solid fill under a hand-drawn outline is painted on the TRUE
			     ellipse: the rough loop is a stroke, not a fillable interior. -->
			<ellipse {cx} {cy} {rx} {ry} fill={fillValue} stroke="none" />
		{/if}
		{#if fillD}
			<path
				class:draw-anim={drawSecs}
				d={fillD}
				fill="none"
				pathLength={drawSecs ? 1 : undefined}
				style="stroke:{fillValue}; stroke-width:{Math.max(
					1,
					(typeof strokeWidth === 'number' ? strokeWidth : 4) * 0.5
				)};{drawSecs
					? ` animation-duration:${drawSecs}s;${delaySecs ? ` animation-delay:${delaySecs}s;` : ''}`
					: ''}"
			/>
		{/if}
		{#each outlineDs as od, i (i)}
			<path
				class:draw-anim={drawSecs}
				d={od}
				fill="none"
				stroke-linecap="round"
				pathLength={drawSecs ? 1 : undefined}
				style="stroke:{stroke}; stroke-width:{strokeWidth};{drawSecs
					? ` animation-duration:${drawSecs}s;${delaySecs ? ` animation-delay:${delaySecs}s;` : ''}`
					: ''}"
				stroke-dasharray={drawSecs ? undefined : dasharray}
			/>
		{/each}
	</g>
{:else}
	<ellipse
		id={id || undefined}
		class="draw-ellipse {klass}"
		class:draw-anim={drawSecs}
		{cx}
		{cy}
		{rx}
		{ry}
		pathLength={drawSecs ? 1 : undefined}
		style="stroke:{stroke}; stroke-width:{strokeWidth}; fill:{fillValue};{drawSecs
			? ` animation-duration:${drawSecs}s;${delaySecs ? ` animation-delay:${delaySecs}s;` : ''}`
			: ''}{guard.safe}"
		stroke-dasharray={drawSecs ? undefined : dasharray}
		aria-label={label}
		role={label ? 'img' : undefined}
	/>
{/if}

<style>
	/* Draw-on: the outline traces itself; duration/delay come inline. */
	ellipse.draw-anim,
	path.draw-anim {
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
