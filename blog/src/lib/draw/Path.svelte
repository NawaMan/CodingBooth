<!--
  Path — one continuous stroke chaining line / curve / arc segments, with
  optional arrowheads, dashing, a self-draw reveal, and geometry keyframes.
  Composes inside <Draw>:

      <Path start={[200, 780]} segments={[
        { to: [500, 780] },                              // straight
        { to: [800, 620], c1: [650, 780] },              // quadratic curve
        { to: [1150, 620], bend: 0.5 },                  // circular arc
        { to: [1450, 780], c1: [1300, 620], c2: [1350, 780] } // cubic curve
      ]} arrow="end" />

  Each segment's start defaults to the previous segment's `to` (or `start` for
  the first). The KIND of each segment follows its control data: `bend` → an
  arc, `c1`(/`c2`) → a Bézier curve, neither → a straight line. All of that
  resolution lives in drawCore's pathShapes (pure, NaN-safe).

  Because it is ONE <path>, the whole route gets ONE `draw`/`drawDelay` reveal,
  ONE arrowhead at the real end, and joins that MEET (round linejoins).

  Geometry keyframes (`stops` + `animate`): the whole chain morphs between poses
  on the AnimationBar timeline. A single Line/Curve/Arc can tween `d: path()`
  exactly, but a Path's command structure varies across segments (and arc flags
  don't interpolate), so — like Arc — the geometry track SAMPLES each pose into a
  fixed-count polyline (drawCore.sampleMultiPath) that morphs smoothly. The
  static (no-CSS) render still uses the exact multiPath, and prerenders.

  ADJUST-mode editing (like Line/Curve/Arc): every vertex grows a handle — the
  `start`, each segment's `to`, a control handle per Bézier control point, an
  accent bend handle at each arc's apex; when animating, one handle per stop
  pose instead. Drag to reshape, then Copy the whole `<Path start=… segments=…>`
  tag (with `stops`/`animate`) back over the source. Edits are finder state
  (reset on reload; Copy → paste / dev "Save" is the only persistence) and every
  completed drag records to the ADJUST undo/redo.

  All geometry math is in drawCore.ts (pure, NaN-safe); this component is only
  $derived wiring and SVG markup.
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
		bendFromApex,
		defaultArrowSize,
		finite,
		labelPosMulti,
		linePath,
		multiPath,
		pathShapes,
		pointAt,
		polygonPoints,
		reverseShape,
		round,
		sampleMultiPath,
		shortenShape,
		unwrapAngles
	} from './drawCore';
	import {
		DRAW_CONTEXT_KEY,
		type AnimEditor,
		type ArrowMode,
		type DrawContext,
		type DrawOnEditor,
		type DrawOnProps,
		type PathLabelProps,
		type PathSegment,
		type PathShape,
		type PathStop,
		type Point,
		type SegmentShape,
		type ShapeEditor,
		type ShapeStyleProps
	} from './types';

	interface Props extends ShapeStyleProps, PathLabelProps, DrawOnProps {
		/** The pen's starting point (canvas px) — the first segment's default
		 *  `from`. */
		start: Point;
		/** The chained segments; see PathSegment. */
		segments: PathSegment[];
		arrow?: ArrowMode;
		/** Arrowhead size in canvas px; defaults to scale with thickness. */
		arrowSize?: number;
		/** Geometry keyframes: the whole path's pose per percent, morphed over
		 *  `animate` seconds. Needs ≥2 geometry stops; takes precedence over
		 *  `draw`. The base start/segments should match the 0% stop (the
		 *  static/no-CSS fallback and the ADJUST-editing geometry). */
		stops?: PathStop[];
		/** Seconds for one pass through `stops` (ease-in-out, fill both). */
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
		start,
		segments,
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

	// ADJUST-mode editing overrides: the editor is a coordinate FINDER — drags
	// mutate these locals (reset on reload), never the props; Copy → paste is
	// the only persistence.
	let liveStart = $state<Point | null>(null);
	let liveSegments = $state<PathSegment[] | null>(null);
	type IdStop = PathStop & { id: number };
	let liveStops = $state<IdStop[] | null>(null);
	let stopSeq = 0;
	let liveDraw = $state<number | null>(null);
	let liveDrawDelay = $state<number | null>(null);
	const START = $derived(liveStart ?? start);
	const SEGS = $derived<PathSegment[]>(liveSegments ?? segments ?? []);
	const S = $derived<PathStop[] | undefined>(liveStops ?? stops);
	const drawVal = $derived(liveDraw ?? draw);
	const drawDelayVal = $derived(liveDrawDelay ?? drawDelay);

	function materializeSegs(): PathSegment[] {
		if (!liveSegments) liveSegments = (segments ?? []).map((s) => ({ ...s }));
		return liveSegments;
	}
	function materializeStops(): IdStop[] {
		if (!liveStops) liveStops = (stops ?? []).map((s) => ({ ...s, id: stopSeq++ }));
		return liveStops;
	}

	// One timeline (`animate`) drives two tracks a stop can carry: geometry
	// (start/segments → the sampled d: path tween) and `drawn` (keyframed
	// stroke-dashoffset reveal). A stop counts toward each track only if it
	// defines that data, so the two are independent. Either takes precedence
	// over the flat `draw` reveal.
	const hasGeom = (s: PathStop) => !!(s.start || s.segments);
	const hasDrawn = (s: PathStop) => s.drawn != null;
	const geomStopsActive = $derived(!!(S && S.filter(hasGeom).length >= 2));
	const revealActive = $derived(!!(S && S.filter(hasDrawn).length >= 2));
	const animSecs = $derived(
		animate && Number.isFinite(animate) && animate > 0 && (geomStopsActive || revealActive)
			? animate
			: null
	);
	const geomAnim = $derived(animSecs != null && geomStopsActive);
	const revealAnim = $derived(animSecs != null && revealActive);

	// Draw-on: pathLength=1 normalizes any path so the dash trick needs no DOM
	// measurement (SSR-safe); the animation then owns the dash pattern.
	const drawSecs = $derived(
		!animSecs && drawVal && Number.isFinite(drawVal) && drawVal > 0 ? drawVal : null
	);
	const delaySecs = $derived(
		drawSecs && drawDelayVal && Number.isFinite(drawDelayVal) && drawDelayVal > 0 ? drawDelayVal : 0
	);

	const shapes = $derived(pathShapes(START, SEGS));
	const baseD = $derived(multiPath(shapes));

	const atEnd = $derived(arrow === 'end' || arrow === 'both');
	const atStart = $derived(arrow === 'start' || arrow === 'both');
	const size = $derived(arrowSize ?? defaultArrowSize(thickness ?? 4));

	// Trim ONLY the last shape's tail and the first shape's start behind their
	// heads, so the single `d` never pokes past a tip — middle joins untouched.
	function shaftShapesOf(list: SegmentShape[]): SegmentShape[] {
		if (list.length === 0) return list;
		const out = [...list];
		const last = out.length - 1;
		if (atEnd) out[last] = shortenShape(out[last], size);
		if (atStart) out[0] = reverseShape(shortenShape(reverseShape(out[0]), size));
		return out;
	}
	const shaftShapes = $derived(shaftShapesOf(shapes));
	const d = $derived(multiPath(shaftShapes));

	// Heads sit on the ORIGINAL end/start points and end tangents.
	const endShape = $derived(shapes.length ? shapes[shapes.length - 1] : null);
	const startShape = $derived(shapes.length ? shapes[0] : null);
	const endHead = $derived(
		atEnd && endShape ? polygonPoints(arrowHead(endShape.to, angleAt(endShape, 1), size)) : null
	);
	const startHead = $derived(
		atStart && startShape
			? polygonPoints(arrowHead(startShape.from, angleAt(startShape, 0) + Math.PI, size))
			: null
	);

	const stroke = $derived(color ?? 'var(--draw-stroke, currentColor)');
	const strokeWidth = $derived(thickness ?? 'var(--draw-thickness, 4)');
	const dasharray = $derived(dash === true ? '12 8' : dash === false ? undefined : dash);

	const labelXY = $derived(labelText ? labelPosMulti(shapes, labelAt, labelOffset) : null);

	// --- Geometry keyframes: resolve each geometry stop to a full pose, then
	// generate one @keyframes set. The shaft tweens `d: path(sampled polyline)`
	// (constant command structure at every stop → the browser interpolates the
	// numbers); heads/label ride along on translate/rotate keyframes.
	const clampPct = (p: number) => Math.max(0, Math.min(100, finite(p)));
	const poseStart = (s: PathStop) => s.start ?? START;
	const poseSegs = (s: PathStop) => s.segments ?? SEGS;
	const poseShapes = (s: PathStop) => pathShapes(poseStart(s), poseSegs(s));

	const geomStops = $derived.by(() => {
		if (!geomAnim || !S) return null;
		return S.filter(hasGeom)
			.map((s) => ({ pct: clampPct(s.pct), shapes: poseShapes(s), ease: sanitizeEase(s.ease) }))
			.sort((a, b) => a.pct - b.pct);
	});

	const uid = newEditorId();
	const animName = `draw-move-${uid}`;
	const deg = (rad: number) => round((rad * 180) / Math.PI);
	const tf = (e: string) => (e ? ` animation-timing-function: ${e};` : '');

	const keyframesCss = $derived.by(() => {
		if (!animSecs) return '';
		const frame = (pct: number, body: string) => `${pct}% { ${body} }`;
		let css = '';
		if (geomStops) {
			const shaftFrames = geomStops
				.map((g) => frame(g.pct, `d: path("${sampleMultiPath(shaftShapesOf(g.shapes))}");${tf(g.ease)}`))
				.join(' ');
			css += `@keyframes ${animName} { ${shaftFrames} }`;
			if (atEnd) {
				// Unwrap the tangent angles across stops so the head takes the SHORTEST
				// rotation between keyframes — an arc's end tangent comes back
				// un-normalized (can exceed 2π), which otherwise spins the head a full
				// turn mid-morph.
				const angles = unwrapAngles(
					geomStops.map((g) => {
						const last = g.shapes[g.shapes.length - 1];
						return last ? angleAt(last, 1) : 0;
					})
				);
				const frames = geomStops
					.map((g, i) => {
						const last = g.shapes[g.shapes.length - 1];
						const p = last ? last.to : [0, 0];
						return frame(g.pct, `transform: translate(${round(p[0])}px, ${round(p[1])}px) rotate(${deg(angles[i])}deg);${tf(g.ease)}`);
					})
					.join(' ');
				css += ` @keyframes ${animName}-end { ${frames} }`;
			}
			if (atStart) {
				const angles = unwrapAngles(
					geomStops.map((g) => {
						const first = g.shapes[0];
						return first ? angleAt(first, 0) + Math.PI : 0;
					})
				);
				const frames = geomStops
					.map((g, i) => {
						const first = g.shapes[0];
						const p = first ? first.from : [0, 0];
						return frame(g.pct, `transform: translate(${round(p[0])}px, ${round(p[1])}px) rotate(${deg(angles[i])}deg);${tf(g.ease)}`);
					})
					.join(' ');
				css += ` @keyframes ${animName}-start { ${frames} }`;
			}
			if (labelText) {
				const frames = geomStops
					.map((g) => {
						const p = labelPosMulti(g.shapes, labelAt, labelOffset);
						return frame(g.pct, `transform: translate(${p[0]}px, ${p[1]}px);${tf(g.ease)}`);
					})
					.join(' ');
				css += ` @keyframes ${animName}-label { ${frames} }`;
			}
		}
		if (revealAnim && S) {
			const frames = S.filter(hasDrawn)
				.map((s) => ({
					pct: clampPct(s.pct),
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

	// While animating, heads are drawn at the ORIGIN (tip on 0,0 pointing +x;
	// label anchored on 0,0) and positioned entirely by their transform frames.
	const originHead = $derived(polygonPoints(arrowHead([0, 0], 0, size)));
	const animOf = (suffix: string) => ` animation: ${animName}${suffix} ${animSecs}s ease-in-out both;`;
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

	// pathShapes drops a malformed (no-`to`) segment — TS forbids it, so it only
	// happens on runtime junk. When it does, shapes no longer line up 1:1 with
	// SEGS, so per-segment handles would mis-map; disable them.
	const editable = $derived(shapes.length === SEGS.length);
	const showStart = $derived(shapes.length > 0 && !SEGS[0]?.from);

	const fmtBend = (b: number) => String(Math.round((Number.isFinite(b) ? b : 0) * 1000) / 1000 + 0);

	const segLiteral = (s: PathSegment) => {
		const parts: string[] = [];
		if (s.from) parts.push(`from: ${fmtPoint(s.from)}`);
		parts.push(`to: ${fmtPoint(s.to)}`);
		if (s.bend != null) parts.push(`bend: ${fmtBend(s.bend)}`);
		else {
			if (s.c1) parts.push(`c1: ${fmtPoint(s.c1)}`);
			if (s.c2) parts.push(`c2: ${fmtPoint(s.c2)}`);
		}
		return `{ ${parts.join(', ')} }`;
	};
	const segsLiteral = (list: PathSegment[]) => `[${list.map(segLiteral).join(', ')}]`;
	const stopLiteral = (s: PathStop) =>
		`{ pct: ${finite(s.pct)}${s.start ? `, start: ${fmtPoint(s.start)}` : ''}${s.segments ? `, segments: ${segsLiteral(s.segments)}` : ''}${s.drawn != null ? `, drawn: ${fmtNum(s.drawn)}` : ''}${s.ease ? `, ease: "${sanitizeEase(s.ease)}"` : ''} }`;
	const stopsAttrFor = (list: PathStop[] | undefined) =>
		list && list.length
			? ` stops={[${list.map(stopLiteral).join(', ')}]}${animate ? ` animate={${finite(animate)}}` : ''}`
			: '';

	const tagFor = (st: Point, list: PathSegment[], sl: PathStop[] | undefined, dr: number | undefined, dd: number | undefined) =>
		`<Path${name ? ` name="${name}"` : ''} start={${fmtPoint(st)}} segments={${segsLiteral(list)}}` +
		stopsAttrFor(sl) +
		sharedAttrs({ arrow, arrowSize, color, thickness, dash, label, labelText, labelAt, labelOffset, draw: dr, drawDelay: dd, grid, id, class: klass, style }) +
		' />';
	const snippet = $derived(tagFor(START, SEGS, S, drawVal, drawDelayVal));
	const sourceSnippet = $derived(tagFor(start, segments ?? [], stops, draw, drawDelay));

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

	const editor: ShapeEditor = {
		id: uid,
		kind: 'Path',
		get name() {
			return name;
		},
		get readout() {
			return `start ${fmtPoint(START)} · ${shapes.length} segment${shapes.length === 1 ? '' : 's'}`;
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
			return geomAnim || revealAnim ? animApi : null;
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

	// --- Static-geometry setters + undo/redo. ---------------------------------
	type PointKey = 'from' | 'to' | 'c1' | 'c2';
	function setStart(p: Point) {
		liveStart = p;
	}
	function commitStart(before: Point, after: Point) {
		record({ undo: () => setStart(before), redo: () => setStart(after) });
	}
	function setSeg(i: number, key: PointKey, p: Point) {
		liveSegments = materializeSegs().map((s, k) => (k === i ? { ...s, [key]: p } : s));
	}
	function commitSeg(i: number, key: PointKey, before: Point, after: Point) {
		record({ undo: () => setSeg(i, key, before), redo: () => setSeg(i, key, after) });
	}
	function setSegBend(i: number, b: number) {
		liveSegments = materializeSegs().map((s, k) => (k === i ? { ...s, bend: b } : s));
	}
	function commitSegBend(i: number, before: number, after: number) {
		record({ undo: () => setSegBend(i, before), redo: () => setSegBend(i, after) });
	}

	// --- Per-stop pose setters (editing an animated Path). Editing the
	// lowest-pct geometry stop also syncs the base start/segments, so the static
	// (0%) fallback keeps matching (the Line/Curve strategy).
	const lowestGeomStop = $derived.by(() => {
		let best = -1;
		S?.forEach((s, i) => {
			if (hasGeom(s) && (best === -1 || finite(s.pct) < finite(S[best].pct))) best = i;
		});
		return best;
	});
	function setStopStart(i: number, p: Point, sync: boolean) {
		liveStops = materializeStops().map((s, k) => (k === i ? { ...s, start: p } : s));
		if (sync) liveStart = p;
	}
	function commitStopStart(i: number, sync: boolean, before: Point, after: Point) {
		record({ undo: () => setStopStart(i, before, sync), redo: () => setStopStart(i, after, sync) });
	}
	function setStopSeg(i: number, j: number, key: PointKey, p: Point, sync: boolean) {
		liveStops = materializeStops().map((s, k) => {
			if (k !== i) return s;
			const segs = (s.segments ?? SEGS).map((seg) => ({ ...seg }));
			segs[j] = { ...segs[j], [key]: p };
			return { ...s, segments: segs };
		});
		if (sync) setSeg(j, key, p);
	}
	function commitStopSeg(i: number, j: number, key: PointKey, sync: boolean, before: Point, after: Point) {
		record({ undo: () => setStopSeg(i, j, key, before, sync), redo: () => setStopSeg(i, j, key, after, sync) });
	}
	function setStopSegBend(i: number, j: number, b: number, sync: boolean) {
		liveStops = materializeStops().map((s, k) => {
			if (k !== i) return s;
			const segs = (s.segments ?? SEGS).map((seg) => ({ ...seg }));
			segs[j] = { ...segs[j], bend: b };
			return { ...s, segments: segs };
		});
		if (sync) setSegBend(j, b);
	}
	function commitStopSegBend(i: number, j: number, sync: boolean, before: number, after: number) {
		record({ undo: () => setStopSegBend(i, j, before, sync), redo: () => setStopSegBend(i, j, after, sync) });
	}

	$effect(() => {
		if (editing && isSelected && (geomAnim || revealAnim) && !liveStops) materializeStops();
	});

	// Ref to the shaft path, so "+ keyframe" can read the live playhead time.
	let shaftEl = $state<SVGPathElement>();
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

	// --- Keyframe editor for the toolbar panel (add / remove / retime stops).
	function lerpSeg(a: PathSegment, b: PathSegment, frac: number): PathSegment {
		const out: PathSegment = { to: lerpPointAt(a.to, b.to, frac) ?? a.to };
		if (a.from || b.from) out.from = lerpPointAt(a.from ?? a.to, b.from ?? b.to, frac);
		if (a.bend != null || b.bend != null) {
			const av = a.bend ?? 0;
			out.bend = Math.round((av + ((b.bend ?? 0) - av) * frac) * 1000) / 1000;
		} else {
			if (a.c1 || b.c1) out.c1 = lerpPointAt(a.c1, b.c1, frac);
			if (a.c2 || b.c2) out.c2 = lerpPointAt(a.c2, b.c2, frac);
		}
		return out;
	}

	const animApi: AnimEditor = {
		get stops() {
			const list = liveStops ?? (stops ?? []).map((s, i) => ({ ...s, id: -1 - i }) as IdStop);
			return list
				.map((s) => ({
					id: s.id,
					pct: Math.round(finite(s.pct)),
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
			if (a.start || b.start) ns.start = lerpPointAt(a.start ?? START, b.start ?? START, frac);
			if (a.segments || b.segments) {
				const aseg = a.segments ?? SEGS;
				const bseg = b.segments ?? SEGS;
				ns.segments = aseg.map((seg, j) => lerpSeg(seg, bseg[j] ?? seg, frac));
			}
			if (a.drawn != null || b.drawn != null) {
				const av = a.drawn ?? 0;
				const bv = b.drawn ?? 1;
				ns.drawn = Math.round((av + (bv - av) * frac) * 1000) / 1000;
			}
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

{#if d}
	<g
		id={id || undefined}
		class="draw-path {klass}"
		style={style || undefined}
		aria-label={label}
		role={label ? 'img' : undefined}
	>
		{#if isSelected}
			<path class="draw-selglow" d={baseD} />
		{/if}
		{#if animSecs}
			<!-- Generated geometry/reveal keyframes — SVG <style> is valid markup,
			     and the rules are plain CSS, so this prerenders and scrubs. -->
			{@html `<style>${keyframesCss}</style>`}
		{/if}
		<path
			bind:this={shaftEl}
			class="draw-path-shaft"
			class:draw-anim={drawSecs}
			{d}
			fill="none"
			pathLength={drawSecs || revealAnim ? 1 : undefined}
			style="stroke:{stroke}; stroke-width:{strokeWidth};{drawSecs
				? ` animation-duration:${drawSecs}s;${delaySecs ? ` animation-delay:${delaySecs}s;` : ''}`
				: ''}{revealAnim ? ' stroke-dasharray:1;' : ''}{shaftAnim}"
			stroke-dasharray={drawSecs || revealAnim ? undefined : dasharray}
			stroke-linejoin="round"
			stroke-linecap="round"
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
{/if}

{#snippet chrome()}
	<!-- Editing chrome (never in published output): guide lines and one handle
	     per vertex — wrapped so <Draw> can re-parent them whole into its top
	     layer once this shape is selected (select-to-front). -->
	<g class="draw-chrome" data-shape={name || 'Path'}>
		{#if !geomAnim}
			<!-- Static handles: one per vertex — start, each `to`, controls, and
			     an accent bend handle at each arc's apex. -->
			{#if showStart}
				<DrawHandle
					selected={isSelected}
					point={START}
					{grid}
					title="start · Shift = H/V"
					onselect={select}
					onmove={(p) => setStart(p)}
					oncommit={(b, a) => commitStart(b, a)}
				/>
			{/if}
			{#if editable}
				{#each shapes as shape, i (i)}
					{@const seg = SEGS[i]}
					{#if shape.kind === 'quadratic'}
						<path class="draw-guide" d={linePath(shape.c1, shape.from)} />
						<path class="draw-guide" d={linePath(shape.c1, shape.to)} />
					{:else if shape.kind === 'cubic'}
						<path class="draw-guide" d={linePath(shape.c1, shape.from)} />
						<path class="draw-guide" d={linePath(shape.c2, shape.to)} />
					{/if}
					{#if seg.from}
						<DrawHandle
							selected={isSelected}
							point={shape.from}
							{grid}
							title={`segment ${i + 1} · from (sub-path) · Shift = H/V`}
							onselect={select}
							onmove={(p) => setSeg(i, 'from', p)}
							oncommit={(b, a) => commitSeg(i, 'from', b, a)}
						/>
					{/if}
					<DrawHandle
						selected={isSelected}
						point={shape.to}
						{grid}
						title={`segment ${i + 1} · to · Shift = H/V`}
						onselect={select}
						onmove={(p) => setSeg(i, 'to', p)}
						oncommit={(b, a) => commitSeg(i, 'to', b, a)}
					/>
					{#if shape.kind === 'quadratic' || shape.kind === 'cubic'}
						<DrawHandle
							selected={isSelected}
							point={shape.c1}
							{grid}
							kind="control"
							title={`segment ${i + 1} · c1`}
							onselect={select}
							onmove={(p) => setSeg(i, 'c1', p)}
							oncommit={(b, a) => commitSeg(i, 'c1', b, a)}
						/>
					{/if}
					{#if shape.kind === 'cubic'}
						<DrawHandle
							selected={isSelected}
							point={shape.c2}
							{grid}
							kind="control"
							title={`segment ${i + 1} · c2`}
							onselect={select}
							onmove={(p) => setSeg(i, 'c2', p)}
							oncommit={(b, a) => commitSeg(i, 'c2', b, a)}
						/>
					{/if}
					{#if shape.kind === 'arc'}
						<DrawHandle
							selected={isSelected}
							point={pointAt(shape, 0.5)}
							kind="bend"
							title={`segment ${i + 1} · bend · drag across the chord to flip`}
							onselect={select}
							onmove={(p) => setSegBend(i, bendFromApex(shape.from, shape.to, p))}
							oncommit={(b, a) =>
								commitSegBend(i, bendFromApex(shape.from, shape.to, b), bendFromApex(shape.from, shape.to, a))}
						/>
					{/if}
				{/each}
			{/if}
		{:else if S}
			<!-- Animated: one handle set per stop pose. The lowest-pct stop is
			     the solid "base pose" (kept synced to start/segments); later
			     stops are hollow, timeline-styled (dashed before the playhead). -->
			{#each S as s, i (i)}
				{#if hasGeom(s)}
					{@const pose = poseShapes(s)}
					{@const solid = i === lowestGeomStop}
					{@const kind = solid ? 'point' : 'control'}
					<DrawHandle
						selected={isSelected}
						point={poseStart(s)}
						{grid}
						{kind}
						pct={clampPct(s.pct)}
						{playhead}
						title={`start · ${clampPct(s.pct)}%`}
						onselect={select}
						onmove={(p) => setStopStart(i, p, solid)}
						oncommit={(b, a) => commitStopStart(i, solid, b, a)}
					/>
					{#if pose.length === poseSegs(s).length}
						{#each pose as shape, j (j)}
							<DrawHandle
								selected={isSelected}
								point={shape.to}
								{grid}
								{kind}
								pct={clampPct(s.pct)}
								{playhead}
								title={`segment ${j + 1} · to · ${clampPct(s.pct)}%`}
								onselect={select}
								onmove={(p) => setStopSeg(i, j, 'to', p, solid)}
								oncommit={(b, a) => commitStopSeg(i, j, 'to', solid, b, a)}
							/>
							{#if shape.kind === 'quadratic' || shape.kind === 'cubic'}
								<DrawHandle
									selected={isSelected}
									point={shape.c1}
									{grid}
									kind="control"
									pct={clampPct(s.pct)}
									{playhead}
									title={`segment ${j + 1} · c1 · ${clampPct(s.pct)}%`}
									onselect={select}
									onmove={(p) => setStopSeg(i, j, 'c1', p, solid)}
									oncommit={(b, a) => commitStopSeg(i, j, 'c1', solid, b, a)}
								/>
							{/if}
							{#if shape.kind === 'cubic'}
								<DrawHandle
									selected={isSelected}
									point={shape.c2}
									{grid}
									kind="control"
									pct={clampPct(s.pct)}
									{playhead}
									title={`segment ${j + 1} · c2 · ${clampPct(s.pct)}%`}
									onselect={select}
									onmove={(p) => setStopSeg(i, j, 'c2', p, solid)}
									oncommit={(b, a) => commitStopSeg(i, j, 'c2', solid, b, a)}
								/>
							{/if}
							{#if shape.kind === 'arc'}
								<DrawHandle
									selected={isSelected}
									point={pointAt(shape, 0.5)}
									kind="bend"
									pct={clampPct(s.pct)}
									{playhead}
									title={`segment ${j + 1} · bend · ${clampPct(s.pct)}%`}
									onselect={select}
									onmove={(p) => setStopSegBend(i, j, bendFromApex(shape.from, shape.to, p), solid)}
									oncommit={(b, a) =>
										commitStopSegBend(i, j, solid, bendFromApex(shape.from, shape.to, b), bendFromApex(shape.from, shape.to, a))}
								/>
							{/if}
						{/each}
					{/if}
				{/if}
			{/each}
		{/if}
	</g>
{/snippet}

<style>
	.draw-label {
		stroke: none;
		font-size: var(--draw-font-size, 32px);
	}
	/* Draw-on: the whole stroke draws itself, then the arrowhead(s)/label fade
	   in over the final fifth. Durations/delays come inline from `draw`. */
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
	/* Editing chrome (ADJUST mode only): the hit stroke re-enables pointer
	   events on just this shape's stroke; the glow marks the selected shape;
	   the guide connects a Bézier control point to the endpoint it steers. */
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
	.draw-guide {
		fill: none;
		stroke: var(--ctrl-strong-bg, #2980b9);
		stroke-opacity: 0.6;
		stroke-width: 1.5;
		stroke-dasharray: 4 4;
	}
</style>
