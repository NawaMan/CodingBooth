<!--
  Sprite — a positioned, rotatable HTML element that flies along a path of
  keyframe stops. This is the KeyframeStudio "flying element" folded into the
  Draw family, so ONE surface authors both SVG shapes AND moving HTML sprites
  on one timeline:

      <Draw title="Launch">
        <Sprite name="rocket" animate={2.5} fontScale={0.84}
          stops={[
            { pct: 0,   x: 0,    y: 1025, w: 56,  h: 55,  rot: 20, ease: "ease-in"  },
            { pct: 100, x: 1528, y: 432,  w: 228, h: 219, rot: -45 },
          ]}>🚀</Sprite>
        <Line from={[…]} to={[…]} draw={2.5} />   (draws itself on the SAME bar)
      </Draw>

  HOW IT FITS THE DRAW FAMILY: like Line/Curve/Arc, the Sprite renders its own
  content + generated CSS @keyframes and only REGISTERS a ShapeEditor for
  selection / Copy — Draw hosts nothing for it. The one twist is that the
  visual is HTML, not SVG, so the moving element rides in a <foreignObject>
  spanning the canvas (SVG user units == canvas px, so a stop's x/y/w/h are
  the element's left/top/width/height with no math). The animation is pure CSS
  (left/top/width/height/transform + per-stop easing), so it prerenders and
  the AnimationBar scrubs it exactly like every other shape's animation —
  no Web Animations API, unlike the standalone KeyframeStudio.

  PATH MODE: `path={PathShape}` replaces the discrete stops with a real curve
  (line/quadratic/cubic/arc/polyline). The sprite SAMPLES it internally —
  pointAt for its centre, angleAt for the tangent it banks to (`orient`),
  `samples` frames, angle-unwrapped so the glyph never spin-flips — and
  everything downstream is the same generated CSS. In ADJUST the EDITOR is the
  curve itself: from/to + control handles like a <Curve>'s (apex grip for an
  arc, one handle per waypoint for a polyline), re-routing the flight live; no
  per-stop ghosts, no keyframe panel, and Copy/SAVE carry the literal points.

  `orient` banks the glyph to the tangent (great for a nose-up 🚀/▲). For a
  SIDE-VIEW glyph (🚚/🚗) that would flip upside down on right-to-left stretches,
  `upright` instead keeps it level and MIRRORS it to face travel — see the prop.

  ADJUST-mode editing (stop mode): each stop grows a ghost box with a MOVE
  handle (drag to reposition), a RESIZE handle (bottom-right corner) and a
  ROTATE handle; the keyframe panel retimes / adds / removes stops and sets
  per-stop easing, just like the path shapes. Geometry is edited by DRAGGING (the Draw convention),
  so the panel needs no l/t/w/h fields. Edits are finder state — Copy → paste
  is the only persistence — and every completed drag records to ADJUST undo.

  The moving element is pointer-events:none (the surface never eats input);
  only the ADJUST handles re-enable the pointer, and only in ADJUST mode.
