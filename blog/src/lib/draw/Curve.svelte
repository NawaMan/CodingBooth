<!--
  Curve — a Bézier between two canvas points: quadratic when only `c1` is
  given, cubic with `c1` + `c2`. Composes inside <Draw>:

      <Curve from={[200, 800]} to={[1200, 300]} c1={[700, 900]} arrow="end" />
      <Curve from={[200, 200]} to={[900, 700]} c1={[500, 100]} c2={[700, 800]} />

  Arrowheads point along the curve's END TANGENT (angleAt), not the chord,
  and the shaft is trimmed behind each head by exact de Casteljau
  subdivision (shortenShape) so no stroke pokes past the tip — the same
  computed-polygon approach as Line, fed by the curve's tangents.

  ADJUST-mode editing (Phase 3): endpoint handles plus hollow control-point
  handles with the conventional thin guide lines from each control point to
  its endpoint (c1 → from, c2 → to; a quadratic's single c1 guides to both
  ends). Guide lines are editing chrome — never in the published output.

  All geometry math lives in drawCore.ts (pure, NaN-safe); this component is
  only $derived wiring and SVG markup. Theming and the default-arrow-size
  note are as in Line.svelte.
-->
<script lang="ts">
	import { getContext, onDestroy, untrack } from 'svelte';
	import { browser } from '$app/environment';
	import { record } from '$lib/stores/adjustHistory';
	import DrawHandle from './DrawHandle.svelte';
	import {
		fmtNum,
		fmtPoint,
		lerpPointAt,
		neighborsAt,
		newEditorId,
		playheadPercent,
		sanitizeEase,
		sharedAttrs,
		widestGapMid
	} from './editing';
	import {
		angleAt,
		arrowHead,
		curvePath,
		defaultArrowSize,
		finite,
		labelPos,
		linePath,
		polygonPoints,
		reverseShape,
		round,
		shortenShape,
		unwrapAngles
	} from './drawCore';
	import {
		DRAW_CONTEXT_KEY,
		type AnimEditor,
		type ArrowMode,
		type CurveStop,
		type DrawOnEditor,
		type DrawContext,
		type DrawOnProps,
		type PathLabelProps,
		type PathShape,
		type Point,
		type SegmentShape,
		type ShapeEditor,
		type ShapeStyleProps
	} from './types';

	interface Props extends ShapeStyleProps, PathLabelProps, DrawOnProps {
		from: Point;
		to: Point;
		/** Control point; alone it makes the curve quadratic. */
		c1: Point;
		/** Second control point; with c2 the curve is cubic. */
		c2?: Point;
		arrow?: ArrowMode;
		/** Arrowhead size in canvas px; defaults to scale with thickness. */
		arrowSize?: number;
		/** Geometry keyframes: the curve's endpoints/control points per
		 *  percent, animated over `animate` seconds (CSS d: path() tween — a
		 *  cubic stays cubic and a quadratic quadratic, so the command
		 *  structure matches at every stop). Same model as Line's stops; needs
		 *  ≥2, takes precedence over `draw`. */
		stops?: CurveStop[];
		/** Seconds for one pass through `stops` (ease-in-out, fill both). Drives
		 *  both tracks a stop can carry: geometry (from/to/c1/c2) and the
		 *  `drawn` self-draw progress (keyframed stroke-dashoffset). */
		animate?: number;
		/** Shown in the editing readout + copied tag (mirrors Block's). */
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
		from,
		to,
		c1,
		c2,
		arrow = 'none',
		arrowSize,
		color,
		thickness,
		dash = false,
		label,
		labelText,
		labelAt = 0.5,
		labelOffset = 20,
		draw,
		drawDelay,
		stops,
		animate,
		name = '',
		grid = 1,
		style = '',
		id = '',
		class: klass = ''
	}: Props = $props();

	// ADJUST-mode editing overrides (finder state — reset on reload; Copy →
	// paste into the source is the only persistence).
	let liveFrom = $state<Point | null>(null);
	let liveTo = $state<Point | null>(null);
	let liveC1 = $state<Point | null>(null);
	let liveC2 = $state<Point | null>(null);
	type IdStop = CurveStop & { id: number };
	let liveStops = $state<IdStop[] | null>(null);
	let stopSeq = 0;
	let liveDraw = $state<number | null>(null);
	let liveDrawDelay = $state<number | null>(null);
	const F = $derived(liveFrom ?? from);
	const T = $derived(liveTo ?? to);
	const C1 = $derived(liveC1 ?? c1);
	const C2 = $derived(c2 ? (liveC2 ?? c2) : undefined);
	const S = $derived<CurveStop[] | undefined>(liveStops ?? stops);
	const drawVal = $derived(liveDraw ?? draw);
	const drawDelayVal = $derived(liveDrawDelay ?? drawDelay);

	function materializeStops(): IdStop[] {
		if (!liveStops) liveStops = (stops ?? []).map((s) => ({ ...s, id: stopSeq++ }));
		return liveStops;
	}

	// One timeline (`animate`) drives two tracks a stop can carry: geometry
	// (from/to/c1/c2 → the d: path tween) and `drawn` (keyframed
	// stroke-dashoffset reveal). A stop counts toward each track only if it
	// defines that track's data, so the two are independent (a reveal-only
	// keyframe at 75% doesn't pin the geometry). Either takes precedence over
	// the flat `draw` reveal.
	const hasGeom = (s: CurveStop) => !!(s.from || s.to || s.c1 || s.c2);
	const hasDrawn = (s: CurveStop) => s.drawn != null;
	const geomStopsActive = $derived(!!(S && S.filter(hasGeom).length >= 2));
	const revealActive = $derived(!!(S && S.filter(hasDrawn).length >= 2));
	const animSecs = $derived(
		animate && Number.isFinite(animate) && animate > 0 && (geomStopsActive || revealActive)
			? animate
			: null
	);
	const geomAnim = $derived(animSecs != null && geomStopsActive);
	const revealAnim = $derived(animSecs != null && revealActive);

	// Draw-on: pathLength=1 normalizes any path so the dash trick needs no
	// DOM measurement (SSR-safe); the animation then owns the dash pattern.
	// drawDelay staggers shapes into a sequence on one AnimationBar timeline.
	const drawSecs = $derived(
		!animSecs && drawVal && Number.isFinite(drawVal) && drawVal > 0 ? drawVal : null
	);
	const delaySecs = $derived(
		drawSecs && drawDelayVal && Number.isFinite(drawDelayVal) && drawDelayVal > 0 ? drawDelayVal : 0
	);

	const base = $derived<SegmentShape>(
		C2 ? { kind: 'cubic', from: F, to: T, c1: C1, c2: C2 } : { kind: 'quadratic', from: F, to: T, c1: C1 }
	);

	// Resolve a stop into a full PathShape (each missing point → base value),
	// keeping cubic/quadratic identity from the BASE so every frame's `d` has
	// the same command structure.
	function stopShape(s: CurveStop): SegmentShape {
		const f = s.from ?? F;
		const t = s.to ?? T;
		const a = s.c1 ?? C1;
		return C2 ? { kind: 'cubic', from: f, to: t, c1: a, c2: s.c2 ?? C2 } : { kind: 'quadratic', from: f, to: t, c1: a };
	}

	const geomStops = $derived.by(() => {
		if (!geomAnim || !S) return null;
		return S.filter(hasGeom)
			.map((s) => ({
				pct: Math.max(0, Math.min(100, finite(s.pct))),
				shape: stopShape(s),
				ease: sanitizeEase(s.ease)
			}))
			.sort((a, b) => a.pct - b.pct);
	});

	const atEnd = $derived(arrow === 'end' || arrow === 'both');
	const atStart = $derived(arrow === 'start' || arrow === 'both');
	const size = $derived(arrowSize ?? defaultArrowSize(thickness ?? 4));

	// Shaft, trimmed behind each head so the stroke never pokes past a tip.
	const shaft = $derived.by(() => {
		let s: SegmentShape = base;
		if (atEnd) s = shortenShape(s, size);
		if (atStart) s = reverseShape(shortenShape(reverseShape(s), size));
		return s;
	});

	const d = $derived(
		shaft.kind === 'cubic'
			? curvePath(shaft.from, shaft.to, shaft.c1, shaft.c2)
			: shaft.kind === 'quadratic'
				? curvePath(shaft.from, shaft.to, shaft.c1)
				: linePath(shaft.from, shaft.to)
	);
	const baseD = $derived(C2 ? curvePath(F, T, C1, C2) : curvePath(F, T, C1));

	// Heads sit on the ORIGINAL curve's endpoints and end tangents.
	const endHead = $derived(atEnd ? polygonPoints(arrowHead(T, angleAt(base, 1), size)) : null);
	const startHead = $derived(
		atStart ? polygonPoints(arrowHead(F, angleAt(base, 0) + Math.PI, size)) : null
	);

	const stroke = $derived(color ?? 'var(--draw-stroke, currentColor)');
	const strokeWidth = $derived(thickness ?? 'var(--draw-thickness, 4)');
	const dasharray = $derived(dash === true ? '12 8' : dash === false ? undefined : dash);

	const labelXY = $derived(labelText ? labelPos(base, labelAt, labelOffset) : null);

	// --- Geometry keyframes: generate one @keyframes set from the stops via
	// the same pure builders the static render uses (see Line.svelte). The
	// shaft tweens d: path(…); heads/label ride along on transform keyframes.
	const uid = newEditorId();
	const animName = `draw-move-${uid}`;
	const deg = (rad: number) => round((rad * 180) / Math.PI);

	function shaftDOf(shape: SegmentShape): string {
		let s = shape;
		if (atEnd) s = shortenShape(s, size);
		if (atStart) s = reverseShape(shortenShape(reverseShape(s), size));
		return s.kind === 'cubic'
			? curvePath(s.from, s.to, s.c1, s.c2)
			: s.kind === 'quadratic'
				? curvePath(s.from, s.to, s.c1)
				: linePath(s.from, s.to);
	}

	// A per-stop CSS timing function set INSIDE its keyframe governs the
	// segment starting at that stop (ease-in/out/linear); '' inherits the
	// animation's default ease-in-out.
	const tf = (e: string) => (e ? ` animation-timing-function: ${e};` : '');

	const keyframesCss = $derived.by(() => {
		if (!animSecs) return '';
		const frame = (pct: number, body: string) => `${pct}% { ${body} }`;
		let css = '';
		if (geomStops) {
			const shaftFrames = geomStops
				.map((g) => frame(g.pct, `d: path("${shaftDOf(g.shape)}");${tf(g.ease)}`))
				.join(' ');
			css += `@keyframes ${animName} { ${shaftFrames} }`;
			if (atEnd) {
				// Unwrap the tangent angles across stops so the head takes the SHORTEST
				// rotation between keyframes — a curve's end tangent can jump the atan2
				// branch cut between poses, otherwise spinning the head the long way.
				const angles = unwrapAngles(geomStops.map((g) => angleAt(g.shape, 1)));
				const frames = geomStops
					.map((g, i) =>
						frame(
							g.pct,
							`transform: translate(${round(g.shape.to[0])}px, ${round(g.shape.to[1])}px) rotate(${deg(angles[i])}deg);${tf(g.ease)}`
						)
					)
					.join(' ');
				css += ` @keyframes ${animName}-end { ${frames} }`;
			}
			if (atStart) {
				const angles = unwrapAngles(geomStops.map((g) => angleAt(g.shape, 0) + Math.PI));
				const frames = geomStops
					.map((g, i) =>
						frame(
							g.pct,
							`transform: translate(${round(g.shape.from[0])}px, ${round(g.shape.from[1])}px) rotate(${deg(angles[i])}deg);${tf(g.ease)}`
						)
					)
					.join(' ');
				css += ` @keyframes ${animName}-start { ${frames} }`;
			}
			if (labelText) {
				const frames = geomStops
					.map((g) => {
						const p = labelPos(g.shape, labelAt, labelOffset);
						return frame(g.pct, `transform: translate(${p[0]}px, ${p[1]}px);${tf(g.ease)}`);
					})
					.join(' ');
				css += ` @keyframes ${animName}-label { ${frames} }`;
			}
		}
		if (revealAnim && S) {
			// drawn 0..1 → stroke-dashoffset 1..0 (pathLength=1 normalizes).
			const frames = S.filter(hasDrawn)
				.map((s) => ({
					pct: Math.max(0, Math.min(100, finite(s.pct))),
					off: round(1 - Math.max(0, Math.min(1, finite(s.drawn as number)))),
					ease: sanitizeEase(s.ease)
				}))
				.sort((a, b) => a.pct - b.pct)
				.map((r) => frame(r.pct, `stroke-dashoffset: ${r.off};${tf(r.ease)}`))
				.join(' ');
			css += ` @keyframes ${animName}-reveal { ${frames} }`;
		}
		return css;
	});

	const originHead = $derived(polygonPoints(arrowHead([0, 0], 0, size)));
	const animOf = (suffix: string) => ` animation: ${animName}${suffix} ${animSecs}s ease-in-out both;`;
	// Combined shaft animation: geometry d-tween and/or reveal dashoffset.
	const shaftAnim = $derived.by(() => {
		if (!animSecs) return '';
		const parts: string[] = [];
		if (geomAnim) parts.push(`${animName} ${animSecs}s ease-in-out both`);
		if (revealAnim) parts.push(`${animName}-reveal ${animSecs}s ease-in-out both`);
		return parts.length ? ` animation: ${parts.join(', ')};` : '';
	});

	// --- ADJUST-mode editing chrome ------------------------------------------
	const ctx = getContext<DrawContext | undefined>(DRAW_CONTEXT_KEY);
	const editing = $derived(ctx?.editing ?? false);

	// Publish the live geometry under our name so a <Sprite path="<name>"> can
	// ride this curve. Init-time (not an effect) so it exists during prerender;
	// the getter reads the live points, so dragging a handle re-routes the rider.
	// The initial-value capture of `name` is deliberate: a shape's name is its
	// identity, not reactive state (see DrawContext.registerPathSource).
	// svelte-ignore state_referenced_locally
	if (name && ctx) onDestroy(ctx.registerPathSource(name, () => base));

	const stopsAttrFor = (list: CurveStop[] | undefined) =>
		list && list.length
			? ` stops={[${list
					.map(
						(s) =>
							`{ pct: ${finite(s.pct)}${s.from ? `, from: ${fmtPoint(s.from)}` : ''}${s.to ? `, to: ${fmtPoint(s.to)}` : ''}${s.c1 ? `, c1: ${fmtPoint(s.c1)}` : ''}${s.c2 ? `, c2: ${fmtPoint(s.c2)}` : ''}${s.drawn != null ? `, drawn: ${fmtNum(s.drawn)}` : ''}${s.ease ? `, ease: "${sanitizeEase(s.ease)}"` : ''} }`
					)
					.join(', ')}]}`
			: '';

	const tagFor = (f: Point, t: Point, a: Point, b: Point | undefined, list: CurveStop[] | undefined, dr: number | undefined, dd: number | undefined) =>
		`<Curve${name ? ` name="${name}"` : ''} from={${fmtPoint(f)}} to={${fmtPoint(t)}}` +
		` c1={${fmtPoint(a)}}${b ? ` c2={${fmtPoint(b)}}` : ''}` +
		stopsAttrFor(list) +
		(list && list.length && animate ? ` animate={${finite(animate)}}` : '') +
		sharedAttrs({ arrow, arrowSize, color, thickness, dash, label, labelText, labelAt, labelOffset, draw: dr, drawDelay: dd, grid, id, class: klass, style }) +
		' />';
	const snippet = $derived(tagFor(F, T, C1, C2, S, drawVal, drawDelayVal));
	const sourceSnippet = $derived(tagFor(from, to, c1, c2, stops, draw, drawDelay));

	const editor: ShapeEditor = {
		id: uid,
		kind: 'Curve',
		get name() {
			return name;
		},
		get readout() {
			return `from ${fmtPoint(F)} → to ${fmtPoint(T)} · c1 ${fmtPoint(C1)}${C2 ? ` · c2 ${fmtPoint(C2)}` : ''}`;
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
		get anim() {
			return geomAnim ? animApi : null;
		},
		get drawEdit() {
			return drawSecs ? drawApi : null;
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

	function commit(apply: (p: Point) => void, before: Point, after: Point) {
		record({ undo: () => apply(before), redo: () => apply(after) });
	}

	// --- Editable stops + keyframe editor (see Line.svelte for the model).
	const POINT_KEYS = ['from', 'to', 'c1', 'c2'] as const;
	type StopKey = (typeof POINT_KEYS)[number];
	const baseOf = (key: StopKey): Point => (key === 'from' ? F : key === 'to' ? T : key === 'c1' ? C1 : (C2 ?? C1));
	const lowestStopFor = (key: StopKey) => {
		let best = -1;
		S?.forEach((s, i) => {
			if (s[key] && (best === -1 || finite(s.pct) < finite(S[best].pct))) best = i;
		});
		return best;
	};

	function setStop(i: number, key: StopKey, p: Point, sync: boolean) {
		liveStops = materializeStops().map((s, k) => (k === i ? { ...s, [key]: p } : s));
		if (sync) {
			if (key === 'from') liveFrom = p;
			else if (key === 'to') liveTo = p;
			else if (key === 'c1') liveC1 = p;
			else liveC2 = p;
		}
	}
	function commitStop(i: number, key: StopKey, sync: boolean, b: Point, a: Point) {
		record({ undo: () => setStop(i, key, b, sync), redo: () => setStop(i, key, a, sync) });
	}

	$effect(() => {
		if (editing && isSelected && geomAnim && !liveStops) materializeStops();
	});

	// Ref to the shaft path, so "+ keyframe" can read the live playhead time.
	let shaftEl = $state<SVGPathElement>();

	// Live playhead % for timeline-aware stop connectors (dashed before, bold
	// near). Polled each frame while editing an animated curve; null otherwise.
	let playhead = $state<number | null>(null);
	$effect(() => {
		if (!browser || !editing || !geomAnim) {
			playhead = null;
			return;
		}
		let raf = 0;
		const loop = () => {
			playhead = playheadPercent(shaftEl, animName, animSecs);
			raf = requestAnimationFrame(loop);
		};
		loop();
		return () => cancelAnimationFrame(raf);
	});

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

	const animApi: AnimEditor = {
		get stops() {
			const list = liveStops ?? (stops ?? []).map((s, i) => ({ ...s, id: -1 - i }) as IdStop);
			return list
				.map((s) => ({
					id: s.id,
					pct: Math.round(finite(s.pct)),
					// draw fraction → percent for the panel; null when this stop
					// isn't a reveal keyframe.
					drawn: s.drawn != null ? Math.round(finite(s.drawn) * 100) : null,
					ease: s.ease ?? null
				}))
				.sort((a, b) => a.pct - b.pct);
		},
		addStop() {
			const list = materializeStops();
			const sorted = [...list].sort((a, b) => finite(a.pct) - finite(b.pct));
			const ph = playheadPercent(shaftEl, animName, animSecs);
			const target = ph != null ? Math.round(ph) : widestGapMid(sorted);
			const { a, b, frac } = neighborsAt(sorted, target);
			const ns: IdStop = { id: stopSeq++, pct: target };
			for (const key of POINT_KEYS) {
				if (a[key] || b[key]) ns[key] = lerpPointAt(a[key] ?? baseOf(key), b[key] ?? baseOf(key), frac);
			}
			// Interpolate the reveal fraction too when the neighbours carry it.
			if (a.drawn != null || b.drawn != null) {
				const av = a.drawn ?? 0;
				const bv = b.drawn ?? 1;
				ns.drawn = Math.round((av + (bv - av) * frac) * 1000) / 1000;
			}
			// The new stop splits a→b, so it inherits a's segment easing.
			if (a.ease) ns.ease = a.ease;
			liveStops = [...list, ns];
		},
		removeStop(id: number) {
			const list = materializeStops();
			if (list.length <= 2) return;
			liveStops = list.filter((s) => s.id !== id);
		},
		setPct(id: number, pct: number) {
			const v = Math.max(0, Math.min(100, Math.round(finite(pct))));
			liveStops = materializeStops().map((s) => (s.id === id ? { ...s, pct: v } : s));
		},
		setDrawn(id: number, drawnPct: number | null) {
			liveStops = materializeStops().map((s) => {
				if (s.id !== id) return s;
				if (drawnPct == null) {
					const { drawn: _drop, ...rest } = s;
					return rest as IdStop;
				}
				return { ...s, drawn: Math.max(0, Math.min(1, finite(drawnPct) / 100)) };
			});
		},
		setEase(id: number, ease: string | null) {
			liveStops = materializeStops().map((s) => {
				if (s.id !== id) return s;
				if (!ease) {
					const { ease: _drop, ...rest } = s;
					return rest as IdStop;
				}
				return { ...s, ease: sanitizeEase(ease) };
			});
		},
		preview() {
			const pct = playheadPercent(shaftEl, animName, animSecs);
			if (pct == null) return null;
			let drawn: number | null = null;
			if (revealAnim && shaftEl && typeof getComputedStyle === 'function') {
				const off = parseFloat(getComputedStyle(shaftEl).strokeDashoffset || '');
				if (Number.isFinite(off)) drawn = Math.max(0, Math.min(100, Math.round((1 - off) * 100)));
			}
			return { pct: Math.round(pct), drawn };
		}
	};
</script>

<g
	id={id || undefined}
	class="draw-curve {klass}"
	style={style || undefined}
	aria-label={label}
	role={label ? 'img' : undefined}
>
	{#if isSelected}
		<path class="draw-selglow" d={baseD} />
	{/if}
	{#if animSecs}
		{@html `<style>${keyframesCss}</style>`}
	{/if}
	<path
		bind:this={shaftEl}
		{d}
		fill="none"
		class:draw-anim={drawSecs}
		pathLength={drawSecs || revealAnim ? 1 : undefined}
		style="stroke:{stroke}; stroke-width:{strokeWidth};{drawSecs
			? ` animation-duration:${drawSecs}s;${delaySecs ? ` animation-delay:${delaySecs}s;` : ''}`
			: ''}{revealAnim ? ' stroke-dasharray:1;' : ''}{shaftAnim}"
		stroke-dasharray={drawSecs || revealAnim ? undefined : dasharray}
	/>
	{#if endHead}
		<polygon
			points={geomAnim ? originHead : endHead}
			class:head-anim={drawSecs}
			style="fill:{stroke};{drawSecs
				? ` animation-duration:${drawSecs * 0.2}s; animation-delay:${delaySecs + drawSecs * 0.8}s;`
				: ''}{geomAnim ? animOf('-end') : ''}"
			stroke="none"
		/>
	{/if}
	{#if startHead}
		<polygon
			points={geomAnim ? originHead : startHead}
			class:head-anim={drawSecs}
			style="fill:{stroke};{drawSecs
				? ` animation-duration:${drawSecs * 0.2}s; animation-delay:${delaySecs + drawSecs * 0.8}s;`
				: ''}{geomAnim ? animOf('-start') : ''}"
			stroke="none"
		/>
	{/if}
	{#if labelText && labelXY}
		<text
			class="draw-label"
			class:label-anim={drawSecs}
			x={geomAnim ? 0 : labelXY[0]}
			y={geomAnim ? 0 : labelXY[1]}
			text-anchor="middle"
			style="fill:{stroke};{drawSecs
				? ` animation-duration:${drawSecs * 0.2}s; animation-delay:${delaySecs + drawSecs * 0.8}s;`
				: ''}{geomAnim ? animOf('-label') : ''}">{labelText}</text
		>
	{/if}

	{#if editing}
		<!-- The hit stroke stays HOME even when selected: it only ever competes
		     with other shapes' hit strokes, and raising it would seal off the band
		     where two strokes cross. See Draw's chrome layer. -->
		<!-- svelte-ignore a11y_no_static_element_interactions -->
		<path class="draw-hit" d={baseD} onpointerdown={select} />
		{#if !isHoisted}{@render chrome()}{/if}
	{/if}
</g>

{#snippet chrome()}
	<!-- Editing chrome (never in published output): thin guide lines from each
	     control point to its endpoint(s), endpoint handles, and hollow
	     control-point handles — wrapped so <Draw> can re-parent them whole into
	     its top layer once this shape is selected (select-to-front). -->
	<g class="draw-chrome" data-shape={name || 'Curve'}>
		<path class="draw-guide" d={linePath(C1, F)} />
		<path class="draw-guide" d={C2 ? linePath(C2, T) : linePath(C1, T)} />
		{#if !(geomAnim && S?.some((s) => s.from))}
			<DrawHandle selected={isSelected}
				point={F}
				{grid}
				title="from · Shift = H/V"
				onselect={select}
				onmove={(p) => (liveFrom = p)}
				oncommit={(b, a) => commit((p) => (liveFrom = p), b, a)}
			/>
		{/if}
		{#if !(geomAnim && S?.some((s) => s.to))}
			<DrawHandle selected={isSelected}
				point={T}
				{grid}
				title="to · Shift = H/V"
				onselect={select}
				onmove={(p) => (liveTo = p)}
				oncommit={(b, a) => commit((p) => (liveTo = p), b, a)}
			/>
		{/if}
		{#if !(geomAnim && S?.some((s) => s.c1))}
			<DrawHandle selected={isSelected}
				point={C1}
				{grid}
				kind="control"
				title="c1"
				onselect={select}
				onmove={(p) => (liveC1 = p)}
				oncommit={(b, a) => commit((p) => (liveC1 = p), b, a)}
			/>
		{/if}
		{#if C2 && !(geomAnim && S?.some((s) => s.c2))}
			<DrawHandle selected={isSelected}
				point={C2}
				{grid}
				kind="control"
				title="c2"
				onselect={select}
				onmove={(p) => (liveC2 = p)}
				oncommit={(b, a) => commit((p) => (liveC2 = p), b, a)}
			/>
		{/if}
		{#if geomAnim && S}
			<!-- One handle per stop-defined point; endpoints solid at their
			     lowest-pct stop, control points and later stops hollow. -->
			{#each S as s, i (i)}
				{#each POINT_KEYS as key}
					{#if s[key]}
						<DrawHandle selected={isSelected}
							point={s[key]}
							{grid}
							kind={(key === 'from' || key === 'to') && i === lowestStopFor(key) ? 'point' : 'control'}
							pct={finite(s.pct)}
							{playhead}
							title={`${key} · ${finite(s.pct)}%`}
							onselect={select}
							onmove={(p) => setStop(i, key, p, i === lowestStopFor(key))}
							oncommit={(b, a) => commitStop(i, key, i === lowestStopFor(key), b, a)}
						/>
					{/if}
				{/each}
			{/each}
		{/if}
	</g>
{/snippet}

<style>
	.draw-label {
		stroke: none;
		font-size: var(--draw-font-size, 32px);
	}
	/* Draw-on: the shape draws itself, then arrowheads fade in over the final
	   fifth. Durations/delays come inline from the `draw` prop. */
	path.draw-anim {
		stroke-dasharray: 1;
		stroke-dashoffset: 1;
		animation-name: draw-on;
		animation-timing-function: ease-in-out;
		animation-fill-mode: forwards;
	}
	polygon.head-anim,
	text.label-anim {
		opacity: 0;
		animation-name: head-in;
		animation-timing-function: ease-out;
		animation-fill-mode: forwards;
	}
	@keyframes draw-on {
		to {
			stroke-dashoffset: 0;
		}
	}
	@keyframes head-in {
		to {
			opacity: 1;
		}
	}
	/* Editing chrome (ADJUST mode only). */
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
	}
	/* Thin guide from a control point to the endpoint it steers, so the
	   hollow handles read as what they are. */
	.draw-guide {
		fill: none;
		stroke: var(--ctrl-strong-bg, #2980b9);
		stroke-opacity: 0.6;
		stroke-width: 1.5;
		stroke-dasharray: 4 4;
	}
</style>
