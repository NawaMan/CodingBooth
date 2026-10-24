/*
  Freehand ink — the variable-width outline behind the ANNOTATE pen.

  Vendored from perfect-freehand 1.2.3 by Steve Ruiz (https://github.com/steveruizok/perfect-freehand),
  trimmed to the parts the pen uses, typed for this codebase, and made TOTAL: every input
  may be junk (a stroke another window wrote, a NaN from a pointer fired before layout) and
  the answer is still a drawable result. The algorithm itself is unchanged — the numbers it
  produces match upstream for the same input and options.

  Why the outline, not a stroked line: perfect-freehand turns the sampled centre line into a
  closed POLYGON whose width breathes with the hand's speed (simulated pressure — no stored
  pressure, see `simulatePressure`). It is painted as a FILL, so the ink tapers at a flick and
  swells on a slow, deliberate mark, the way a real marker does. The stored `Stroke.points`
  stay the single source of truth; the outline is derived at render time, on every window.

  ── perfect-freehand licence ──────────────────────────────────────────────────────────────
  MIT License

  Copyright (c) 2021 Stephen Ruiz Ltd

  Permission is hereby granted, free of charge, to any person obtaining a copy of this
  software and associated documentation files (the "Software"), to deal in the Software
  without restriction, including without limitation the rights to use, copy, modify, merge,
  publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons
  to whom the Software is furnished to do so, subject to the following conditions:

  The above copyright notice and this permission notice shall be included in all copies or
  substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
  INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
  PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE
  FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
  OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
  DEALINGS IN THE SOFTWARE.
*/

import type { Point } from '$lib/draw/types';
import { finitePoint } from '$lib/draw/drawCore';

/** A taper/cap setting for one END of the stroke. `taper` is the length in canvas px over
    which the ink narrows to a point (0 = none); `cap` rounds an un-tapered end. */
export interface FreehandEnd {
	taper: number;
	cap: boolean;
}

/** The pen's shape — perfect-freehand's options, minus the ones we never vary. */
export interface FreehandOptions {
	/** Diameter of the ink at full pressure, in canvas px. */
	size: number;
	/** How much speed thins the line: 0 = constant width, 1 = maximum swing. Negative
	    values invert it (faster = thicker). */
	thinning: number;
	/** How much the line lags behind the hand to iron out jitter, 0–1. */
	streamline: number;
	/** How much the outline's own corners are softened, 0–1. */
	smoothing: number;
	/** Pressure → width curve. Upstream takes a function; we store a NAME, so the options
	    can travel through a prop or JSON. */
	easing: FreehandEasing;
	start: FreehandEnd;
	end: FreehandEnd;
}

export type FreehandEasing = 'linear' | 'easeIn' | 'easeOut' | 'easeInOut';

/** The deck's default pen: a size-12 marker that thins noticeably with speed, rounded at
    both ends, no taper — chosen in perfect-freehand's playground for presenter ink. */
export const DEFAULT_FREEHAND: FreehandOptions = {
	size: 12,
	thinning: 0.7,
	streamline: 0.6,
	smoothing: 0.5,
	easing: 'linear',
	start: { taper: 0, cap: true },
	end: { taper: 0, cap: true }
};

const EASINGS: Record<FreehandEasing, (t: number) => number> = {
	linear: (t) => t,
	easeIn: (t) => t * t,
	easeOut: (t) => t * (2 - t),
	easeInOut: (t) => (t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t)
};

/** A partial set of options, as a prop or a stored blob might carry them. */
export type FreehandInput = Partial<Omit<FreehandOptions, 'start' | 'end'>> & {
	start?: Partial<FreehandEnd>;
	end?: Partial<FreehandEnd>;
};

const clamp = (v: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, v));
const finite = (v: unknown, fallback: number): number =>
	typeof v === 'number' && Number.isFinite(v) ? v : fallback;

/** Merge a partial over the defaults, coercing every field into its legal range — so a typo
    in a deck's prop degrades to the default rather than a NaN outline. */
