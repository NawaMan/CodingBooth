// Pure geometry for the hand-drawn ("sloppy") render option — the Excalidraw
// look, our own math. No component imports, no DOM, no stores, no runtime
// dependency: everything here is independently unit-testable
// (tests/roughCore.test.ts), the same discipline drawCore.ts follows.
//
// THE ONE RULE THIS FILE EXISTS TO KEEP: every function is DETERMINISTIC.
// Shapes prerender on the server and hydrate in the browser, so a `Math.random`
// anywhere would hand the two sides different `d` strings — a hydration
// mismatch, or a visible snap on load. All wobble comes from a seeded PRNG
// whose seed is derived from the shape's own props (or an explicit `seed`), so
// the same shape draws the same way forever, on both sides of the wire.
//
// SECOND RULE: roughening is RENDER-ONLY. It rewrites the `d` string and
// nothing else. Every evaluator — pointAt/angleAt for sprites riding a path,
// arrowhead tangents, label placement, ADJUST handles — keeps working over the
// TRUE geometry, so a vehicle doesn't judder along a jittery road and handles
// don't drift off their stroke.
//
// THIRD RULE: the command structure is CONSTANT. Sample counts never depend on
// a shape's size, so an animated shape's generated `d: path()` keyframes have
// matching command counts at every stop and the browser can interpolate them.
// The jitter is applied in a shape-LOCAL frame (offset along the normal at each
// sample) from one seed per shape, so a morphing shape's wobble rides the
// geometry instead of boiling.

import { finite, pointAt, polylineSegments, round } from './drawCore';
import type { Point, PathShape } from './types';

// ─── Seeded randomness ──────────────────────────────────────────────────────

/** mulberry32 — a small, fast, well-distributed 32-bit PRNG. Returns a
 *  generator of numbers in [0, 1). Same seed ⇒ same sequence, everywhere:
 *  that is the whole reason it is here instead of `Math.random`. */
export function makeRandom(seed: number): () => number {
	let a = (Math.floor(finite(seed, 1)) || 1) >>> 0;
	return function next(): number {
		a = (a + 0x6d2b79f5) >>> 0;
		let t = a;
		t = Math.imul(t ^ (t >>> 15), t | 1);
		t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
		return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
	};
}

/** A stable 32-bit seed from any string — FNV-1a. Components hash their own
 *  geometry props into this so two different shapes wobble differently while
 *  each stays identical across renders. Never returns 0 (a zero seed would
 *  collapse mulberry32's first draw). */
export function hashSeed(text: string): number {
	let h = 0x811c9dc5;
	for (let i = 0; i < text.length; i++) {
		h ^= text.charCodeAt(i);
		h = Math.imul(h, 0x01000193) >>> 0;
	}
	return (h >>> 0) || 1;
}

/** The seed for a shape: an explicit `seed` prop wins, else a hash of a
 *  caller-supplied identity string (normally its geometry + name). */
export function seedOf(seed: number | undefined, identity: string): number {
	return seed != null && Number.isFinite(seed) ? Math.floor(seed) >>> 0 || 1 : hashSeed(identity);
}

// ─── Options ────────────────────────────────────────────────────────────────

/** How sloppy, and how. Every field has a sane default; `roughness` is the one
 *  an author actually reaches for (it is what `rough={1.5}` sets). */
export interface RoughOptions {
	/** Wobble amount. 0 = clean (callers should skip roughening entirely),
	 *  1 = Excalidraw-ish, 2 = drunk. Clamped to [0, 4]. */
	roughness?: number;
	/** How much each pass bows away from the true path over its whole length —
	 *  the low-frequency arc on top of the high-frequency jitter. */
	bowing?: number;
	/** Explicit seed; omit to derive one from the shape's identity. */
	seed?: number;
	/** Overlapping passes per stroke. 2 is the doubled-line look; 1 is a single
	 *  sketchy line; 3+ gets scribbly. Clamped to [1, 4]. */
	passes?: number;
	/** Samples per segment. CONSTANT by design — see the header. */
	samples?: number;
}