-->
<script lang="ts">
	import { getContext, onDestroy, setContext, untrack, type Snippet } from 'svelte';
	import { browser } from '$app/environment';
	import { record } from '$lib/stores/adjustHistory';
	import DrawHandle from './DrawHandle.svelte';
	import {
		fmtNum,
		fmtPoint,
		neighborsAt,
		newEditorId,
		playheadPercent,
		sanitizeEase,
		widestGapMid
	} from './editing';
	import {
		angleAt,
		arcPath,
		bendFromApex,
		curvePath,
		finite,
		linePath,
		pointAt,
		polylinePath,
		round,
		smoothPath,
		uniformLengthParams
	} from './drawCore';
	import {
		DRAW_CONTEXT_KEY,
		SPRITE_ISOLATION_KEY,
		type AnimEditor,
		type DrawContext,
		type PathShape,
		type Point,
		type ShapeEditor,
		type SpriteIsolation,
		type SpriteStop
	} from './types';

	interface Props {
		/** Geometry keyframes: the box (x/y/w/h + rot) per percent. Needs ≥2 to
		 *  animate; a single stop renders a static element. Ignored when `path`
		 *  is set. */
		stops?: SpriteStop[];
		/** Follow a real CURVE instead of discrete stops: the sprite samples this
		 *  shape internally (`pointAt` for its centre, `angleAt` for the tangent)
		 *  into generated keyframes, so the flight is smooth and the slide never
		 *  sees a stop. In ADJUST the EDITOR is the curve itself — endpoint /
		 *  control-point handles like a <Curve>'s, no per-stop ghosts — and the
		 *  flight re-routes live as the curve is dragged. Takes precedence over
		 *  `stops`.
		 *
		 *  A `polyline` kind rides waypoints — straight segments (the heading
		 *  SNAPS at each corner; angle-unwrapped, but abrupt by nature) or, with
		 *  `smooth: true`, a Catmull-Rom through every point. Bump `samples` on
		 *  long many-cornered routes so corners don't round off in the sampling.
		 *
		 *  Also takes a NAME (`path="road"`): the sprite then rides the named
		 *  Line/Curve/Arc/Polyline in the same <Draw>, sharing its live geometry — one
		 *  curve authored once, flight and stroke always in step. The named
		 *  shape must come EARLIER in the markup (Connector's rule); an unknown
		 *  name renders no flight, never a broken one. In this mode the sprite
		 *  grows NO editor of its own — drag the named shape's handles, and its
		 *  tag is the single source of truth for Copy/SAVE. */
		path?: PathShape | string;
		/** Box size (canvas px) while riding `path`: one number = square, or
		 *  [w, h]. The box's CENTRE rides the path. */
		size?: number | [number, number];
		/** Bank to the path's tangent as it travels (path mode default). false =
		 *  keep the glyph at its fixed `rotate`, no banking. */
		orient?: boolean;
		/** UPRIGHT mode (path mode; opt-in, default off). For a SIDE-VIEW glyph —
		 *  a vehicle, a runner — that must never roll onto its roof. `orient`
		 *  banks a glyph by pure rotation, which flips a side glyph UPSIDE DOWN
		 *  wherever the path heads right-to-left (no rotation both points the nose
		 *  backward AND keeps the roof up — that needs a mirror). `upright` instead
		 *  keeps the glyph LEVEL and MIRRORS it (`scaleX(-1)`) to face its
		 *  direction of travel, flipping at each turnaround. It OVERRIDES `orient`
		 *  (upright never banks). CONVENTION: the glyph faces LEFT at `rotate` 0
		 *  (as 🚚/🚗/🏎️ commonly do), so it is mirrored while travelling rightward;
		 *  a right-facing glyph rides facing backward (swap it for a left-facing
		 *  one). CSS-only, so it still prerenders and scrubs; the mirror tweens
		 *  over one sample at a turnaround, a brief flip while the glyph is
		 *  near-vertical. No effect outside path mode. */
		upright?: boolean;
		/** Extra rotation (deg) on top of the tangent in path mode — aligns a
		 *  glyph whose artwork doesn't point "up" (🚀 ≈ -45, a left-facing 🚗 ≈ 90).
		 *  Under `upright` it is a level tilt on top of the (un-banked) glyph. */
		rotate?: number;
		/** How many keyframes to sample `path` into. More = smoother polyline,
		 *  bigger generated CSS. */
		samples?: number;
		/** Seconds for one pass through `stops` (ease-in-out, fill both). */
		animate?: number;
		/** Seconds to HOLD the start pose before the flight begins (CSS
		 *  animation-delay) — the sprite counterpart of a shape's `drawDelay`,
		 *  for staggering several objects on one timeline. The AnimationBar's
		 *  timeline simply extends to delay + animate, and scrubbing passes
		 *  through the wait. */
		delay?: number;
		/** CSS timing function for the WHOLE flight (default ease-in-out). Use
		 *  "linear" when position must be proportional to time — e.g. staggered
		 *  objects that should hold formation while their windows overlap. In
		 *  stops mode a per-stop `ease` still overrides its own segment. */
		ease?: string;
		/** When set, emit `font-size: h*fontScale` on every frame so a glyph
		 *  grows with its box as it travels (the rocket case uses 0.84). */
		fontScale?: number | null;
		/** Static transform-origin (the rotation pivot), in %. A property of the
		 *  object, not a moment — lives on the element, not the keyframes. */
		origin?: string;
		/** Shown in the editing readout + copied tag (mirrors Block's). */
		name?: string;
		/** Snap step (canvas px) while dragging handles. 1 = freeform. */
		grid?: number;
		/** Treat this sprite as a GROUP of editable shapes (children are a nested
		 *  <Draw>): in ADJUST, double-click to enter isolation — freeze + straighten
		 *  — and edit the nested shapes; Esc / click-outside exits. Off by default,
		 *  so a plain glyph sprite keeps its simple select-and-fly behavior. */
		group?: boolean;
		/** Hide this sprite from ADJUST entirely: no ghost boxes, no handles, no
		 *  keyframe panel, not selectable — it just flies. For GENERATED stops
		 *  (e.g. sampled from a curve) that aren't meant to be hand-edited, where
		 *  dozens of ghosts would only bury the shapes that ARE editable. */
		lock?: boolean;
		/** Freeze the flight at its current frame (CSS `animation-play-state:
		 *  paused`) — for a Sprite driven by an external trigger rather than
		 *  autoplay-on-mount (e.g. `<Cursor startOn>`). Purely a playback
		 *  toggle; the generated keyframes are untouched, so flipping it back
		 *  off resumes exactly where the timeline says it should. Default
		 *  false — every existing Sprite keeps playing on mount. */
		paused?: boolean;
		children?: Snippet;
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
		stops,
		path,
		size = 64,
		orient = true,
		upright = false,
		rotate = 0,
		samples = 40,
		animate,
		delay = 0,
		ease = 'ease-in-out',
		fontScale = null,
		origin = '50% 50%',
		name = '',
		grid = 1,
		group = false,
		lock = false,
		paused = false,
		children,
		style = '',
		id = '',
		class: klass = ''
	}: Props = $props();

	// ADJUST-mode editing overrides: the editor is a coordinate FINDER — drags
	// mutate these locals (reset on reload), never the props; Copy → paste is
	// the only persistence.
	type IdStop = SpriteStop & { id: number };
	// A sampled path stop carries an internal `flip` (horizontal mirror) that
	// `upright` mode sets; authors never write it (path stops are generated).
	type FlipStop = SpriteStop & { flip?: boolean };
	let liveStops = $state<IdStop[] | null>(null);
	let stopSeq = 0;

	// --- Path mode ------------------------------------------------------------
	// The path's points as currently edited — the same finder-state model as
	// liveStops: drags mutate these locals, Copy/SAVE is the persistence.
	let livePathFrom = $state<Point | null>(null);
	let livePathTo = $state<Point | null>(null);
	let livePathC1 = $state<Point | null>(null);
	let livePathC2 = $state<Point | null>(null);
	let livePathBend = $state<number | null>(null);
	// Polyline mode: the whole waypoint list is the edit state (one handle per
	// point), so a single array replaces the from/to/control locals.
	let livePathPoints = $state<Point[] | null>(null);
	/** path="name" — the sprite rides a shape it does not own. */
	const isRef = $derived(typeof path === 'string');
	/** The `path` prop resolved: a literal shape as-is; a NAME through the Draw
	 *  context's live path sources (the named shape must appear earlier in the
	 *  markup; unknown name → no flight, never a broken one). `ctx` is declared
	 *  further down — safe, deriveds evaluate lazily after init. */
	const sourcePath = $derived.by<PathShape | null>(() => {
		if (!path) return null;
		return typeof path === 'string' ? (ctx?.pathSource(path) ?? null) : path;
	});
	/** The path with live edits folded in (literal mode only — a NAMED shape
	 *  owns its geometry and is edited by its own handles); null when not in
	 *  path mode. */
	const P = $derived.by<PathShape | null>(() => {
		if (!sourcePath) return null;
		if (isRef) return sourcePath;
		// A polyline folds in the whole edited waypoint list — it has no
		// from/to of its own, so it steps aside before the endpoint locals.
		if (sourcePath.kind === 'polyline')
			return { ...sourcePath, points: livePathPoints ?? sourcePath.points };
		const f = livePathFrom ?? sourcePath.from;
		const t = livePathTo ?? sourcePath.to;
		switch (sourcePath.kind) {
			case 'line':
				return { kind: 'line', from: f, to: t };
			case 'quadratic':
				return { kind: 'quadratic', from: f, to: t, c1: livePathC1 ?? sourcePath.c1 };
			case 'cubic':
				return {
					kind: 'cubic',
					from: f,
					to: t,
					c1: livePathC1 ?? sourcePath.c1,
					c2: livePathC2 ?? sourcePath.c2
				};
			case 'arc':
				return { kind: 'arc', from: f, to: t, bend: livePathBend ?? sourcePath.bend };
		}
	});
	const boxW = $derived(Math.max(1, finite(Array.isArray(size) ? size[0] : size)));
	const boxH = $derived(Math.max(1, finite(Array.isArray(size) ? size[1] : size)));

	// Sample the path into ordinary stops: centre from pointAt, rotation from
	// the tangent. Samples are spaced by ARC LENGTH, not by the bézier
	// parameter — constant travel speed, and (sharing ease-in-out with the
	// draw-on stroke) the sprite stays glued to a same-duration `draw`'s pen
	// tip. Tangent angles are UNWRAPPED against the previous sample so the
	// glyph turns the short way instead of snapping 360° where atan2 crosses
	// ±π. Everything downstream (keyframes, base pose, scrubbing) then works
	// untouched — a path sprite IS a stops sprite, it just never shows the
	// stops to anyone.
	const pathStops = $derived.by<FlipStop[]>(() => {
		if (!P) return [];
		const n = Math.max(2, Math.round(finite(samples)) || 2);
		const ts = uniformLengthParams(P, n);
		const out: FlipStop[] = [];
		let prev = 0;
		for (let k = 0; k <= n; k++) {
			const t = ts[k];
			const [px, py] = pointAt(P, t);
			let rot = finite(rotate);
			let flip = false;
			if (upright) {
				// UPRIGHT: never bank (overrides `orient`) — a side-view glyph does
				// not roll, it just turns to face the way it's going. The glyph is
				// kept level (rot = the `rotate` offset only) and MIRRORED to face
				// travel. Convention: it faces LEFT at rot 0 (🚚/🚗), so mirror it
				// while heading RIGHTWARD (tangent's x-component ≥ 0). No unwrap
				// needed — the mirror, not a rotation, carries the direction.
				flip = Math.cos(angleAt(P, t)) >= 0;
			} else if (orient) {
				let a = angleAt(P, t);
				if (k > 0) {
					while (a - prev > Math.PI) a -= 2 * Math.PI;
					while (a - prev < -Math.PI) a += 2 * Math.PI;
				}
				prev = a;
				// angleAt is atan2 from +x; Sprite rot 0 points "up", hence +90.
				rot += (a * 180) / Math.PI + 90;
			}
			const stop: FlipStop = {
				// pct is animation PROGRESS (uniform), t is the path parameter that
				// puts the k-th frame at arc-length fraction k/n — the two differ by
				// exactly the reparameterization.
				pct: Math.round((k / n) * 10000) / 100,
				x: Math.round(px - boxW / 2),
				y: Math.round(py - boxH / 2),
				w: boxW,
				h: boxH,
				rot: Math.round(rot)
			};
			if (flip) stop.flip = true;
			out.push(stop);
		}
		return out;
	});

	// The path itself, as an SVG d — the editing ghost/hit geometry.
	const pathD = $derived.by(() => {
		if (!P) return '';
		switch (P.kind) {
			case 'line':
				return linePath(P.from, P.to);
			case 'quadratic':
				return curvePath(P.from, P.to, P.c1);
			case 'cubic':
				return curvePath(P.from, P.to, P.c1, P.c2);
			case 'arc':
				return arcPath(P.from, P.to, P.bend);
			case 'polyline':
				return P.smooth ? smoothPath(P.points, P.close) : polylinePath(P.points, P.close);
		}
	});
	// --------------------------------------------------------------------------

	/** `path` was given but resolves to nothing (an unknown name, or a name
	 *  registered later in the markup): render NOTHING — a missing flight,
	 *  never a glyph stranded at a fallback pose. Connector's rule. */
	const unresolved = $derived(!!path && !P);

	const S = $derived<FlipStop[]>(P ? pathStops : (liveStops ?? stops ?? []));

	// Clone the prop stops into editable id-carrying state on first edit.
	function materializeStops(): IdStop[] {
		if (!liveStops) liveStops = (stops ?? []).map((s) => ({ ...s, id: stopSeq++ }));
		return liveStops;
	}

	const clampPct = (p: number) => Math.max(0, Math.min(100, finite(p)));
	// Resolved, NaN-safe stops in markup order (indices line up with S so a
	// handle can bind back by index); sizes clamp to ≥1 so a box never collapses.
	const RS = $derived(
		S.map((s) => ({
			pct: clampPct(s.pct),
			x: finite(s.x),
			y: finite(s.y),
			w: Math.max(1, finite(s.w)),
			h: Math.max(1, finite(s.h)),
			rot: finite(s.rot ?? 0),
			ease: sanitizeEase(s.ease),
			flip: !!s.flip
		}))
	);
	// Sorted by percent — drives the @keyframes and the base (0%) pose.
	const sorted = $derived([...RS].sort((a, b) => a.pct - b.pct));
	const base = $derived(sorted[0] ?? { pct: 0, x: 0, y: 0, w: 100, h: 100, rot: 0, ease: '', flip: false });

	const animSecs = $derived(
		animate && Number.isFinite(animate) && animate > 0 && RS.length >= 2 ? animate : null
	);
	// Start-pose hold before the flight (see `delay`); 0 when not animating.
	const delaySecs = $derived(
		animSecs && Number.isFinite(delay) && delay > 0 ? delay : 0
	);
	// Whole-flight timing function (see `ease`), sanitized like a stop's.
	const easeFn = $derived(sanitizeEase(ease) || 'ease-in-out');

	const uid = newEditorId();
	const animName = `draw-sprite-${uid}`;
	// Integer font-size (like KeyframeStudio) — clean output, no float noise.
	const fontFor = (h: number) => (fontScale == null ? null : Math.round(h * fontScale));

	// --- Generated CSS @keyframes: left/top/width/height + rotate (+ optional
	// font-size), one frame per stop. A per-stop timing function set INSIDE its
	// keyframe governs the segment starting there; '' inherits ease-in-out.
	const keyframesCss = $derived.by(() => {
		if (!animSecs) return '';
		const body = sorted
			.map((s) => {
				const fs = fontFor(s.h);
				return (
					`${s.pct}% { left:${round(s.x)}px; top:${round(s.y)}px; ` +
					`width:${round(s.w)}px; height:${round(s.h)}px; transform:rotate(${round(s.rot)}deg)${s.flip ? ' scaleX(-1)' : ''};` +
					`${fs != null ? ` font-size:${fs}px;` : ''}` +
					`${s.ease ? ` animation-timing-function:${s.ease};` : ''} }`
				);
			})
			.join(' ');
		return `@keyframes ${animName} { ${body} }`;
	});

	// Base (0%) inline pose — the static/no-JS/SSR fallback; the animation
	// (fill:both) takes over once the browser runs it.
	const baseStyle = $derived(
		`left:${round(base.x)}px; top:${round(base.y)}px; ` +
			`width:${round(base.w)}px; height:${round(base.h)}px; ` +
			`transform-origin:${origin}; transform:rotate(${round(base.rot)}deg)${base.flip ? ' scaleX(-1)' : ''};` +
			`${fontFor(base.h) != null ? ` font-size:${fontFor(base.h)}px;` : ''}` +
			`${animSecs ? ` animation:${animName} ${animSecs}s ${easeFn}${delaySecs ? ` ${delaySecs}s` : ''} both;${paused ? ' animation-play-state:paused;' : ''}` : ''}`
	);

	// --- ADJUST-mode editing chrome ------------------------------------------
	const ctx = getContext<DrawContext | undefined>(DRAW_CONTEXT_KEY);
	const editing = $derived(ctx?.editing ?? false);
	const cw = $derived(ctx?.width ?? 1920);
	const ch = $derived(ctx?.height ?? 1080);

	const stopLiteral = (s: {
		pct: number;
		x: number;
		y: number;
		w: number;
		h: number;
		rot: number;
		ease: string;
	}) =>
		`{ pct: ${fmtNum(s.pct)}, x: ${fmtNum(s.x)}, y: ${fmtNum(s.y)}, ` +
		`w: ${fmtNum(s.w)}, h: ${fmtNum(s.h)}${s.rot ? `, rot: ${fmtNum(s.rot)}` : ''}` +
		`${s.ease ? `, ease: "${s.ease}"` : ''} }`;

	const tagFor = (list: Array<Parameters<typeof stopLiteral>[0]>) =>
		`<Sprite${name ? ` name="${name}"` : ''}` +
		`${animate ? ` animate={${fmtNum(animate)}}` : ''}` +
		`${delay ? ` delay={${fmtNum(delay)}}` : ''}` +
		`${easeFn !== 'ease-in-out' ? ` ease="${easeFn}"` : ''}` +
		`${fontScale != null ? ` fontScale={${fmtNum(fontScale)}}` : ''}` +
		`${origin !== '50% 50%' ? ` origin="${origin}"` : ''}` +
		`${group ? ' group' : ''}` +
		`${lock ? ' lock' : ''}` +
		`${paused ? ' paused' : ''}` +
		` stops={[${list.map(stopLiteral).join(', ')}]}>`;

	// Path-mode serialization: the tag carries the curve's LITERAL points, so
	// Copy round-trips and SAVE's literal tag swap has real bytes to match —
	// unlike a path fed from a shared const, which can only be copied by hand.
	const pathLiteral = (s: PathShape) =>
		s.kind === 'line'
			? `{ kind: "line", from: ${fmtPoint(s.from)}, to: ${fmtPoint(s.to)} }`
			: s.kind === 'quadratic'
				? `{ kind: "quadratic", from: ${fmtPoint(s.from)}, c1: ${fmtPoint(s.c1)}, to: ${fmtPoint(s.to)} }`
				: s.kind === 'cubic'
					? `{ kind: "cubic", from: ${fmtPoint(s.from)}, c1: ${fmtPoint(s.c1)}, c2: ${fmtPoint(s.c2)}, to: ${fmtPoint(s.to)} }`
					: s.kind === 'polyline'
						? `{ kind: "polyline", points: [${s.points.map(fmtPoint).join(', ')}]` +
							`${s.close ? ', close: true' : ''}${s.smooth ? ', smooth: true' : ''} }`
						: `{ kind: "arc", from: ${fmtPoint(s.from)}, to: ${fmtPoint(s.to)}, bend: ${fmtNum(s.bend)} }`;

	// Takes the serialized attr value — `{${pathLiteral(shape)}}` or `"name"`.
	const pathTagFor = (pathAttr: string) =>
		`<Sprite${name ? ` name="${name}"` : ''}` +
		` path=${pathAttr}` +
		`${animate ? ` animate={${fmtNum(animate)}}` : ''}` +
		`${delay ? ` delay={${fmtNum(delay)}}` : ''}` +
		`${easeFn !== 'ease-in-out' ? ` ease="${easeFn}"` : ''}` +
		`${Array.isArray(size) ? ` size={[${fmtNum(size[0])}, ${fmtNum(size[1])}]}` : size !== 64 ? ` size={${fmtNum(size)}}` : ''}` +
		`${orient ? '' : ' orient={false}'}` +
		`${upright ? ' upright' : ''}` +
		`${finite(rotate) ? ` rotate={${fmtNum(rotate)}}` : ''}` +
		`${samples !== 40 ? ` samples={${fmtNum(samples)}}` : ''}` +
		`${fontScale != null ? ` fontScale={${fmtNum(fontScale)}}` : ''}` +
		`${origin !== '50% 50%' ? ` origin="${origin}"` : ''}` +
		`${group ? ' group' : ''}` +
		`${lock ? ' lock' : ''}` +
		`${paused ? ' paused' : ''}` +
		`>`;

	// Source (prop) stops resolved the same way, for the "Copy changed" OLD side.
	const sourceStops = $derived(
		(stops ?? []).map((s) => ({
			pct: clampPct(s.pct),
			x: finite(s.x),
			y: finite(s.y),
			w: Math.max(1, finite(s.w)),
			h: Math.max(1, finite(s.h)),
			rot: finite(s.rot ?? 0),
			ease: sanitizeEase(s.ease)
		}))
	);
	const snippet = $derived(
		typeof path === 'string'
			? pathTagFor(`"${path}"`)
			: P
				? pathTagFor(`{${pathLiteral(P)}}`)
				: tagFor(RS)
	);
	const sourceSnippet = $derived(
		typeof path === 'string'
			? pathTagFor(`"${path}"`)
			: path
				? pathTagFor(`{${pathLiteral(path)}}`)
				: tagFor(sourceStops)
	);

	const editor: ShapeEditor = {
		id: uid,
		kind: 'Sprite',
		get name() {
			return name;
		},
		get readout() {
			// A path sprite reads as its curve, not its (generated) stop count.
			return P
				? `${P.kind} path · ${finite(animate ?? 0)}s`
				: `${RS.length} stops · ${finite(animate ?? 0)}s`;
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
			// No keyframe panel in path mode: the stops are generated, so rows of
			// them would be noise — the curve handles are the whole editor.
			return animSecs && !P ? animApi : null;
		},
		get chrome() {
			return chrome;
		}
	};
	const isSelected = $derived(ctx?.selected === editor);
	// Selected → Draw renders our `chrome` snippet in its top layer instead, so
	// we must not also render it inline (select-to-front; see DrawContext). The
	// ghost BOXES stay home either way — like a path shape's hit stroke, they
	// only compete with each other, and a selected sprite's box is a wide target
	// that would swallow every shape drawn under it.
	const isHoisted = $derived(ctx?.hoisted === editor);
	const select = () => ctx?.select(editor);
	$effect(() => {
		// A locked sprite never registers: it cannot be selected, listed or
		// copied — ADJUST simply doesn't know it exists. Nor does a path="name"
		// rider: the NAMED shape is the editor and the single source of truth.
		if (!ctx?.registerShape || lock || isRef) return;
		// untrack: registering reads+writes Draw's shape list (see Rect.svelte).
		return untrack(() => ctx.registerShape(editor));
	});
	onDestroy(() => {
		if (ctx?.selected === editor) ctx.select(null);
	});

	// Materialize eagerly while the panel is up so its rows carry real ids.
	// (Stop mode only — path mode has no panel and ignores liveStops.)
	$effect(() => {
		if (editing && isSelected && animSecs && !P && !liveStops) materializeStops();
	});

	// --- Per-stop geometry editing (drag the ghost). Live drags mutate the
	// stop; a completed gesture records the whole box before/after to undo.
	function setStopGeom(i: number, patch: Partial<SpriteStop>) {
		liveStops = materializeStops().map((s, k) => (k === i ? { ...s, ...patch } : s));
	}
	// Snapshot a stop's geometry (for undo), captured at pointer-down.
	const geomAt = (i: number): SpriteStop => {
		const s = RS[i];
		return { pct: s.pct, x: s.x, y: s.y, w: s.w, h: s.h, rot: s.rot, ease: s.ease };
	};
	// Path-mode handle commits: same record() shape the path shapes use.
	function commitPath(apply: (p: Point) => void, before: Point, after: Point) {
		record({ undo: () => apply(before), redo: () => apply(after) });
	}
	// Polyline mode: move ONE waypoint, materializing the editable list from
	// the current path on first touch (the liveStops pattern).
	function setPathPoint(i: number, p: Point) {
		if (P?.kind !== 'polyline') return;
		const pts = livePathPoints ?? P.points.map((q): Point => [q[0], q[1]]);
		livePathPoints = pts.map((q, k) => (k === i ? p : q));
	}

	let dragBefore: { i: number; box: SpriteStop } | null = null;
	function beginDrag(i: number) {
		select();
		dragBefore = { i, box: geomAt(i) };
	}
	function endDrag(i: number) {
		if (!dragBefore || dragBefore.i !== i) return;
		const before = dragBefore.box;
		const after = geomAt(i);
		dragBefore = null;
		if (before.x === after.x && before.y === after.y && before.w === after.w && before.h === after.h && before.rot === after.rot)
			return;
		record({ undo: () => setStopGeom(i, before), redo: () => setStopGeom(i, after) });
	}

	// Handle anchor points, in canvas px, computed from the (axis-aligned) box.
	const center = (s: { x: number; y: number; w: number; h: number }): Point => [s.x + s.w / 2, s.y + s.h / 2];
	const corner = (s: { x: number; y: number; w: number; h: number }): Point => [s.x + s.w, s.y + s.h];
	// Rotate grip: a point orbiting the center, offset "up" then turned by rot.
	const gripRadius = (s: { h: number }) => s.h / 2 + 40;
	function gripPoint(s: { x: number; y: number; w: number; h: number; rot: number }): Point {
		const [cx, cy] = center(s);
		const R = gripRadius(s);
		const th = (s.rot * Math.PI) / 180;
		return [round(cx + R * Math.sin(th)), round(cy - R * Math.cos(th))];
	}

	// Geometry stays on the integer grid (matches DrawHandle's snapped points
	// and Block's whole-pixel boxes), so copied stops read cleanly.
	function onMove(i: number, p: Point) {
		const s = RS[i];
		setStopGeom(i, { x: Math.round(p[0] - s.w / 2), y: Math.round(p[1] - s.h / 2) });
	}
	function onResize(i: number, p: Point) {
		const s = RS[i];
		setStopGeom(i, { w: Math.max(8, Math.round(p[0] - s.x)), h: Math.max(8, Math.round(p[1] - s.y)) });
	}
	function onRotate(i: number, p: Point) {
		const s = RS[i];
		const [cx, cy] = center(s);
		// Grip is "up" at rot 0, i.e. -90° from +x; add 90 to recover rot.
		const deg = (Math.atan2(p[1] - cy, p[0] - cx) * 180) / Math.PI + 90;
		setStopGeom(i, { rot: Math.round(deg) });
	}

	// Ref to the moving element, so "+ keyframe" / preview can read the live
	// playhead time off its CSS animation.
	let spriteEl = $state<HTMLElement>();

	// --- Isolation ("enter group") editing -----------------------------------
	// Double-click the sprite to FREEZE it at its current on-screen pose,
	// STRAIGHTEN it to rot 0, and make its content pointer-live — so the nested
	// shapes edit with the ordinary Draw machinery. Rotation is the ONLY thing
	// that broke DrawHandle's drag scale (getBoundingClientRect on a turned box
	// inflates the bbox); at rot 0 the nested svg is upright at plain deck scale,
	// identical to a standalone Draw, so its editing is known-good. Esc (or
	// toggling ADJUST off) exits and restores the flight. Reachable only in
	// ADJUST, so published builds stay byte-inert and never eat input.
	let entered = $state(false);
	let editPose = $state<{ x: number; y: number; w: number; h: number } | null>(null);

	// Tell any nested <Draw> (a group's contents) that it may edit ONLY while
	// this sprite is isolated — so its handles/toolbar never linger on, or ride
	// along with, the flying box. A standalone Draw has no such provider.
	setContext<SpriteIsolation>(SPRITE_ISOLATION_KEY, {
		get entered() {
			return entered;
		}
	});

	function enterIsolation() {
		if (!group || !editing || !browser || !spriteEl) return;
		// Freeze at the CURRENT animated pose, read straight off the running CSS
		// animation, so the box straightens where it is rather than jumping.
		const cs = getComputedStyle(spriteEl);
		editPose = {
			x: parseFloat(cs.left) || base.x,
			y: parseFloat(cs.top) || base.y,
			w: parseFloat(cs.width) || base.w,
			h: parseFloat(cs.height) || base.h
		};
		entered = true;
		// Hand editing to the nested Draw: drop the outer selection so the
		// sprite's own keyframe toolbar steps aside for the inner shape's.
		ctx?.select(null);
	}
	function exitIsolation() {
		entered = false;
		editPose = null;
	}
	// Esc exits; so does turning ADJUST off underneath an entered sprite.
	$effect(() => {
		if (!entered || !browser) return;
		const onKey = (e: KeyboardEvent) => {
			if (e.key === 'Escape') exitIsolation();
		};
		window.addEventListener('keydown', onKey);
		return () => window.removeEventListener('keydown', onKey);
	});
	// Click OUTSIDE the isolated group leaves isolation (Illustrator-style), which
	// also tears down the nested Draw's editing chrome (its `editing` gates on our
	// `entered`) — so deselecting by clicking away closes the inner dialog too.
	// Clicks on the sprite content (shapes, handles, the nested toolbar) or the
	// AnimationBar are exempt.
	$effect(() => {
		if (!entered || !browser) return;
		const onDown = (e: PointerEvent) => {
			const t = e.target as Node | null;
			if (t && spriteEl?.contains(t)) return;
			if (t instanceof Element && t.closest('.anim-bar')) return;
			exitIsolation();
		};
		window.addEventListener('pointerdown', onDown, true);
		return () => window.removeEventListener('pointerdown', onDown, true);
	});
	$effect(() => {
		if (!editing && entered) exitIsolation();
	});

	// The frozen, straightened edit pose — no animation, rot 0 — swapped in for
	// baseStyle on .sprite-el while entered.
	const editStyle = $derived(
		editPose
			? `left:${round(editPose.x)}px; top:${round(editPose.y)}px; ` +
					`width:${round(editPose.w)}px; height:${round(editPose.h)}px; ` +
					`transform-origin:${origin}; transform:rotate(0deg);` +
					`${fontFor(editPose.h) != null ? ` font-size:${fontFor(editPose.h)}px;` : ''}`
			: baseStyle
	);

	const animApi: AnimEditor = {
		get stops() {
			const list = liveStops ?? (stops ?? []).map((s, i) => ({ ...s, id: -1 - i }) as IdStop);
			return list
				.map((s) => ({
					id: s.id,
					pct: Math.round(clampPct(s.pct)),
					x: Math.round(finite(s.x)),
					y: Math.round(finite(s.y)),
					w: Math.max(1, Math.round(finite(s.w))),
					h: Math.max(1, Math.round(finite(s.h))),
					rot: Math.round(finite(s.rot ?? 0)),
					ease: s.ease ?? null
				}))
				.sort((a, b) => a.pct - b.pct);
		},
		addStop() {
			const list = materializeStops();
			const asc = [...list].sort((a, b) => finite(a.pct) - finite(b.pct));
			// Insert at the AnimationBar playhead if readable, else the widest gap;
			// geometry is lerped between the bracketing stops so it lands on the path.
			const ph = playheadPercent(spriteEl, animName, animSecs, delaySecs);
			const target = ph != null ? Math.round(ph) : widestGapMid(asc);
			const { a, b, frac } = neighborsAt(asc, target);
			const lerp = (p: number, q: number) => Math.round(p + (q - p) * frac);
			const ns: IdStop = {
				id: stopSeq++,
				pct: target,
				x: lerp(finite(a.x), finite(b.x)),
				y: lerp(finite(a.y), finite(b.y)),
				w: Math.max(1, lerp(finite(a.w), finite(b.w))),
				h: Math.max(1, lerp(finite(a.h), finite(b.h))),
				rot: lerp(finite(a.rot ?? 0), finite(b.rot ?? 0))
			};
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
		setPose(id: number, key: 'x' | 'y' | 'w' | 'h' | 'rot', value: number) {
			// Same mutation drag uses (setStopGeom), just addressed by id — panel
			// edits stay out of the global undo, matching setPct/setEase.
			const raw = Math.round(finite(value));
			const v = key === 'w' || key === 'h' ? Math.max(1, raw) : raw;
			liveStops = materializeStops().map((s) => (s.id === id ? { ...s, [key]: v } : s));
		},
		preview() {
			const pct = playheadPercent(spriteEl, animName, animSecs, delaySecs);
			if (pct == null) return null;
			return { pct: Math.round(pct), drawn: null };
		}
	};
</script>

<g id={id || undefined} class="draw-sprite {klass}" style={style || undefined}>
	{#if !unresolved}
	{#if animSecs}
		<!-- Generated keyframes — a real <style>, so it prerenders and scrubs. -->
		{@html `<style>${keyframesCss}</style>`}
	{/if}

	<!-- The moving element lives in HTML space, spanning the canvas so a stop's
	     x/y/w/h are its left/top/width/height with no math. pointer-events:none
	     keeps the surface's never-eats-input guarantee. -->
	<foreignObject
		x="0"
		y="0"
		width={cw}
		height={ch}
		style="overflow:visible; pointer-events:{entered ? 'auto' : 'none'};"
	>
		<div
			xmlns="http://www.w3.org/1999/xhtml"
			class="sprite-layer"
			style="position:absolute; inset:0; pointer-events:{entered ? 'auto' : 'none'}; overflow:visible;"
		>
			<div
				bind:this={spriteEl}
				class="sprite-el"
				class:entered
				style={entered && editPose ? editStyle : baseStyle}
			>
				{@render children?.()}
			</div>
		</div>
	</foreignObject>
	{/if}

	{#if editing && !entered && !lock && P && !isRef}
		<!-- Path-mode chrome: the flight path ITSELF is the editor. One dashed
		     ghost of the curve (no per-stop boxes — the stops are generated),
		     with a wide hit stroke to select; when selected, the chrome snippet
		     grows endpoint/control handles like a <Curve>'s, and dragging them
		     re-routes the flight live. -->
		{#if isSelected}
			<path class="draw-selglow" d={pathD} />
		{/if}
		<path class="sprite-path" class:selected={isSelected} d={pathD} />
		<!-- svelte-ignore a11y_no_static_element_interactions -->
		<path class="draw-hit" d={pathD} onpointerdown={select} ondblclick={enterIsolation} />
		{#if !isHoisted}{@render chrome()}{/if}
	{/if}

	{#if editing && !entered && !lock && !P}
		<!-- One ghost per stop: an axis-aligned dashed box (the grab/geometry
		     box) with the stop's percent, plus a short tick showing its rotation.
		     Clicking a box selects the sprite; DOUBLE-clicking enters isolation
		     (freeze + straighten) to edit the nested shapes; when selected, each
		     box grows move / resize / rotate handles. -->
		{#each RS as s, i (i)}
			{@const cxy = center(s)}
			<g class="sprite-ghost" class:selected={isSelected}>
				<!-- svelte-ignore a11y_no_static_element_interactions -->
				<rect
					class="sprite-hit"
					x={s.x}
					y={s.y}
					width={s.w}
					height={s.h}
					onpointerdown={select}
					ondblclick={enterIsolation}
				/>
				<rect class="sprite-box" x={s.x} y={s.y} width={s.w} height={s.h} />
				<!-- Orientation tick: from center outwards along `rot` (0 = up). -->
				<line
					class="sprite-tick"
					x1={cxy[0]}
					y1={cxy[1]}
					x2={gripPoint(s)[0]}
					y2={gripPoint(s)[1]}
				/>
				<text class="sprite-pct" x={s.x + 6} y={s.y + 22}>{s.pct}%</text>
			</g>
		{/each}
		{#if !isHoisted}{@render chrome()}{/if}
	{/if}

	{#if entered && editPose}
		<!-- Isolation affordance: an upright frame + hint in the OUTER svg (not
		     pointer-inert), marking that the group is frozen/straightened and its
		     nested shapes are now directly editable. Esc exits. -->
		<rect
			class="iso-frame"
			x={editPose.x}
			y={editPose.y}
			width={editPose.w}
			height={editPose.h}
		/>
		<text class="iso-hint" x={editPose.x} y={editPose.y - 12}>▸ group isolated · Esc to exit</text>
	{/if}
</g>

{#snippet chrome()}
	<!-- The selected sprite's per-stop move / resize / rotate handles, wrapped so
	     <Draw> can re-parent them whole into its top layer (select-to-front).
	     They ride absolute canvas coordinates, so lifting them out of their ghost
	     <g> moves nothing. Self-guarding: an UNSELECTED sprite has no handles at
	     all, so this renders nothing while it merely holds the hoist through
	     another shape's drag. -->
	{#if isSelected && !entered && P}
		<!-- Path-mode handles: the curve's own points, exactly a <Curve>'s editor
		     — solid endpoints, hollow control points with guide lines, an apex
		     grip for an arc's bend. Dragging any of them re-samples the flight. -->
		<g class="draw-chrome" data-shape={name || 'Sprite'}>
			{#if P.kind === 'polyline'}
				<!-- One handle per waypoint — drag any vertex and the flight
				     re-samples through the moved point (smooth included: the
				     Catmull-Rom passes THROUGH every point, so the handle stays
				     on the curve). -->
				{#each P.points as pt, i (i)}
					<DrawHandle
						point={pt}
						{grid}
						title={`p${i}`}
						onselect={select}
						onmove={(p) => setPathPoint(i, p)}
						oncommit={(b, a) => commitPath((p) => setPathPoint(i, p), b, a)}
					/>
				{/each}
			{:else}
			{#if P.kind === 'quadratic' || P.kind === 'cubic'}
				<path class="draw-guide" d={linePath(P.c1, P.from)} />
				<path class="draw-guide" d={P.kind === 'cubic' ? linePath(P.c2, P.to) : linePath(P.c1, P.to)} />
			{/if}
			<DrawHandle
				point={P.from}
				{grid}
				title="from"
				onselect={select}
				onmove={(p) => (livePathFrom = p)}
				oncommit={(b, a) => commitPath((p) => (livePathFrom = p), b, a)}
			/>
			<DrawHandle
				point={P.to}
				{grid}
				title="to"
				onselect={select}
				onmove={(p) => (livePathTo = p)}
				oncommit={(b, a) => commitPath((p) => (livePathTo = p), b, a)}
			/>
			{#if P.kind === 'quadratic' || P.kind === 'cubic'}
				<DrawHandle
					point={P.c1}
					{grid}
					kind="control"
					title="c1"
					onselect={select}
					onmove={(p) => (livePathC1 = p)}
					oncommit={(b, a) => commitPath((p) => (livePathC1 = p), b, a)}
				/>
			{/if}
			{#if P.kind === 'cubic'}
				<DrawHandle
					point={P.c2}
					{grid}
					kind="control"
					title="c2"
					onselect={select}
					onmove={(p) => (livePathC2 = p)}
					oncommit={(b, a) => commitPath((p) => (livePathC2 = p), b, a)}
				/>
			{/if}
			{#if P.kind === 'arc'}
				{@const AF = P.from}
				{@const AT = P.to}
				<DrawHandle
					point={pointAt(P, 0.5)}
					{grid}
					kind="bend"
					title="bend"
					onselect={select}
					onmove={(p) => (livePathBend = bendFromApex(AF, AT, p))}
					oncommit={(b, a) =>
						record({
							undo: () => (livePathBend = bendFromApex(AF, AT, b)),
							redo: () => (livePathBend = bendFromApex(AF, AT, a))
						})}
				/>
			{/if}
			{/if}
		</g>
	{:else if isSelected && !entered}
		<g class="draw-chrome" data-shape={name || 'Sprite'}>
			{#each RS as s, i (i)}
				<DrawHandle
					point={center(s)}
					{grid}
					title={`move · ${s.pct}%`}
					onselect={() => beginDrag(i)}
					onmove={(p) => onMove(i, p)}
					oncommit={() => endDrag(i)}
				/>
				<DrawHandle
					point={corner(s)}
					{grid}
					kind="control"
					title={`resize · ${s.pct}%`}
					onselect={() => beginDrag(i)}
					onmove={(p) => onResize(i, p)}
					oncommit={() => endDrag(i)}
				/>
				<DrawHandle
					point={gripPoint(s)}
					kind="bend"
					title={`rotate · ${s.pct}%`}
					onselect={() => beginDrag(i)}
					onmove={(p) => onRotate(i, p)}
					oncommit={() => endDrag(i)}
				/>
			{/each}
		</g>
	{/if}
{/snippet}

<style>
	.sprite-el {
		position: absolute;
		display: flex;
		align-items: center;
		justify-content: center;
		line-height: 1;
		/* Redundant with the inline pointer-events:none, but keep it even if the
		   inline style is ever trimmed — the surface must never eat input. */
		pointer-events: none;
	}
	/* Isolation mode (ADJUST + double-click only): the frozen, straightened box
	   becomes pointer-live so the nested Draw's own handles/hit-strokes work. */
	.sprite-el.entered {
		pointer-events: auto;
	}

	/* Editing chrome (ADJUST mode only). */
	.sprite-hit {
		fill: transparent;
		stroke: none;
		pointer-events: all;
		cursor: pointer;
	}
	.sprite-box {
		fill: none;
		stroke: rgba(255, 255, 255, 0.35);
		stroke-width: 2;
		stroke-dasharray: 8 6;
		pointer-events: none;
	}
	.sprite-ghost.selected .sprite-box {
		stroke: var(--ctrl-selected-bg, #00b356);
		stroke-opacity: 0.8;
	}
	.sprite-tick {
		stroke: var(--ctrl-strong-bg, #2980b9);
		stroke-width: 3;
		pointer-events: none;
	}
	.sprite-pct {
		fill: rgba(255, 255, 255, 0.55);
		font-family: 'Fira Code', monospace;
		font-size: 20px;
		pointer-events: none;
		user-select: none;
	}
	/* Path-mode chrome (ADJUST only): the flight path is the editor. Same
	   vocabulary as the path shapes' own chrome (Line/Curve/Arc). */
	.sprite-path {
		fill: none;
		stroke: rgba(255, 255, 255, 0.35);
		stroke-width: 2;
		stroke-dasharray: 8 6;
		pointer-events: none;
	}
	.sprite-path.selected {
		stroke: var(--ctrl-selected-bg, #00b356);
		stroke-opacity: 0.8;
	}
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
	.draw-guide {
		fill: none;
		stroke: var(--ctrl-strong-bg, #2980b9);
		stroke-opacity: 0.6;
		stroke-width: 1.5;
		stroke-dasharray: 4 4;
	}

	/* Isolation affordances. */
	.iso-frame {
		fill: none;
		stroke: var(--ctrl-selected-bg, #00b356);
		stroke-width: 2;
		stroke-dasharray: 10 6;
		pointer-events: none;
	}
	.iso-hint {
		fill: var(--ctrl-selected-bg, #00b356);
		font-family: 'Fira Code', monospace;
		font-size: 20px;
		pointer-events: none;
		user-select: none;
	}
</style>
