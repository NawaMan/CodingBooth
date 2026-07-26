<!--
  Arc — a circular arc between two canvas points, bent by a single
  human-readable number:

      <Arc from={[400, 540]} to={[1500, 540]} bend={0.3} arrow="both" />

  `bend` is the sagitta (bulge height) as a signed fraction of the chord
  length: 0.5 bulges by half the chord (a semicircle), negative bends to the
  other side (positive is screen-up for a left-to-right arc), 0 degenerates
  to the straight line, and |bend| is clamped to 1. drawCore's arcPath does
  the radius / large-arc / sweep math — raw SVG arc parameters never appear
  here or in a slide's diff.

  ADJUST-mode editing (Phase 3): endpoint handles plus one accent-colored
  BEND handle riding the apex (pointAt 0.5); dragging it perpendicular to
  the chord updates `bend` via the pure inverse bendFromApex — dragging
  across the chord flips the sign. That handle is what makes `bend` the
  right API: the number a human reads in a diff is the number the handle
  drags.

  Arrowheads follow the arc's end tangents and the shaft is trimmed behind
  each head by an exact angular cut (shortenShape), as in Curve.
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
		arcPath,
		arrowHead,
		bendFromApex,
		clampBend,
		defaultArrowSize,
		finite,
		labelPos,
		pointAt,
		polygonPoints,
		reverseShape,
		round,
		samplePath,
		shortenShape,
		unwrapAngles
	} from './drawCore';
	import {
		DRAW_CONTEXT_KEY,
		type AnimEditor,
		type ArcStop,
		type ArrowMode,
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
		/** Sagitta / chord length, signed; clamped to [-1, 1]. */
		bend?: number;
		arrow?: ArrowMode;
		/** Arrowhead size in canvas px; defaults to scale with thickness. */
		arrowSize?: number;
		/** Geometry keyframes: the arc's endpoints and/or `bend` per percent,
		 *  animated over `animate` seconds. Sampled to a fixed-count polyline
		 *  (arc flags don't interpolate), so it prerenders and AnimationBar
		 *  scrubs it; needs ≥2, takes precedence over `draw`. */
		stops?: ArcStop[];
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
		from,
		to,
		bend = 0.25,
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
	let liveBend = $state<number | null>(null);
	type IdStop = ArcStop & { id: number };
	let liveStops = $state<IdStop[] | null>(null);
	let stopSeq = 0;
	let liveDraw = $state<number | null>(null);
	let liveDrawDelay = $state<number | null>(null);
	const F = $derived(liveFrom ?? from);
	const T = $derived(liveTo ?? to);
	const B = $derived(liveBend ?? bend);
	const S = $derived<ArcStop[] | undefined>(liveStops ?? stops);
	const drawVal = $derived(liveDraw ?? draw);
	const drawDelayVal = $derived(liveDrawDelay ?? drawDelay);

	function materializeStops(): IdStop[] {
		if (!liveStops) liveStops = (stops ?? []).map((s) => ({ ...s, id: stopSeq++ }));
		return liveStops;
	}

	// One timeline (`animate`) drives two tracks a stop can carry: geometry
	// (from/to/bend → sampled d: path tween) and `drawn` (keyframed
	// stroke-dashoffset reveal). A stop counts toward each track only if it
	// defines that data, so they stay independent. Either takes precedence
	// over the flat `draw` reveal.
	const hasGeom = (s: ArcStop) => !!(s.from || s.to || s.bend != null);
	const hasDrawn = (s: ArcStop) => s.drawn != null;
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

	const base = $derived<SegmentShape>({ kind: 'arc', from: F, to: T, bend: B });

	// A stop resolved to a full arc PathShape (missing fields → base values).
	function stopShape(s: ArcStop): SegmentShape {
		return { kind: 'arc', from: s.from ?? F, to: s.to ?? T, bend: s.bend ?? B };
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
		shaft.kind === 'arc' ? arcPath(shaft.from, shaft.to, shaft.bend) : arcPath(shaft.from, shaft.to, 0)
	);
	const baseD = $derived(arcPath(F, T, B));

	// Heads sit on the ORIGINAL arc's endpoints and end tangents.
	const endHead = $derived(atEnd ? polygonPoints(arrowHead(T, angleAt(base, 1), size)) : null);
	const startHead = $derived(
		atStart ? polygonPoints(arrowHead(F, angleAt(base, 0) + Math.PI, size)) : null
	);

	const stroke = $derived(color ?? 'var(--draw-stroke, currentColor)');
	const strokeWidth = $derived(thickness ?? 'var(--draw-thickness, 4)');
	const dasharray = $derived(dash === true ? '12 8' : dash === false ? undefined : dash);

	const labelXY = $derived(labelText ? labelPos(base, labelAt, labelOffset) : null);

	// --- Geometry keyframes (see Line.svelte). Arc shafts are SAMPLED to a
	// fixed-count polyline per stop, since arc-command flags don't
	// interpolate; heads/label ride per-stop tangents.
	const uid = newEditorId();
	const animName = `draw-move-${uid}`;
	const deg = (rad: number) => round((rad * 180) / Math.PI);

	function shaftShapeOf(shape: SegmentShape): SegmentShape {
		let s = shape;
		if (atEnd) s = shortenShape(s, size);
		if (atStart) s = reverseShape(shortenShape(reverseShape(s), size));
		return s;
	}

	// A per-stop CSS timing function set INSIDE its keyframe governs the
	// segment starting at that stop; '' inherits the default ease-in-out.
	const tf = (e: string) => (e ? ` animation-timing-function: ${e};` : '');

	const keyframesCss = $derived.by(() => {
		if (!animSecs) return '';
		const frame = (pct: number, body: string) => `${pct}% { ${body} }`;
		let css = '';
		if (geomStops) {
			const shaftFrames = geomStops
				.map((g) => frame(g.pct, `d: path("${samplePath(shaftShapeOf(g.shape))}");${tf(g.ease)}`))
				.join(' ');
			css += `@keyframes ${animName} { ${shaftFrames} }`;
			if (atEnd) {
				// Unwrap the tangent angles across stops so the head takes the SHORTEST
				// rotation between keyframes — an arc's tangent comes back
				// un-normalized (can exceed 2π), which otherwise spins the head a full
				// turn mid-morph.
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
	// ride this arc (see Curve.svelte — same contract, incl. the deliberate
	// init-time capture of `name`).
	// svelte-ignore state_referenced_locally
	if (name && ctx) onDestroy(ctx.registerPathSource(name, () => ({ kind: 'arc', from: F, to: T, bend: B })));

	const apex = $derived(pointAt(base, 0.5));

	// bend keeps 3 decimals (the handle produces fractions); never NaN/-0.
	const fmtBend = (b: number) => String(Math.round((Number.isFinite(b) ? b : 0) * 1000) / 1000 + 0);

	const stopsAttrFor = (list: ArcStop[] | undefined) =>
		list && list.length
			? ` stops={[${list
					.map(
						(s) =>
							`{ pct: ${finite(s.pct)}${s.from ? `, from: ${fmtPoint(s.from)}` : ''}${s.to ? `, to: ${fmtPoint(s.to)}` : ''}${s.bend != null ? `, bend: ${fmtBend(s.bend)}` : ''}${s.drawn != null ? `, drawn: ${fmtNum(s.drawn)}` : ''}${s.ease ? `, ease: "${sanitizeEase(s.ease)}"` : ''} }`
					)
					.join(', ')}]}${animate ? ` animate={${finite(animate)}}` : ''}`
			: '';

	const tagFor = (f: Point, t: Point, b: number, list: ArcStop[] | undefined, dr: number | undefined, dd: number | undefined) =>
		`<Arc${name ? ` name="${name}"` : ''} from={${fmtPoint(f)}} to={${fmtPoint(t)}} bend={${fmtBend(b)}}` +
		stopsAttrFor(list) +
		sharedAttrs({ arrow, arrowSize, color, thickness, dash, label, labelText, labelAt, labelOffset, draw: dr, drawDelay: dd, grid, id, class: klass, style }) +
		' />';
	const snippet = $derived(tagFor(F, T, B, S, drawVal, drawDelayVal));
	const sourceSnippet = $derived(tagFor(from, to, bend, stops, draw, drawDelay));

	const editor: ShapeEditor = {
		id: uid,
		kind: 'Arc',
		get name() {
			return name;
		},
		get readout() {
			return `from ${fmtPoint(F)} → to ${fmtPoint(T)} · bend ${fmtBend(B)}`;
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

	function commit(apply: (p: Point) => void, before: Point, after: Point) {
		record({ undo: () => apply(before), redo: () => apply(after) });
	}

	// --- Editable stops. Endpoints are per-stop point handles; bend is a
	// per-stop apex handle (dragging it perpendicular to the chord retimes
	// that stop's bend via bendFromApex).
	const lowestStopFor = (key: 'from' | 'to') => {
		let best = -1;
		S?.forEach((s, i) => {
			if (s[key] && (best === -1 || finite(s.pct) < finite(S[best].pct))) best = i;
		});
		return best;
	};
	function setStopPoint(i: number, key: 'from' | 'to', p: Point, sync: boolean) {
		liveStops = materializeStops().map((s, k) => (k === i ? { ...s, [key]: p } : s));
		if (sync) {
			if (key === 'from') liveFrom = p;
			else liveTo = p;
		}
	}
	function commitStopPoint(i: number, key: 'from' | 'to', sync: boolean, b: Point, a: Point) {
		record({ undo: () => setStopPoint(i, key, b, sync), redo: () => setStopPoint(i, key, a, sync) });
	}
	function setStopBend(i: number, b: number, sync: boolean) {
		liveStops = materializeStops().map((s, k) => (k === i ? { ...s, bend: b } : s));
		if (sync) liveBend = b;
	}
	function commitStopBend(i: number, sync: boolean, before: number, after: number) {
		record({ undo: () => setStopBend(i, before, sync), redo: () => setStopBend(i, after, sync) });
	}

	$effect(() => {
		if (editing && isSelected && (geomAnim || revealAnim) && !liveStops) materializeStops();
	});

	// Ref to the shaft path, so "+ keyframe" can read the live playhead time.
	let shaftEl = $state<SVGPathElement>();

	// Live playhead % for timeline-aware stop connectors (dashed before, bold
	// near). Polled each frame while editing an animated arc; null otherwise.
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
			if (a.from || b.from) ns.from = lerpPointAt(a.from ?? F, b.from ?? F, frac);
			if (a.to || b.to) ns.to = lerpPointAt(a.to ?? T, b.to ?? T, frac);
			if (a.bend != null || b.bend != null)
				ns.bend = clampBend((a.bend ?? B) + ((b.bend ?? B) - (a.bend ?? B)) * frac);
			if (a.drawn != null || b.drawn != null) {
				const av = a.drawn ?? 0;
				const bv = b.drawn ?? 1;
				ns.drawn = Math.round((av + (bv - av) * frac) * 1000) / 1000;
			}
			if (a.ease) ns.ease = a.ease; // inherit the split segment's easing
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
	class="draw-arc {klass}"
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
	<!-- Editing chrome: endpoint handles and the bend handle riding the apex —
	     wrapped so <Draw> can re-parent them whole into its top layer once this
	     shape is selected (select-to-front). -->
	<g class="draw-chrome" data-shape={name || 'Arc'}>
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
		{#if !(geomAnim && S?.some((s) => s.bend != null))}
			<DrawHandle selected={isSelected}
				point={apex}
				kind="bend"
				title="bend · drag across the chord to flip"
				onselect={select}
				onmove={(p) => (liveBend = bendFromApex(F, T, p))}
				oncommit={(b, a) => {
					const vb = bendFromApex(F, T, b);
					const va = bendFromApex(F, T, a);
					record({ undo: () => (liveBend = vb), redo: () => (liveBend = va) });
				}}
			/>
		{/if}
		{#if geomAnim && S}
			<!-- Per-stop handles: from/to at their positions, and a bend apex
			     handle per stop that animates bend. -->
			{#each S as s, i (i)}
				{#if s.from}
					<DrawHandle selected={isSelected}
						point={s.from}
						{grid}
						kind={i === lowestStopFor('from') ? 'point' : 'control'}
						pct={finite(s.pct)}
						{playhead}
						title={`from · ${finite(s.pct)}%`}
						onselect={select}
						onmove={(p) => setStopPoint(i, 'from', p, i === lowestStopFor('from'))}
						oncommit={(b, a) => commitStopPoint(i, 'from', i === lowestStopFor('from'), b, a)}
					/>
				{/if}
				{#if s.to}
					<DrawHandle selected={isSelected}
						point={s.to}
						{grid}
						kind={i === lowestStopFor('to') ? 'point' : 'control'}
						pct={finite(s.pct)}
						{playhead}
						title={`to · ${finite(s.pct)}%`}
						onselect={select}
						onmove={(p) => setStopPoint(i, 'to', p, i === lowestStopFor('to'))}
						oncommit={(b, a) => commitStopPoint(i, 'to', i === lowestStopFor('to'), b, a)}
					/>
				{/if}
				{#if s.bend != null}
					{@const sf = s.from ?? F}
					{@const st = s.to ?? T}
					<DrawHandle selected={isSelected}
						point={pointAt({ kind: 'arc', from: sf, to: st, bend: s.bend }, 0.5)}
						kind="bend"
						pct={finite(s.pct)}
						{playhead}
						title={`bend · ${finite(s.pct)}%`}
						onselect={select}
						onmove={(p) => setStopBend(i, bendFromApex(sf, st, p), false)}
						oncommit={(b, a) =>
							commitStopBend(i, false, bendFromApex(sf, st, b), bendFromApex(sf, st, a))}
					/>
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
</style>