const DEFAULTS = {
	roughness: 1,
	bowing: 1,
	passes: 2,
	// Deliberately LOW. Sample spacing sets the wobble's wavelength, and a hand
	// draws long slow waves — sampling densely gives high-frequency chatter that
	// reads as a noisy line, not a drawn one. Also constant by design: see the
	// header's third rule.
	samples: 8
};

interface Resolved {
	roughness: number;
	bowing: number;
	passes: number;
	samples: number;
	seed: number;
}

function resolve(opts: RoughOptions | undefined, identity: string): Resolved {
	const o = opts ?? {};
	return {
		roughness: clamp(finite(o.roughness ?? DEFAULTS.roughness, DEFAULTS.roughness), 0, 4),
		bowing: clamp(finite(o.bowing ?? DEFAULTS.bowing, DEFAULTS.bowing), 0, 4),
		passes: Math.round(clamp(finite(o.passes ?? DEFAULTS.passes, DEFAULTS.passes), 1, 4)),
		samples: Math.round(clamp(finite(o.samples ?? DEFAULTS.samples, DEFAULTS.samples), 2, 64)),
		seed: seedOf(o.seed, identity)
	};
}

function clamp(v: number, lo: number, hi: number): number {
	return v < lo ? lo : v > hi ? hi : v;
}

/** Fold a shape's own `rough` prop together with the `<Draw rough>` default it
 *  sits inside. Unset inherits; `false`/`0` opts a single shape out of an
 *  inherited default; `true` means the standard wobble. Returns null for "draw
 *  this the ordinary way", which is the signal every component branches on. */
export function resolveRoughness(
	own: boolean | number | undefined,
	inherited: number | null
): number | null {
	if (own === undefined || own === null) return inherited;
	if (own === false) return null;
	if (own === true) return DEFAULTS.roughness;
	const v = finite(own, 0);
	return v > 0 ? v : null;
}

// ─── Perturbation ───────────────────────────────────────────────────────────

/** Chord length of a point run — the scale the wobble amplitude keys off. */
function runLength(pts: Point[]): number {
	let total = 0;
	for (let i = 1; i < pts.length; i++) {
		total += Math.hypot(pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1]);
	}
	return total;
}

/** Unit normals at each point of a run, from the local tangent. Endpoints
 *  borrow their neighbour's tangent; a degenerate (zero-length) step falls back
 *  to the previous normal, so a doubled point never produces NaN. */
function normalsOf(pts: Point[]): Point[] {
	const n = pts.length;
	const out: Point[] = [];
	let last: Point = [0, -1];
	for (let i = 0; i < n; i++) {
		const a = pts[Math.max(0, i - 1)];
		const b = pts[Math.min(n - 1, i + 1)];
		const dx = b[0] - a[0];
		const dy = b[1] - a[1];
		const len = Math.hypot(dx, dy);
		if (len > 1e-9) last = [dy / len, -dx / len];
		out.push(last);
	}
	return out;
}

/** Offset every point along its own normal by high-frequency jitter plus one
 *  low-frequency bow for the whole pass. On an OPEN run the offset tapers
 *  toward the ends (a half-sine window) so arrowheads and segment joins stay
 *  visually attached; on a CLOSED run it does not taper and the last point is
 *  snapped back onto the first so the loop still closes. */
export function perturb(
	pts: Point[],
	rnd: () => number,
	amp: number,
	bow: number,
	closed = false
): Point[] {
	const n = pts.length - 1;
	if (n < 1) return pts.map((p) => [p[0], p[1]] as Point);
	const nrm = normalsOf(pts);
	const bowDir = rnd() * 2 - 1;
	const out: Point[] = [];
	for (let i = 0; i <= n; i++) {
		const t = i / n;
		const window = closed ? 1 : 0.35 + 0.65 * Math.sin(Math.PI * t);
		const jitter = (rnd() * 2 - 1) * amp * window;
		const bowOff = closed ? 0 : bowDir * bow * Math.sin(Math.PI * t);
		const off = jitter + bowOff;
		out.push([pts[i][0] + nrm[i][0] * off, pts[i][1] + nrm[i][1] * off]);
	}
	if (closed) out[n] = [out[0][0], out[0][1]];
	return out;
}

