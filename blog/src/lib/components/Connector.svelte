<!--
  Connector — an auto-routed arrow between two named <Block>s.

  A Block with a `name` publishes its live box to the page-wide anchor registry
  ($lib/stores/blockAnchors). A Connector looks its two endpoints up by that
  name and routes an arrow between the boxes — so the diagram is authored in
  NAMES, not coordinates, and every arrow follows its boxes when you drag them
  around in ADJUST mode. That is what turns Block into a diagramming tool.

      <Block name="api" x={200} y={400} width={280} height={140}>API</Block>
      <Block name="db"  x={900} y={400} width={280} height={140}>DB</Block>

      <Connector from="api" to="db" label="query" />

  Either end also takes a raw canvas point (`from={[300, 540]}`) or a literal
  box (`to={{ x, y, width, height }}`), so a connector can point at something
  that isn't a Block.

  ROUTES
    straight (default) — a line between the boxes, attaching wherever it meets
                         each border, at whatever angle it arrives.
    ortho              — right-angled elbows, corners rounded by `radius`.
    curve              — an S-bend leaving and entering each box square to its
                         side; the classic flowchart look.

  Sides are chosen automatically (the edge facing the other box, weighed by the
  box's own aspect) — pin one with `fromSide` / `toSide` when the auto pick
  isn't the story you're telling.

  ORDERING (matters!)  A Connector resolves its endpoints during **SSR** too,
  and Blocks register in document order — so put connectors AFTER the Blocks
  they link, or the prerendered slide ships without them. An unresolved name
  renders nothing at all (never a broken arrow), and the connector appears as
  soon as the name shows up client-side.

  Rendering: on its own, a Connector renders its own canvas-spanning <svg>
  overlay (pointer-events:none, so it never eats a click). Dropped INSIDE a
  <Draw>, it detects the surface via context and renders a bare <g> into it
  instead — so connectors and hand-placed shapes share one <svg> and one
  z-order.

  Theming rides the same --draw-* custom properties as the Draw family
  (--draw-stroke, --draw-thickness, --draw-font-size); `color`/`thickness`
  override per connector. `draw` gives it the family's CSS draw-on reveal
  (prerenders, and AnimationBar scrubs it); stagger `drawDelay` across several
  connectors to build a diagram step by step on one timeline.
-->
<script lang="ts">
	import { getContext } from 'svelte';
	import type { Snippet } from 'svelte';
	import { blockAnchors } from '$lib/stores/blockAnchors';
	import {
		connectorGeometry,
		pointRect,
		type Rect,
		type Route,
		type SideOpt
	} from '$lib/draw/connectorCore';
	import { arrowHead, defaultArrowSize, polygonPoints } from '$lib/draw/drawCore';
	import { DRAW_CONTEXT_KEY, type ArrowMode, type DrawContext, type Point } from '$lib/draw/types';

	/** A Block `name`, a canvas point, or a literal box. */
	type End = string | Point | Rect;

	interface Props {
		from: End;
		to: End;
		/** How the shaft gets from one box to the other. */
		route?: Route;
		/** Which arrowheads to draw. Unlike Line, a Connector points somewhere by
		 *  default — it exists to say "A → B". */
		arrow?: ArrowMode;
		/** Arrowhead length in canvas px; defaults to scale with thickness. */
		arrowSize?: number;
		/** Clearance in canvas px between a box's edge and the arrow tip. */
		gap?: number;
		/** Pin an end to a specific edge instead of the auto-facing one. */
		fromSide?: SideOpt;
		toSide?: SideOpt;
		/** Corner radius for `route="ortho"` elbows. */
		radius?: number;
		/** Visible text drawn on the shaft (this is the label you can SEE). */
		label?: string;
		/** Where the label sits along the shaft (0–1) and how far off it (px,
		 *  positive = left of the direction of travel). */
		labelAt?: number;
		labelOffset?: number;
		/** Stroke color; overrides --draw-stroke (default currentColor). */
		color?: string;
		/** Stroke width in canvas px; overrides --draw-thickness (default 4). */
		thickness?: number;
		/** true for the default dash pattern, or an SVG dasharray like "12 6". */
		dash?: boolean | string;
		/** Seconds for the connector to draw itself in (CSS only, so it survives
		 *  prerendering and AnimationBar scrubs it). The head and label fade in
		 *  over the final fifth. */
		draw?: number;
		/** Seconds to wait before the draw-on starts — stagger these to build a
		 *  diagram one arrow at a time on a single timeline. */
		drawDelay?: number;
		/** Accessible name. Defaults to the visible label, else "from → to". */
		ariaLabel?: string;
		/** The coordinate space when self-hosting an <svg> (ignored inside Draw). */
		canvasWidth?: number;
		canvasHeight?: number;
		/** Inline style for the root element, applied last so it wins. Lands on the
		 *  connector's own <g>, which is the one element present in BOTH render
		 *  modes (standalone overlay and nested inside a Draw surface). */
		style?: string;
		/** DOM id for the root element. */
		id?: string;
		/** Extra class(es) for the root element. NOTE: a slide's own scoped styles
		 *  will NOT match — use global CSS (global.css / roles.css / a :global(...)
		 *  block) or a utility class. See AGENTS.md. */
		class?: string;
	}

	let {
		from,
		to,
		route = 'straight',
		arrow = 'end',
		arrowSize,
		gap = 8,
		fromSide = 'auto',
		toSide = 'auto',
		radius = 12,
		label,
		labelAt = 0.5,
		labelOffset = 20,
		color,
		thickness,
		dash = false,
		draw,
		drawDelay,
		ariaLabel,
		canvasWidth = 1920,
		canvasHeight = 1080,
		style = '',
		id = '',
		class: klass = ''
	}: Props = $props();

	// Nested in a <Draw>? Then render into ITS svg rather than opening another.
	const drawCtx = getContext<DrawContext | undefined>(DRAW_CONTEXT_KEY);

	const anchors = $derived($blockAnchors);

	/** Resolve one endpoint. A name that isn't registered yet resolves to null,
	 *  which suppresses the whole connector — never a half-drawn arrow. */
	function resolve(end: End): Rect | null {
		if (typeof end === 'string') return anchors.get(end) ?? null;
		if (Array.isArray(end)) return pointRect(end);
		return end;
	}

	const a = $derived(resolve(from));
	const b = $derived(resolve(to));

	const atEnd = $derived(arrow === 'end' || arrow === 'both');
	const atStart = $derived(arrow === 'start' || arrow === 'both');
	const size = $derived(arrowSize ?? defaultArrowSize(thickness ?? 4));

	const geo = $derived(
		a && b
			? connectorGeometry(a, b, {
					route,
					gap,
					fromSide,
					toSide,
					radius,
					arrowSize: size,
					arrowStart: atStart,
					arrowEnd: atEnd,
					labelAt,
					labelOffset
				})
			: null
	);

	const endHead = $derived(geo && atEnd ? polygonPoints(arrowHead(geo.end, geo.endAngle, size)) : null);
	const startHead = $derived(
		geo && atStart ? polygonPoints(arrowHead(geo.start, geo.startAngle, size)) : null
	);

	const stroke = $derived(color ?? 'var(--draw-stroke, currentColor)');
	const strokeWidth = $derived(thickness ?? 'var(--draw-thickness, 4)');
	const dasharray = $derived(dash === true ? '12 8' : dash === false ? undefined : dash);

	// Draw-on: pathLength=1 normalizes the path so the dash trick needs no DOM
	// measurement (SSR-safe) — the same mechanism Line/Curve/Arc use.
	const drawSecs = $derived(draw && Number.isFinite(draw) && draw > 0 ? draw : null);
	const delaySecs = $derived(
		drawSecs && drawDelay && Number.isFinite(drawDelay) && drawDelay > 0 ? drawDelay : 0
	);

	const name = $derived(
		ariaLabel ??
			label ??
			(typeof from === 'string' && typeof to === 'string' ? `${from} to ${to}` : undefined)
	);
</script>

{#snippet shaft(g: NonNullable<typeof geo>)}
	<g
		id={id || undefined}
		class="connector {klass}"
		style={style || undefined}
		role={name ? 'img' : undefined}
		aria-label={name}
	>
		<path
			d={g.d}
			fill="none"
			class:draw-anim={drawSecs}
			pathLength={drawSecs ? 1 : undefined}
			stroke-dasharray={drawSecs ? undefined : dasharray}
			style="stroke:{stroke}; stroke-width:{strokeWidth};{drawSecs
				? ` animation-duration:${drawSecs}s;${delaySecs ? ` animation-delay:${delaySecs}s;` : ''}`
				: ''}"
		/>
		{#if endHead}
			<polygon
				points={endHead}
				class:head-anim={drawSecs}
				stroke="none"
				style="fill:{stroke};{drawSecs
					? ` animation-duration:${drawSecs * 0.2}s; animation-delay:${delaySecs + drawSecs * 0.8}s;`
					: ''}"
			/>
		{/if}
		{#if startHead}
			<polygon
				points={startHead}
				class:head-anim={drawSecs}
				stroke="none"
				style="fill:{stroke};{drawSecs
					? ` animation-duration:${drawSecs * 0.2}s; animation-delay:${delaySecs + drawSecs * 0.8}s;`
					: ''}"
			/>
		{/if}
		{#if label}
			<text
				class="connector-label"
				class:label-anim={drawSecs}
				x={g.label[0]}
				y={g.label[1]}
				text-anchor="middle"
				dominant-baseline="middle"
				style="fill:{stroke};{drawSecs
					? ` animation-duration:${drawSecs * 0.2}s; animation-delay:${delaySecs + drawSecs * 0.8}s;`
					: ''}">{label}</text
			>
		{/if}
	</g>
{/snippet}

{#if geo}
	{#if drawCtx}
		<!-- Inside a <Draw>: share its surface, its viewBox and its z-order. -->
		{@render shaft(geo)}
	{:else}
		<!-- Standalone: our own canvas-spanning overlay. pointer-events:none is
		     inline, so the never-eats-input guarantee holds even before CSS lands. -->
		<svg
			class="connector-surface"
			viewBox="0 0 {canvasWidth} {canvasHeight}"
			style="width:{canvasWidth}px; height:{canvasHeight}px; pointer-events:none;"
			aria-hidden={name ? undefined : 'true'}
		>
			{@render shaft(geo)}
		</svg>
	{/if}
{/if}

<style>
	.connector-surface {
		position: absolute;
		left: 0;
		top: 0;
		display: block;
		fill: none;
		font-size: var(--draw-font-size, 32px);
	}
	.connector-label {
		font-size: var(--draw-font-size, 32px);
		/* Halo the text in the surface color and paint it UNDER the fill, so a
		   label sitting on its own shaft (labelOffset={0}) still reads. Browsers
		   without paint-order just show a plain filled glyph. */
		paint-order: stroke;
		stroke: var(--surface-bg, #181818);
		stroke-width: 6px;
		stroke-linejoin: round;
	}
	/* Draw-on: the shaft draws itself, then the head and label fade in over the
	   final fifth. Durations/delays arrive inline from the `draw` prop. */
	path.draw-anim {
		stroke-dasharray: 1;
		stroke-dashoffset: 1;
		animation-name: connector-draw-on;
		animation-timing-function: ease-in-out;
		animation-fill-mode: forwards;
	}
	polygon.head-anim,
	text.label-anim {
		opacity: 0;
		animation-name: connector-head-in;
		animation-timing-function: ease-out;
		animation-fill-mode: forwards;
	}
	@keyframes connector-draw-on {
		to {
			stroke-dashoffset: 0;
		}
	}
	@keyframes connector-head-in {
		to {
			opacity: 1;
		}
	}
</style>