export function resolveFreehand(input?: FreehandInput | null): FreehandOptions {
	const d = DEFAULT_FREEHAND;
	const i: FreehandInput = input && typeof input === 'object' ? input : {};
	const end = (raw: Partial<FreehandEnd> | undefined, def: FreehandEnd): FreehandEnd => ({
		taper: Math.max(0, finite(raw?.taper, def.taper)),
		cap: typeof raw?.cap === 'boolean' ? raw.cap : def.cap
	});
	return {
		size: Math.max(0.5, finite(i.size, d.size)),
		thinning: clamp(finite(i.thinning, d.thinning), -1, 1),
		streamline: clamp(finite(i.streamline, d.streamline), 0, 1),
		smoothing: clamp(finite(i.smoothing, d.smoothing), 0, 1),
		easing: i.easing && i.easing in EASINGS ? i.easing : d.easing,
		start: end(i.start, d.start),
		end: end(i.end, d.end)
	};
}

/** The widest the ink can get, as a RADIUS in canvas px. `size` is the width at middling
    pressure, not a ceiling: with thinning, a slow (high simulated pressure) stretch swells to
    `size × ease(0.5 + |thinning|/2)` — 10.2 for the default size 12 / thinning 0.7. The eraser
    reaches by this, so a fat slow loop is as easy to catch as it looks. */
export function freehandMaxRadius(options?: FreehandInput | null): number {
	const o = resolveFreehand(options);
	return o.size * EASINGS[o.easing](0.5 + Math.abs(o.thinning) / 2);
}

// ── Vector helpers (upstream's vec.ts) ────────────────────────────────────────────────────