/** Catmull-Rom through every point, emitted as cubic `C` commands WITHOUT a
 *  leading `M` so runs can be chained into one subpath while keeping their
 *  corners sharp (a smooth pass over a corner would round it away). Exactly
 *  `pts.length - 1` commands — that fixed count is what lets `d: path()`
 *  interpolate between animation stops. */
export function catmullCommands(pts: Point[]): string {
	const n = pts.length;
	if (n < 2) return '';
	let d = '';
	for (let i = 0; i < n - 1; i++) {
		const p0 = pts[Math.max(0, i - 1)];
		const p1 = pts[i];
		const p2 = pts[i + 1];
		const p3 = pts[Math.min(n - 1, i + 2)];
		const c1: Point = [p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6];
		const c2: Point = [p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6];
		d += ` C ${round(c1[0])} ${round(c1[1])} ${round(c2[0])} ${round(c2[1])} ${round(p2[0])} ${round(p2[1])}`;
	}
	return d.slice(1);
}

/** The wobble amplitude and bow for a run of the given length. Amplitude grows
 *  gently with length (a 1200px line that wobbles as little as a 40px tick
 *  reads as machine-drawn), but is capped so long strokes stay legible. */
function amplitudes(len: number, roughness: number, bowing: number) {
	const scale = clamp(len / 300, 0, 1);
	// Bow (one slow arc over the whole run) carries most of the character;
	// jitter is the smaller high-frequency term on top. Weighting them the
	// other way round is what makes a "rough" line look merely noisy.
	return {
		amp: roughness * (0.8 + 1.7 * scale),
		bow: bowing * roughness * (0.8 + 4.2 * scale)
	};
}

// ─── Sampling shapes into point runs ────────────────────────────────────────

/** A SegmentShape sampled into `samples + 1` points along its true geometry. */
function sampleShape(shape: PathShape, samples: number): Point[] {
	const out: Point[] = [];
	for (let i = 0; i <= samples; i++) out.push(pointAt(shape, i / samples));
	return out;
}

/** Every point run a shape contributes. A line/curve/arc is one run; a polyline
 *  (or a chained Path) is one run PER segment, so corners survive. */
function runsOf(shape: PathShape, samples: number): Point[][] {
	if (shape.kind === 'polyline') {
		const segs = polylineSegments(shape);
		if (!segs.length) return [];
		return segs.map((s) => sampleShape(s, samples));
	}
	return [sampleShape(shape, samples)];
}

// ─── Public: roughened `d` strings ──────────────────────────────────────────

/** One `d` string per pass for a single shape. Render each as its own `<path>`
 *  so they reveal in parallel under a draw-on animation (one path holding two
 *  subpaths would draw the first stroke, then the second). */
export function roughShape(shape: PathShape, opts?: RoughOptions, identity = ''): string[] {
	return roughRuns(runsOf(shape, resolve(opts, identity).samples), opts, identity, isClosed(shape));
}

/** One `d` string per pass for a chained multi-segment Path — every segment is
 *  roughened separately and joined with a straight `L`, so corners stay sharp
 *  and the whole chain is still ONE subpath per pass (one arrowhead, one
 *  draw-on reveal). */
export function roughShapes(shapes: PathShape[], opts?: RoughOptions, identity = ''): string[] {
	const { samples } = resolve(opts, identity);
	const runs: Point[][] = [];
	for (const s of shapes) runs.push(...runsOf(s, samples));
	return roughRuns(runs, opts, identity, false);
}

function isClosed(shape: PathShape): boolean {
	return shape.kind === 'polyline' && !!shape.close;
}

