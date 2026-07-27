<!--
  Polyline — straight or smoothed segments through a list of canvas points:

      <Polyline points={[[100, 900], [400, 700], [700, 950], [1100, 600]]} smooth />

  `smooth` runs a Catmull-Rom through the points (converted to cubic
  segments in drawCore's smoothPath): the curve passes exactly THROUGH every
  input point — no overshoot-prone fitting. `close` joins the last point
  back to the first (a polygon; with `smooth` the loop stays smooth through
  the seam). Like Line/Curve/Arc.

  `name` publishes the geometry as a path source: a <Sprite path="route">
  later in the same <Draw> flies this exact polyline (see Sprite's PATH MODE).
  Because the source hands out the LIVE (edited) points, dragging the route in
  ADJUST re-routes any rider with it.

  ADJUST-mode editing: with the deck's ADJUST control on, clicking the stroke
  selects the shape and each waypoint grows a drag handle (move-only — the
  waypoint COUNT is fixed; edit the tag to add or remove one). Edits are local
  finder state — Copy → paste is the only persistence — and every completed
  drag records to the global ADJUST undo/redo.
-->
<script lang="ts">
	import { getContext, onDestroy, untrack } from 'svelte';
	import { record } from '$lib/stores/adjustHistory';
	import DrawHandle from './DrawHandle.svelte';
	import { fmtPoint, newEditorId, sharedAttrs } from './editing';
	import { polylinePath, smoothPath } from './drawCore';
	import {
		DRAW_CONTEXT_KEY,
		type DrawContext,
		type DrawOnProps,
		type Point,
		type ShapeEditor,
		type ShapeStyleProps
	} from './types';

	interface Props extends ShapeStyleProps, DrawOnProps {
		points: Point[];
		/** Join the last point back to the first. */
		close?: boolean;
		/** Catmull-Rom smoothing through every point. */
		smooth?: boolean;
		/** Publish this polyline's live geometry as a path source, so a
		 *  <Sprite path="<name>"> in the same <Draw> can ride it (the shape must
		 *  come EARLIER in the markup — Connector's rule). */
		name?: string;
		/** Snap step (canvas px) while dragging handles. 1 = freeform. */
		grid?: number;
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
		points,
		close = false,
		smooth = false,
		name = '',
		grid = 1,
		color,
		thickness,
		dash = false,
		label,
		draw,
		drawDelay,
		style = '',
		id = '',
		class: klass = ''
	}: Props = $props();

	// ADJUST-mode editing override: the editor is a coordinate FINDER — drags
	// mutate this local (reset on reload), never the prop; Copy → paste is the
	// only persistence. Move-only, so the point COUNT never changes here.
	let livePoints = $state<Point[] | null>(null);
	const PTS = $derived<Point[]>(livePoints ?? points);

	// Clone the prop points into editable state on first edit.
	function materialize(): Point[] {
		if (!livePoints) livePoints = points.map((p): Point => [p[0], p[1]]);
		return livePoints;
	}
	function setPoint(i: number, p: Point) {
		livePoints = materialize().map((q, k) => (k === i ? p : q));
	}
	function commitPoint(i: number, before: Point, after: Point) {
		record({ undo: () => setPoint(i, before), redo: () => setPoint(i, after) });
	}

	// Draw-on: pathLength=1 normalizes any path so the dash trick needs no
	// DOM measurement (SSR-safe); the animation then owns the dash pattern.
	// drawDelay staggers shapes into a sequence on one AnimationBar timeline.
	const drawSecs = $derived(draw && Number.isFinite(draw) && draw > 0 ? draw : null);
	const delaySecs = $derived(
		drawSecs && drawDelay && Number.isFinite(drawDelay) && drawDelay > 0 ? drawDelay : 0
	);

	const d = $derived(smooth ? smoothPath(PTS, close) : polylinePath(PTS, close));

	// --- ADJUST-mode editing chrome ------------------------------------------
	const ctx = getContext<DrawContext | undefined>(DRAW_CONTEXT_KEY);
	const editing = $derived(ctx?.editing ?? false);

	// Publish the LIVE geometry under our name so a <Sprite path="<name>"> can
	// ride this polyline and re-route as it's dragged (see Curve.svelte — same
	// contract, incl. the deliberate init-time capture of `name`).
	// svelte-ignore state_referenced_locally
	if (name && ctx)
		onDestroy(ctx.registerPathSource(name, () => ({ kind: 'polyline', points: PTS, close, smooth })));

	const pointsAttr = (list: Point[]) => `points={[${list.map(fmtPoint).join(', ')}]}`;
	const tagFor = (list: Point[]) =>
		`<Polyline${name ? ` name="${name}"` : ''} ${pointsAttr(list)}` +
		`${close ? ' close' : ''}${smooth ? ' smooth' : ''}` +
		sharedAttrs({ color, thickness, dash, label, draw, drawDelay, grid, id, class: klass, style }) +
		' />';
	const snippet = $derived(tagFor(PTS));
	const sourceSnippet = $derived(tagFor(points));

	const uid = newEditorId();
	const editor: ShapeEditor = {
		id: uid,
		kind: 'Polyline',
		get name() {
			return name;
		},
		get readout() {
			return `${PTS.length} pts${smooth ? ' · smooth' : ''}${close ? ' · closed' : ''}`;
		},
		get snippet() {
			return snippet;
		},
		get sourceSnippet() {
			return sourceSnippet;
		},
		get dirty() {
			return snippet !== sourceSnippet;
		},
		get chrome() {
			return chrome;
		}
	};
	const isSelected = $derived(ctx?.selected === editor);
	// Selected → Draw renders our `chrome` snippet in its top layer instead, so
	// we must not also render it inline (select-to-front; see DrawContext).
	const isHoisted = $derived(ctx?.hoisted === editor);
	const select = () => ctx?.select(editor);
	$effect(() => {
		if (!ctx?.registerShape) return;
		// untrack: registering reads+writes Draw's shape list (see Rect.svelte).
		return untrack(() => ctx.registerShape(editor));
	});
	onDestroy(() => {
		if (ctx?.selected === editor) ctx.select(null);
	});

	const stroke = $derived(color ?? 'var(--draw-stroke, currentColor)');
	const strokeWidth = $derived(thickness ?? 'var(--draw-thickness, 4)');
	const dasharray = $derived(dash === true ? '12 8' : dash === false ? undefined : dash);
</script>

<g
	id={id || undefined}
	class="draw-polyline {klass}"
	style={style || undefined}
	aria-label={label}
	role={label ? 'img' : undefined}
>
	{#if isSelected && d}
		<path class="draw-selglow" {d} />
	{/if}
	{#if d}
		<path
			class="draw-polyline-stroke"
			class:draw-anim={drawSecs}
			{d}
			fill="none"
			pathLength={drawSecs ? 1 : undefined}
			style="stroke:{stroke}; stroke-width:{strokeWidth};{drawSecs
				? ` animation-duration:${drawSecs}s;${delaySecs ? ` animation-delay:${delaySecs}s;` : ''}`
				: ''}"
			stroke-dasharray={drawSecs ? undefined : dasharray}
			stroke-linejoin="round"
		/>
	{/if}

	{#if editing && d}
		<!-- The hit stroke stays HOME even when selected: it is the only chrome
		     that competes with other shapes' hit strokes (see Line). -->
		<!-- svelte-ignore a11y_no_static_element_interactions -->
		<path class="draw-hit" {d} onpointerdown={select} />
		{#if !isHoisted}{@render chrome()}{/if}
	{/if}
</g>

{#snippet chrome()}
	<!-- One handle per waypoint (move-only), wrapped so <Draw> can re-parent
	     them whole into its top layer once selected (select-to-front). -->
	<g class="draw-chrome" data-shape={name || 'Polyline'}>
		{#each PTS as p, i (i)}
			<DrawHandle
				selected={isSelected}
				point={p}
				{grid}
				title={`p${i}`}
				onselect={select}
				onmove={(q) => setPoint(i, q)}
				oncommit={(b, a) => commitPoint(i, b, a)}
			/>
		{/each}
	</g>
{/snippet}

<style>
	/* Draw-on: the shape draws itself; duration comes inline from `draw`. */
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
	/* Editing chrome (ADJUST mode only): the hit stroke re-enables pointer
	   events on just this shape's stroke; the glow marks the selected shape. */
	.draw-hit {
		fill: none;
		stroke: transparent;
		stroke-width: 24;
		pointer-events: stroke;
		cursor: pointer;
	}
	.draw-selglow {
		fill: none;
		stroke: var(--ctrl-selected-bg, #00b356);
		stroke-opacity: 0.35;
		stroke-width: 14;
		stroke-linecap: round;
		stroke-linejoin: round;
	}
</style>