type Vec = [number, number];
const add = (a: Vec, b: Vec): Vec => [a[0] + b[0], a[1] + b[1]];
const sub = (a: Vec, b: Vec): Vec => [a[0] - b[0], a[1] - b[1]];
const mul = (a: Vec, n: number): Vec => [a[0] * n, a[1] * n];
const neg = (a: Vec): Vec => [-a[0], -a[1]];
const per = (a: Vec): Vec => [a[1], -a[0]];
const dpr = (a: Vec, b: Vec): number => a[0] * b[0] + a[1] * b[1];
const isEqual = (a: Vec, b: Vec): boolean => a[0] === b[0] && a[1] === b[1];
const dist = (a: Vec, b: Vec): number => Math.hypot(a[1] - b[1], a[0] - b[0]);
const dist2 = (a: Vec, b: Vec): number => (a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2;
const lrp = (a: Vec, b: Vec, t: number): Vec => add(a, mul(sub(b, a), t));
const prj = (a: Vec, b: Vec, c: number): Vec => add(a, mul(b, c));
function uni(a: Vec): Vec {
	const l = Math.hypot(a[0], a[1]);
	return l === 0 ? [0, 0] : [a[0] / l, a[1] / l];
}
function rotAround(a: Vec, c: Vec, r: number): Vec {
	const s = Math.sin(r);
	const co = Math.cos(r);
	const px = a[0] - c[0];
	const py = a[1] - c[1];
	return [px * co - py * s + c[0], px * s + py * co + c[1]];
}

// ── The algorithm (upstream's getStrokePoints / getStrokeOutlinePoints) ───────────────────

const DEFAULT_PRESSURE = 0.5;
/** Lower for the first sample, so a stroke does not start fat — a hand starts slow. */
const DEFAULT_FIRST_PRESSURE = 0.25;
const RATE_OF_PRESSURE_CHANGE = 0.275;
const FIXED_PI = Math.PI + 0.0001;

interface StrokePoint {
	point: Vec;
	pressure: number;
	vector: Vec;
	distance: number;
	runningLength: number;
}

const strokeRadius = (
	size: number,
	thinning: number,
	pressure: number,
	ease: (t: number) => number
) => size * ease(0.5 - thinning * (0.5 - pressure));

/** Streamline the raw samples and annotate each with its direction and running length. */
function strokePoints(input: Vec[], o: FreehandOptions, isComplete: boolean): StrokePoint[] {
	if (input.length === 0) return [];
	const t = 0.15 + (1 - o.streamline) * 0.85;
	let pts = input;

	// Two points: interpolate, so a straight two-point mark (a Shift-snapped line) still gets
	// enough samples to shape. One point: add a neighbour, so a tap has a direction.
	if (pts.length === 2) {
		const last = pts[1];
		pts = [pts[0]];
		for (let i = 1; i < 5; i++) pts.push(lrp(pts[0], last, i / 4));
	}
	if (pts.length === 1) pts = [pts[0], add(pts[0], [1, 1])];

	const out: StrokePoint[] = [
		{
			point: pts[0],
			pressure: DEFAULT_FIRST_PRESSURE,
			vector: [1, 1],
			distance: 0,
			runningLength: 0
		}
	];
	let reachedMinimumLength = false;
	let runningLength = 0;
	let prev = out[0];
	const max = pts.length - 1;

	for (let i = 1; i < pts.length; i++) {
		const point = isComplete && i === max ? pts[i] : lrp(prev.point, pts[i], t);
		if (isEqual(prev.point, point)) continue;
		const distance = dist(point, prev.point);
		runningLength += distance;
		if (i < max && !reachedMinimumLength) {
			if (runningLength < o.size) continue;
			reachedMinimumLength = true;
		}
		prev = {
			point,
			pressure: DEFAULT_PRESSURE,
			vector: uni(sub(prev.point, point)),
			distance,
			runningLength
		};
		out.push(prev);
	}
	out[0].vector = out[1]?.vector ?? [0, 0];
	return out;
}

/** Turn the annotated centre line into the outline polygon. */
function outlinePoints(points: StrokePoint[], o: FreehandOptions, isComplete: boolean): Vec[] {
	const { size, smoothing, thinning } = o;
	if (points.length === 0 || size <= 0) return [];
	const ease = EASINGS[o.easing];
	const taperStartEase = (t: number) => t * (2 - t);
	const taperEndEase = (t: number) => --t * t * t + 1;

	const totalLength = points[points.length - 1].runningLength;
	const taperStart = o.start.taper;
	const taperEnd = o.end.taper;
	const minDistance = Math.pow(size * smoothing, 2);
	const leftPts: Vec[] = [];
	const rightPts: Vec[] = [];

	// Simulated pressure: a fast segment (long distance between samples) reads as light.
	const simulate = (prevP: number, distance: number) => {
		const sp = Math.min(1, distance / size);
		const rp = Math.min(1, 1 - sp);
		return Math.min(1, prevP + (rp - prevP) * (sp * RATE_OF_PRESSURE_CHANGE));
	};

	let prevPressure = points
		.slice(0, 10)
		.reduce((acc, curr) => (acc + simulate(acc, curr.distance)) / 2, points[0].pressure);

	let radius = strokeRadius(size, thinning, points[points.length - 1].pressure, ease);
	let firstRadius: number | undefined;
	let prevVector = points[0].vector;
	let pl = points[0].point;
	let pr = pl;
	let tl = pl;
	let tr = pr;
	let prevSharpCorner = false;

	for (let i = 0; i < points.length; i++) {
		let { pressure } = points[i];
		const { point, vector, distance, runningLength } = points[i];

		// Drop points too close to the end — they make the end cap wobble.
		if (i < points.length - 1 && totalLength - runningLength < 3) continue;

		if (thinning) {
			pressure = simulate(prevPressure, distance);
			radius = strokeRadius(size, thinning, pressure, ease);
		} else {
			radius = size / 2;
		}
		if (firstRadius === undefined) firstRadius = radius;

		const ts = runningLength < taperStart ? taperStartEase(runningLength / taperStart) : 1;
		const te =
			totalLength - runningLength < taperEnd
				? taperEndEase((totalLength - runningLength) / taperEnd)
				: 1;
		radius = Math.max(0.01, radius * Math.min(ts, te));

		const nextVector = (i < points.length - 1 ? points[i + 1] : points[i]).vector;
		const nextDpr = i < points.length - 1 ? dpr(vector, nextVector) : 1.0;
		const prevDpr = dpr(vector, prevVector);
		const sharpCorner = prevDpr < 0 && !prevSharpCorner;
		const nextSharpCorner = nextDpr < 0;

		// A hairpin: draw a half-circle around the point instead of a spike.
		if (sharpCorner || nextSharpCorner) {
			const offset = mul(per(prevVector), radius);
			for (let step = 1 / 13, t = 0; t <= 1; t += step) {
				tl = rotAround(sub(point, offset), point, FIXED_PI * t);
				leftPts.push(tl);
				tr = rotAround(add(point, offset), point, FIXED_PI * -t);
				rightPts.push(tr);
			}
			pl = tl;
			pr = tr;
			if (nextSharpCorner) prevSharpCorner = true;
			continue;
		}
		prevSharpCorner = false;

		if (i === points.length - 1) {
			const offset = mul(per(vector), radius);
			leftPts.push(sub(point, offset));
			rightPts.push(add(point, offset));
			continue;
		}

		const offset = mul(per(lrp(nextVector, vector, nextDpr)), radius);
		tl = sub(point, offset);
		if (i <= 1 || dist2(pl, tl) > minDistance) {
			leftPts.push(tl);
			pl = tl;
		}
		tr = add(point, offset);
		if (i <= 1 || dist2(pr, tr) > minDistance) {
			rightPts.push(tr);
			pr = tr;
		}
		prevPressure = pressure;
		prevVector = vector;
	}

	const firstPoint = points[0].point;
	const lastPoint: Vec =
		points.length > 1 ? points[points.length - 1].point : add(points[0].point, [1, 1]);
	const startCap: Vec[] = [];
	const endCap: Vec[] = [];

	if (points.length === 1) {
		// A dot.
		if (!(taperStart || taperEnd) || isComplete) {
			const start = prj(firstPoint, uni(per(sub(firstPoint, lastPoint))), -(firstRadius ?? radius));
			const dot: Vec[] = [];
			for (let step = 1 / 13, t = step; t <= 1; t += step)
				dot.push(rotAround(start, firstPoint, FIXED_PI * 2 * t));
			return dot;
		}
	} else {
		if (taperStart) {
			// The taper already closes the start.
		} else if (o.start.cap) {
			for (let step = 1 / 13, t = step; t <= 1; t += step) {
				startCap.push(rotAround(rightPts[0], firstPoint, FIXED_PI * t));
			}
		} else {
			const corners = sub(leftPts[0], rightPts[0]);
			const a = mul(corners, 0.5);
			const b = mul(corners, 0.51);
			startCap.push(sub(firstPoint, a), sub(firstPoint, b), add(firstPoint, b), add(firstPoint, a));
		}

		const direction = per(neg(points[points.length - 1].vector));
		if (taperEnd) {
			endCap.push(lastPoint);
		} else if (o.end.cap) {
			const start = prj(lastPoint, direction, radius);
			for (let step = 1 / 29, t = step; t < 1; t += step)
				endCap.push(rotAround(start, lastPoint, FIXED_PI * 3 * t));
		} else {
			endCap.push(
				add(lastPoint, mul(direction, radius)),
				add(lastPoint, mul(direction, radius * 0.99)),
				sub(lastPoint, mul(direction, radius * 0.99)),
				sub(lastPoint, mul(direction, radius))
			);
		}
	}

	return leftPts.concat(endCap, rightPts.reverse(), startCap);
}

/** The outline polygon for a stroke's centre-line points — perfect-freehand's `getStroke`.
    `complete` is upstream's `last`: true once the pen has lifted, so the final sample is
    honoured exactly instead of streamlined towards. */
export function freehandOutline(
	points: Point[],
	options?: FreehandInput | null,
	complete = true
): Point[] {
	if (!Array.isArray(points) || points.length === 0) return [];
	const o = resolveFreehand(options);
	const pts = points.map(finitePoint) as Vec[];
	return outlinePoints(strokePoints(pts, o, complete), o, complete);
}

const fx = (n: number) => (Number.isFinite(n) ? n.toFixed(2) : '0.00');

/** The SVG `d` for an outline polygon, smoothed with quadratic curves through the midpoints
    (perfect-freehand's recommended `getSvgPathFromStroke`). Closed, for painting as a fill.
    Fewer than 4 outline points cannot make the curve and yield ''. */
export function outlineD(outline: Point[]): string {
	const len = outline.length;
	if (len < 4) return '';
	let a = outline[0];
	let b = outline[1];
	const c = outline[2];
	let d =
		`M${fx(a[0])},${fx(a[1])} Q${fx(b[0])},${fx(b[1])} ` +
		`${fx((b[0] + c[0]) / 2)},${fx((b[1] + c[1]) / 2)} T`;
	for (let i = 2; i < len - 1; i++) {
		a = outline[i];
		b = outline[i + 1];
		d += `${fx((a[0] + b[0]) / 2)},${fx((a[1] + b[1]) / 2)} `;
	}
	return d + 'Z';
}

/** Points → the filled pen path, in one call. */
export function freehandD(
	points: Point[],
	options?: FreehandInput | null,
	complete = true
): string {
	return outlineD(freehandOutline(points, options, complete));
}