/** The shared engine: turn a list of point runs into one `d` per pass. Runs are
 *  chained inside a pass (`M` on the first, `L` to bridge into each next), so a
 *  pass is a single continuous subpath. */
function roughRuns(
	runs: Point[][],
	opts: RoughOptions | undefined,
	identity: string,
	closed: boolean
): string[] {
	const cfg = resolve(opts, identity);
	const usable = runs.filter((r) => r.length >= 2);
	if (!usable.length || cfg.roughness <= 0) return [];
	const rnd = makeRandom(cfg.seed);
	const out: string[] = [];
	for (let pass = 0; pass < cfg.passes; pass++) {
		let d = '';
		for (let i = 0; i < usable.length; i++) {
			const run = usable[i];
			const { amp, bow } = amplitudes(runLength(run), cfg.roughness, cfg.bowing);
			// A second pass wobbles a touch harder — that asymmetry is what stops
			// the doubled line from reading as a printing misregistration.
			const gain = pass === 0 ? 1 : 1.25;
			const moved = perturb(run, rnd, amp * gain, bow * gain, closed && usable.length === 1);
			const head = `${round(moved[0][0])} ${round(moved[0][1])}`;
			d += i === 0 ? `M ${head}` : ` L ${head}`;
			const cmds = catmullCommands(moved);
			if (cmds) d += ` ${cmds}`;
		}
		if (d) out.push(d);
	}
	return out;
}

// ─── Box shapes ─────────────────────────────────────────────────────────────

/** The four corners of a box, clockwise from top-left. */
export function boxCorners(x: number, y: number, w: number, h: number): Point[] {
	const X = finite(x);
	const Y = finite(y);
	const W = finite(w);
	const H = finite(h);
	return [
		[X, Y],
		[X + W, Y],
		[X + W, Y + H],
		[X, Y + H]
	];
}

/** A rectangle drawn the way a hand draws one: four INDEPENDENT edges, each
 *  slightly overshooting its corner, rather than one closed loop. The little
 *  crossed corners are the signature of the look — a tidy closed polygon reads
 *  as a computer's rectangle no matter how much you wobble it. */
export function roughRect(
	x: number,
	y: number,
	w: number,
	h: number,
	opts?: RoughOptions,
	identity = ''
): string[] {
	const cfg = resolve(opts, identity);
	if (cfg.roughness <= 0) return [];
	const c = boxCorners(x, y, w, h);
	const rnd = makeRandom(cfg.seed);
	const out: string[] = [];
	for (let pass = 0; pass < cfg.passes; pass++) {
		let d = '';
		for (let e = 0; e < 4; e++) {
			const a = c[e];
			const b = c[(e + 1) % 4];
			const len = Math.hypot(b[0] - a[0], b[1] - a[1]);
			if (!(len > 0)) continue;
			// Overshoot each end by a fraction of the roughness, along the edge.
			const ux = (b[0] - a[0]) / len;
			const uy = (b[1] - a[1]) / len;
			// Overshoot is the signature: a hand runs past the corner and starts
			// the next edge a little early, leaving the little crossed corners
			// that say "drawn". Too shy and it just reads as a wobbly rectangle.
			const over = cfg.roughness * (2.5 + rnd() * 5);
			const back = cfg.roughness * (1 + rnd() * 3);
			const from: Point = [a[0] - ux * back, a[1] - uy * back];
			const to: Point = [b[0] + ux * over, b[1] + uy * over];
			const run = sampleShape({ kind: 'line', from, to }, cfg.samples);
			const { amp, bow } = amplitudes(len, cfg.roughness, cfg.bowing);
			const gain = pass === 0 ? 1 : 1.25;
			const moved = perturb(run, rnd, amp * gain, bow * gain, false);
			d += ` M ${round(moved[0][0])} ${round(moved[0][1])} ${catmullCommands(moved)}`;
		}
		if (d) out.push(d.slice(1));
	}
	return out;
}

/** An ellipse inscribed in the box, as a closed wobbly loop per pass. Drawn as
 *  a polyline sampled off the true ellipse, so it inherits the same
 *  constant-command-count property as everything else here. */
