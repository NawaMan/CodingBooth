<!--
  Line — a straight segment between two canvas points, with optional
  arrowheads and dashing. Composes inside <Draw>:

      <Line from={[300, 540]} to={[900, 540]} arrow="end" thickness={6} />
      <Line from={[100, 100]} to={[400, 300]} dash />

  Arrowheads are computed polygons, not <marker> defs (settled decision):
  drawCore computes the head triangle from the shaft's end tangent and the
  shaft is shortened behind each head so no stroke pokes past the tip — the
  head's tip lands exactly on `to` (or `from` for arrow="start"). Inline
  polygons inherit the shape's color reliably everywhere.

  ADJUST-mode editing (Phase 3): with the deck's ADJUST control on, each
  endpoint grows a drag handle (Shift locks the drag to H/V from the grab
  point, `grid` quantizes) and clicking the stroke or a handle selects
  the shape into Draw's Copy toolbar. Edits are local finder state — Copy →
  paste is the only persistence — and every completed gesture records to
  the global ADJUST undo/redo.

  All geometry math lives in drawCore.ts (pure, NaN-safe); this component is
  only $derived wiring and SVG markup.

  Note on theming: --draw-thickness themes the stroke width, but the default
  arrowhead size scales with the `thickness` PROP (CSS var values aren't
  readable during SSR) — when theming thickness on arrowed lines, set
  `thickness`/`arrowSize` props for matching heads.
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
		arrowHead,
		defaultArrowSize,
		finite,
		labelPos,
		linePath,
		polygonPoints,
		round,
		segmentAngle,
		shorten,
	} from './drawCore';
	import {
		DRAW_CONTEXT_KEY,
		type AnimEditor,
		type ArrowMode,
		type DrawOnEditor,
		type DrawContext,
		type DrawOnProps,
		type LineStop,
		type PathLabelProps,
		type Point,
		type ShapeEditor,
		type ShapeStyleProps
	} from './types';

	interface Props extends ShapeStyleProps, PathLabelProps, DrawOnProps {
		from: Point;
		to: Point;
		arrow?: ArrowMode;
		/** Arrowhead size in canvas px; defaults to scale with thickness. */
		arrowSize?: number;
		/** Geometry keyframes: the line's endpoints per percent, animated over
		 *  `animate` seconds. CSS-only (d: path() interpolation — the command
		 *  structure always matches, so the browser tweens the numbers), so it
		 *  prerenders and AnimationBar scrubs it; arrowheads and labelText ride
		 *  along via transform keyframes. Needs ≥2 stops; takes precedence over
		 *  `draw`. The base from/to should match the 0% stop (they're the
		 *  static/no-CSS fallback and the ADJUST-editing geometry). */
		stops?: LineStop[];
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
	// mutate these locals (reset on reload), never the props; Copy → paste into
	// the source is the only persistence. Geometry stops are editable too.
	let liveFrom = $state<Point | null>(null);
	let liveTo = $state<Point | null>(null);
	// Editable stops carry an internal id so the keyframe panel's rows stay
	// stable across add/remove/retime; ids are stripped on serialization.
	type IdStop = LineStop & { id: number };
	let liveStops = $state<IdStop[] | null>(null);
	let stopSeq = 0;
	// Live draw-on overrides (panel-editable reveal duration / delay).
	let liveDraw = $state<number | null>(null);
	let liveDrawDelay = $state<number | null>(null);
	const F = $derived(liveFrom ?? from);
	const T = $derived(liveTo ?? to);
	const S = $derived<LineStop[] | undefined>(liveStops ?? stops);
	const drawVal = $derived(liveDraw ?? draw);
	const drawDelayVal = $derived(liveDrawDelay ?? drawDelay);

	// Clone the prop stops into editable id-carrying state on first edit.
	function materializeStops(): IdStop[] {
		if (!liveStops) liveStops = (stops ?? []).map((s) => ({ ...s, id: stopSeq++ }));
		return liveStops;
	}

	// One timeline (`animate`) drives two tracks a stop can carry: geometry
	// (from/to → d: path tween) and `drawn` (keyframed stroke-dashoffset
	// reveal). A stop counts toward each track only if it defines that data,
	// so they stay independent (a reveal-only stop doesn't pin the geometry).
	// Either takes precedence over the flat `draw` reveal.
	const hasGeom = (s: LineStop) => !!(s.from || s.to);
	const hasDrawn = (s: LineStop) => s.drawn != null;
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

	const atEnd = $derived(arrow === 'end' || arrow === 'both');
	const atStart = $derived(arrow === 'start' || arrow === 'both');
	const size = $derived(arrowSize ?? defaultArrowSize(thickness ?? 4));

	// Shaft, shortened behind each head so the stroke never pokes past a tip.
	const shaftEnd = $derived(atEnd ? shorten(F, T, size) : T);
	const shaftStart = $derived(atStart ? shorten(T, F, size) : F);
	const d = $derived(linePath(shaftStart, shaftEnd));

	const endHead = $derived(atEnd ? polygonPoints(arrowHead(T, segmentAngle(F, T), size)) : null);
	const startHead = $derived(
		atStart ? polygonPoints(arrowHead(F, segmentAngle(T, F), size)) : null
	);

	const stroke = $derived(color ?? 'var(--draw-stroke, currentColor)');
	const strokeWidth = $derived(thickness ?? 'var(--draw-thickness, 4)');
	const dasharray = $derived(dash === true ? '12 8' : dash === false ? undefined : dash);

	const labelXY = $derived(labelText ? labelPos({ kind: 'line', from: F, to: T }, labelAt, labelOffset) : null);

	// --- Geometry keyframes: generate one @keyframes set from the stops via
	// the same pure builders the static render uses. The shaft tweens
	// d: path(…) (identical command structure at every stop, so the browser
	// interpolates the numbers); heads and the label ride along on
	// translate/rotate keyframes computed from each stop's endpoints.
	const uid = newEditorId();
	const animName = `draw-move-${uid}`;
	const deg = (rad: number) => round((rad * 180) / Math.PI);

	const geomStops = $derived.by(() => {
		if (!geomAnim || !S) return null;
		return S.filter(hasGeom)
			.map((s) => ({
				pct: Math.max(0, Math.min(100, finite(s.pct))),
				from: s.from ?? F,
				to: s.to ?? T,
				ease: sanitizeEase(s.ease)
			}))
			.sort((a, b) => a.pct - b.pct);
	});

	// A per-stop CSS timing function set INSIDE its keyframe governs the
	// segment starting at that stop; '' inherits the default ease-in-out.
	const tf = (e: string) => (e ? ` animation-timing-function: ${e};` : '');

	const keyframesCss = $derived.by(() => {
		if (!animSecs) return '';
		const frame = (pct: number, body: string) => `${pct}% { ${body} }`;
		let css = '';
		if (geomStops) {
			const shaft = geomStops
				.map((s) => {
					const sf = atStart ? shorten(s.to, s.from, size) : s.from;
					const st = atEnd ? shorten(s.from, s.to, size) : s.to;
					return frame(s.pct, `d: path("${linePath(sf, st)}");${tf(s.ease)}`);
				})
				.join(' ');
			css += `@keyframes ${animName} { ${shaft} }`;
			if (atEnd) {
				const frames = geomStops
					.map((s) =>
						frame(
							s.pct,
							`transform: translate(${round(s.to[0])}px, ${round(s.to[1])}px) rotate(${deg(segmentAngle(s.from, s.to))}deg);${tf(s.ease)}`
						)
					)
					.join(' ');
				css += ` @keyframes ${animName}-end { ${frames} }`;
			}
			if (atStart) {
				const frames = geomStops
					.map((s) =>
						frame(
							s.pct,
							`transform: translate(${round(s.from[0])}px, ${round(s.from[1])}px) rotate(${deg(segmentAngle(s.to, s.from))}deg);${tf(s.ease)}`
						)
					)
					.join(' ');
				css += ` @keyframes ${animName}-start { ${frames} }`;
			}
			if (labelText) {
				const frames = geomStops
					.map((s) => {
						const p = labelPos({ kind: 'line', from: s.from, to: s.to }, labelAt, labelOffset);
						return frame(s.pct, `transform: translate(${p[0]}px, ${p[1]}px);${tf(s.ease)}`);
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

	// While animating, heads/label are drawn at the ORIGIN (tip on 0,0
	// pointing +x; label anchored on 0,0) and positioned entirely by their
	// transform keyframes.
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
	// ride this line (see Curve.svelte — same contract, incl. the deliberate
	// init-time capture of `name`).
	// svelte-ignore state_referenced_locally
	if (name && ctx) onDestroy(ctx.registerPathSource(name, () => ({ kind: 'line', from: F, to: T })));

	const stopsAttrFor = (list: LineStop[] | undefined) =>
		list && list.length
			? ` stops={[${list
					.map(
						(s) =>
							`{ pct: ${finite(s.pct)}${s.from ? `, from: ${fmtPoint(s.from)}` : ''}${s.to ? `, to: ${fmtPoint(s.to)}` : ''}${s.drawn != null ? `, drawn: ${fmtNum(s.drawn)}` : ''}${s.ease ? `, ease: "${sanitizeEase(s.ease)}"` : ''} }`
					)
					.join(', ')}]}${animate ? ` animate={${finite(animate)}}` : ''}`
			: '';

	const tagFor = (f: Point, t: Point, list: LineStop[] | undefined, dr: number | undefined, dd: number | undefined) =>
		`<Line${name ? ` name="${name}"` : ''} from={${fmtPoint(f)}} to={${fmtPoint(t)}}` +
		stopsAttrFor(list) +
		sharedAttrs({ arrow, arrowSize, color, thickness, dash, label, labelText, labelAt, labelOffset, draw: dr, drawDelay: dd, grid, id, class: klass, style }) +
		' />';
	const snippet = $derived(tagFor(F, T, S, drawVal, drawDelayVal));
	const sourceSnippet = $derived(tagFor(from, to, stops, draw, drawDelay));

	const editor: ShapeEditor = {
		id: uid,
		kind: 'Line',
		get name() {
			return name;
		},
		get readout() {
			return `from ${fmtPoint(F)} → to ${fmtPoint(T)}`;
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

	// --- Stop handles: when a point is animated, the stops themselves are
	// what you edit — one handle per stop-defined point (so B gets a
	// connector at its 0% AND its 100% position). The base handle for that
	// point is hidden (redundant with the lowest stop, which stays synced to
	// the base so the static fallback keeps matching the 0% pose).
	const fromAnimated = $derived(!!(geomAnim && S?.some((s) => s.from)));
	const toAnimated = $derived(!!(geomAnim && S?.some((s) => s.to)));
	const lowestStopFor = (key: 'from' | 'to') => {
		let best = -1;
		S?.forEach((s, i) => {
			if (s[key] && (best === -1 || finite(s.pct) < finite(S[best].pct))) best = i;
		});
		return best;
	};

	function setStop(i: number, key: 'from' | 'to', p: Point, syncBase: boolean) {
		liveStops = materializeStops().map((s, k) => (k === i ? { ...s, [key]: p } : s));
		if (syncBase) {
			if (key === 'from') liveFrom = p;
			else liveTo = p;
		}
	}

	function commitStop(i: number, key: 'from' | 'to', sync: boolean, b: Point, a: Point) {
		record({
			undo: () => setStop(i, key, b, sync),
			redo: () => setStop(i, key, a, sync)
		});
	}

	// --- Keyframe editor for the toolbar panel (add / remove / retime stops).
	// Structural edits aren't in the global undo (matching KeyframeStudio's
	// panel) — only drags are. Materialize eagerly while the panel is up so
	// its rows always carry real ids.
	$effect(() => {
		if (editing && isSelected && (geomAnim || revealAnim) && !liveStops) materializeStops();
	});

	// Ref to the shaft path, so "+ keyframe" can read the live playhead time.
	let shaftEl = $state<SVGPathElement>();

	// Live playhead % for timeline-aware stop connectors (dashed before, bold
	// near). Polled each frame while editing an animated line; null otherwise.
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
			const list =
				liveStops ?? (stops ?? []).map((s, i) => ({ ...s, id: -1 - i }) as IdStop);
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
			// Insert at the AnimationBar playhead if it's readable, else the
			// widest-gap midpoint. Geometry is lerped between the bracketing
			// stops at that percent, so the new keyframe lands ON the path.
			const ph = playheadPercent(shaftEl, animName, animSecs);
			const target = ph != null ? Math.round(ph) : widestGapMid(sorted);
			const { a, b, frac } = neighborsAt(sorted, target);
			const ns: IdStop = { id: stopSeq++, pct: target };
			if (a.from || b.from) ns.from = lerpPointAt(a.from ?? F, b.from ?? F, frac);
			if (a.to || b.to) ns.to = lerpPointAt(a.to ?? T, b.to ?? T, frac);
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
	class="draw-line {klass}"
	style={style || undefined}
	aria-label={label}
	role={label ? 'img' : undefined}
>
	{#if isSelected}
		<path class="draw-selglow" d={linePath(F, T)} />
	{/if}
	{#if animSecs}
		<!-- Generated geometry keyframes — SVG <style> is valid markup, and
		     the rules are plain CSS, so this prerenders and scrubs. -->
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
		<!-- The hit stroke stays HOME even when the shape is selected: it is the
		     only chrome that competes with other shapes' hit strokes, and raising
		     it would seal off the band where two strokes cross — the very place a
		     neighbour's stroke is the one you mean to click. -->
		<!-- svelte-ignore a11y_no_static_element_interactions -->
		<path class="draw-hit" d={linePath(F, T)} onpointerdown={select} />
		{#if !isHoisted}{@render chrome()}{/if}
	{/if}
</g>

{#snippet chrome()}
	<!-- The handles, wrapped so <Draw> can re-parent them whole into its top
	     layer once this shape is selected (select-to-front). Rendered inline in
	     the shape's own <g> until then. Never outside ADJUST mode. -->
	<g class="draw-chrome" data-shape={name || 'Line'}>
		{#if !fromAnimated}
			<DrawHandle selected={isSelected}
				point={F}
				{grid}
				title="from · Shift = H/V"
				onselect={select}
				onmove={(p) => (liveFrom = p)}
				oncommit={(b, a) => commit((p) => (liveFrom = p), b, a)}
			/>
		{/if}
		{#if !toAnimated}
			<DrawHandle selected={isSelected}
				point={T}
				{grid}
				title="to · Shift = H/V"
				onselect={select}
				onmove={(p) => (liveTo = p)}
				oncommit={(b, a) => commit((p) => (liveTo = p), b, a)}
			/>
		{/if}
		{#if geomAnim && S}
			<!-- One handle per stop-defined point; the lowest-pct stop is the
			     solid "base pose" handle (kept synced to from/to), later stops
			     are hollow. -->
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
						onmove={(p) => setStop(i, 'from', p, i === lowestStopFor('from'))}
						oncommit={(b, a) => commitStop(i, 'from', i === lowestStopFor('from'), b, a)}
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
						onmove={(p) => setStop(i, 'to', p, i === lowestStopFor('to'))}
						oncommit={(b, a) => commitStop(i, 'to', i === lowestStopFor('to'), b, a)}
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
	}
</style>