export function roughEllipse(
	x: number,
	y: number,
	w: number,
	h: number,
	opts?: RoughOptions,
	identity = ''
): string[] {
	const cfg = resolve(opts, identity);
	if (cfg.roughness <= 0) return [];
	const pts = ellipsePoints(x, y, w, h, Math.max(12, cfg.samples * 2));
	if (pts.length < 3) return [];
	return roughRuns([pts], opts, identity, true);
}

/** `n + 1` points around the ellipse inscribed in the box (last === first). */
export function ellipsePoints(
	x: number,
	y: number,
	w: number,
	h: number,
	n = 32
): Point[] {
	const X = finite(x);
	const Y = finite(y);
	const W = finite(w);
	const H = finite(h);
	const cx = X + W / 2;
	const cy = Y + H / 2;
	const rx = W / 2;
	const ry = H / 2;
	const count = Math.max(3, Math.floor(finite(n, 32)));
	const out: Point[] = [];
	for (let i = 0; i <= count; i++) {
		const a = (i / count) * Math.PI * 2;
		out.push([cx + rx * Math.cos(a), cy + ry * Math.sin(a)]);
	}
	out[count] = [out[0][0], out[0][1]];
	return out;
}

// ─── Hachure fill ───────────────────────────────────────────────────────────

/** How a filled shape gets its ink. `solid` is the ordinary SVG fill; the rest
 *  are stroked line work, which is what makes a filled shape look drawn rather
 *  than printed. */
export type FillStyle = 'solid' | 'hachure' | 'cross-hatch';

export interface HachureOptions extends RoughOptions {
	/** Spacing between fill lines, canvas px. */
	gap?: number;
	/** Direction of the fill lines, degrees. */
	angle?: number;
}

/** The scanline segments that fill a polygon with parallel lines at `angle`,
 *  spaced `gap` apart. Pure, and the piece worth unit-testing hardest: a
 *  convex box gives one segment per line, a concave polygon gives several, and
 *  a degenerate polygon gives none rather than an infinite loop. */
export function hachureSegments(
	poly: Point[],
	angleDeg: number,
	gap: number
): [Point, Point][] {
	const step = Math.max(1, finite(gap, 8));
	const pts = poly.filter((p) => Number.isFinite(p[0]) && Number.isFinite(p[1]));
	if (pts.length < 3) return [];
	const a = (finite(angleDeg, -45) * Math.PI) / 180;
	const cos = Math.cos(-a);
	const sin = Math.sin(-a);
	// Rotate into a frame where the fill lines are horizontal.
	const rot = pts.map(([px, py]): Point => [px * cos - py * sin, px * sin + py * cos]);
	let minY = Infinity;
	let maxY = -Infinity;
	for (const [, py] of rot) {
		if (py < minY) minY = py;
		if (py > maxY) maxY = py;
	}
	if (!Number.isFinite(minY) || !Number.isFinite(maxY) || maxY - minY < 1e-9) return [];
	const icos = Math.cos(a);
	const isin = Math.sin(a);
	const out: [Point, Point][] = [];
	const n = rot.length;
	for (let y = minY + step / 2; y < maxY; y += step) {
		const xs: number[] = [];
		for (let i = 0; i < n; i++) {
			const p = rot[i];
			const q = rot[(i + 1) % n];
			const y0 = p[1];
			const y1 = q[1];
			// Half-open span test: a vertex on the boundary is counted once, so
			// crossings stay even and the pairing below never straddles the shape.
			if (y0 === y1) continue;
			if (y < Math.min(y0, y1) || y >= Math.max(y0, y1)) continue;
			xs.push(p[0] + ((y - y0) / (y1 - y0)) * (q[0] - p[0]));
		}
		if (xs.length < 2) continue;
		xs.sort((m, o) => m - o);
		for (let i = 0; i + 1 < xs.length; i += 2) {
			const x0 = xs[i];
			const x1 = xs[i + 1];
			if (x1 - x0 < 1e-9) continue;
			out.push([
				[x0 * icos - y * isin, x0 * isin + y * icos],
				[x1 * icos - y * isin, x1 * isin + y * icos]
			]);
		}
	}
	return out;
}

/** A `d` string of hand-drawn fill lines over a polygon. Each scanline is
 *  wobbled by the same seeded engine as the outlines, so the fill and the
 *  border look like they came from the same pen. */
export function hachurePath(
	poly: Point[],
	opts?: HachureOptions,
	identity = '',
	style: FillStyle = 'hachure'
): string {
	const cfg = resolve(opts, identity);
	const gap = Math.max(2, finite(opts?.gap ?? 10, 10));
	const angle = finite(opts?.angle ?? -45, -45);
	const angles = style === 'cross-hatch' ? [angle, angle + 90] : [angle];
	const rnd = makeRandom(cfg.seed ^ 0x9e3779b9);
	let d = '';
	for (const ang of angles) {
		for (const [a, b] of hachureSegments(poly, ang, gap)) {
			const len = Math.hypot(b[0] - a[0], b[1] - a[1]);
			// Fill lines wobble at HALF the outline's amplitude: a fill that
			// wanders as much as its border stops reading as "inside".
			const { amp, bow } = amplitudes(len, cfg.roughness * 0.5, cfg.bowing * 0.5);
			const run = sampleShape({ kind: 'line', from: a, to: b }, 4);
			const moved = perturb(run, rnd, amp, bow, false);
			d += ` M ${round(moved[0][0])} ${round(moved[0][1])} ${catmullCommands(moved)}`;
		}
	}
	return d.slice(1);
}

/** The polygon a box-geometry shape fills: the rect's corners, or the sampled
 *  ellipse. Both are what `hachurePath` wants. */
export function fillPolygon(
	kind: 'rect' | 'ellipse',
	x: number,
	y: number,
	w: number,
	h: number
): Point[] {
	return kind === 'rect' ? boxCorners(x, y, w, h) : ellipsePoints(x, y, w, h, 48).slice(0, -1);
}

// ─── Arrowheads ─────────────────────────────────────────────────────────────

/** A hand-drawn arrowhead: the two barbs as open strokes rather than a filled
 *  triangle, which is how a pen actually makes one. Takes the same tip/angle/
 *  size as drawCore's `arrowHead`, so callers can swap between them. */
export function roughArrowHead(
	tip: Point,
	angle: number,
	size: number,
	opts?: RoughOptions,
	identity = ''
): string {
	const cfg = resolve(opts, identity);
	const s = finite(size, 16);
	const t: Point = [finite(tip[0]), finite(tip[1])];
	const spread = 0.42;
	const rnd = makeRandom(cfg.seed ^ 0x85ebca6b);
	let d = '';
	for (const sign of [1, -1]) {
		const a = finite(angle) + Math.PI + sign * spread;
		const end: Point = [t[0] + Math.cos(a) * s, t[1] + Math.sin(a) * s];
		const run = sampleShape({ kind: 'line', from: t, to: end }, 4);
		const { amp, bow } = amplitudes(s, cfg.roughness * 0.6, cfg.bowing * 0.4);
		const moved = perturb(run, rnd, amp, bow, false);
		d += ` M ${round(moved[0][0])} ${round(moved[0][1])} ${catmullCommands(moved)}`;
	}
	return d.slice(1);
}

// ─── Identity helpers ───────────────────────────────────────────────────────

/** A stable identity string for a shape, for seeding.
 *
 *  CALLERS: build this from the shape's BASE props and nothing else — never
 *  from live/animated geometry. Every stop of an animated shape must resolve to
 *  the SAME seed, or each keyframe re-rolls its wobble and the shape boils as
 *  it morphs. `name` leads so two geometrically identical shapes still differ. */
export function shapeIdentity(name: string, ...nums: (number | undefined)[]): string {
	return `${name}|${nums.map((n) => round(finite(n ?? 0))).join(',')}`;
}
