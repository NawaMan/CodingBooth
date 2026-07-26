// Pure geometry for the Draw component family. No component imports, no DOM —
// everything here is independently unit-testable (tests/drawCore.test.ts),
// exactly as tableCore.ts is for DataTable. Components contain only $derived
// wiring and SVG markup; this module owns paths, arrowheads, and segment math
// (Phase 2 adds curves/arcs/evaluators feeding the same arrowHead()).
//
// Everything is NaN-safe: a mid-edit half-typed prop must never emit NaNpx
// into the SVG (the same discipline as KeyframeStudio's r()). All numbers
// pass through finite()/round() before reaching an attribute string.

import type { PathSegment, PathShape, Point, SegmentShape } from './types';

/** Coerce a possibly non-finite number to a safe finite one. */
export function finite(value: number, fallback = 0): number {
	return Number.isFinite(value) ? value : fallback;
}

/** A Point with both coordinates coerced finite. */
export function finitePoint(p: Point): Point {
	return [finite(p[0]), finite(p[1])];
}

/** Round to 2 decimals for clean, diffable SVG attributes (never NaN,
 *  never -0). */
export function round(value: number): number {
	return Math.round(finite(value) * 100) / 100 + 0;
}

/** End tangent of the straight segment from → to, in radians.
 *  Zero-length segments return 0 (pointing right), never NaN. */
export function segmentAngle(from: Point, to: Point): number {
	const [fx, fy] = finitePoint(from);
	const [tx, ty] = finitePoint(to);
	if (fx === tx && fy === ty) return 0;
	return Math.atan2(ty - fy, tx - fx);
}

/** The point `by` px back from `to` along the segment from → to.
 *  Degenerate zero-length segments return `to` unchanged (never NaN);
 *  `by` longer than the segment clamps at `from` (the shaft collapses,
 *  it never flips past its own start). Negative `by` extends past `to`. */
export function shorten(from: Point, to: Point, by: number): Point {
	const [fx, fy] = finitePoint(from);
	const [tx, ty] = finitePoint(to);
	const dx = tx - fx;
	const dy = ty - fy;
	const len = Math.hypot(dx, dy);
	if (len === 0) return [tx, ty];
	const t = Math.min(finite(by) / len, 1);
	return [round(tx - dx * t), round(ty - dy * t)];
}

/** The three polygon points of an arrowhead of `size` at `tip`, pointing
 *  along `angle` (radians): the tip itself plus the two base corners, `size`
 *  back from the tip and half a `size` out to each side (a 2:1 head). */
export function arrowHead(tip: Point, angle: number, size: number): Point[] {
	const [x, y] = finitePoint(tip);
	const a = finite(angle);
	const s = finite(size);
	const bx = x - Math.cos(a) * s;
	const by = y - Math.sin(a) * s;
	const wx = -Math.sin(a) * (s / 2);
	const wy = Math.cos(a) * (s / 2);
	return [
		[round(x), round(y)],
		[round(bx + wx), round(by + wy)],
		[round(bx - wx), round(by - wy)]
	];
}

/** Default arrowhead size for a given stroke thickness (canvas px). */
export function defaultArrowSize(thickness: number): number {
	return Math.max(12, finite(thickness, 4) * 4);
}

/** The `d` string for a straight segment. */
export function linePath(from: Point, to: Point): string {
	const [fx, fy] = finitePoint(from);
	const [tx, ty] = finitePoint(to);
	return `M ${round(fx)} ${round(fy)} L ${round(tx)} ${round(ty)}`;
}

/** The `d` string for a Bézier curve: quadratic with one control point,
 *  cubic with two. */
export function curvePath(from: Point, to: Point, c1: Point, c2?: Point): string {
	const [fx, fy] = finitePoint(from);
	const [tx, ty] = finitePoint(to);
	const [ax, ay] = finitePoint(c1);
	if (c2) {
		const [bx, by] = finitePoint(c2);
		return `M ${round(fx)} ${round(fy)} C ${round(ax)} ${round(ay)} ${round(bx)} ${round(by)} ${round(tx)} ${round(ty)}`;
	}
	return `M ${round(fx)} ${round(fy)} Q ${round(ax)} ${round(ay)} ${round(tx)} ${round(ty)}`;
}

/** The `d` string for a circular arc through from/to with a signed `bend`
 *  (sagitta / chord length, clamped to [-1, 1] — see clampBend; positive
 *  bulges toward (dy, -dx), screen-up for a left-to-right chord). The
 *  radius / large-arc / sweep math stays in here — raw SVG arc parameters
 *  never appear in the public API. bend 0 and zero-length chords degenerate
 *  to the straight line. */
export function arcPath(from: Point, to: Point, bend: number): string {
	const g = arcGeometry(from, to, bend);
	if (!g) return linePath(from, to);
	const [fx, fy] = finitePoint(from);
	const [tx, ty] = finitePoint(to);
	const largeArc = Math.abs(g.delta) > Math.PI ? 1 : 0;
	const sweep = g.delta > 0 ? 1 : 0;
	const r = round(g.r);
	return `M ${round(fx)} ${round(fy)} A ${r} ${r} 0 ${largeArc} ${sweep} ${round(tx)} ${round(ty)}`;
}

/** The `d` string for straight segments through `points`, optionally closed.
 *  Fewer than 2 points render nothing (empty string). */
export function polylinePath(points: Point[], close = false): string {
	if (points.length < 2) return '';
	const [first, ...rest] = points.map(finitePoint);
	const d =
		`M ${round(first[0])} ${round(first[1])} ` +
		rest.map(([x, y]) => `L ${round(x)} ${round(y)}`).join(' ');
	return close ? `${d} Z` : d;
}

/** Catmull-Rom through `points`, converted to cubic Bézier segments — the
 *  curve passes exactly THROUGH every input point (no overshoot-prone
 *  fitting), collinear points yield collinear control points, and 2 points
 *  degenerate to a straight line segment. `close` wraps the neighbors so the
 *  loop is smooth through the first/last point too. Returned as PathShapes
 *  so pointAt/angleAt work per segment (segment i runs points[i] →
 *  points[i+1]). */
export function smoothSegments(points: Point[], close = false): SegmentShape[] {
	const pts = points.map(finitePoint);
	const n = pts.length;
	if (n < 2) return [];
	if (n === 2) return [{ kind: 'line', from: pts[0], to: pts[1] }];
	const count = close ? n : n - 1;
	const at = (i: number): Point =>
		close ? pts[((i % n) + n) % n] : pts[Math.max(0, Math.min(n - 1, i))];
	const segments: SegmentShape[] = [];
	for (let i = 0; i < count; i++) {
		const p0 = at(i - 1);
		const p1 = at(i);
		const p2 = at(i + 1);
		const p3 = at(i + 2);
		segments.push({
			kind: 'cubic',
			from: p1,
			c1: [round(p1[0] + (p2[0] - p0[0]) / 6), round(p1[1] + (p2[1] - p0[1]) / 6)],
			c2: [round(p2[0] - (p3[0] - p1[0]) / 6), round(p2[1] - (p3[1] - p1[1]) / 6)],
			to: p2
		});
	}
	return segments;
}

/** A polyline shape expanded to its segment chain — straight lines through
 *  the points, or the Catmull-Rom cubics when `smooth` (`close` appends the
 *  seam segment either way). This is how the evaluators see a polyline:
 *  pointAt/angleAt delegate to the chain via the multi-segment locators, so
 *  arc-length distribution and NaN-safety are inherited. Never recursive —
 *  the chain is only ever lines and cubics. Fewer than 2 points → []. */
export function polylineSegments(shape: {
	points: Point[];
	close?: boolean;
	smooth?: boolean;
}): SegmentShape[] {
	const pts = (Array.isArray(shape.points) ? shape.points : []).map(finitePoint);
	if (pts.length < 2) return [];
	if (shape.smooth) return smoothSegments(pts, shape.close);
	const count = shape.close ? pts.length : pts.length - 1;
	const segments: SegmentShape[] = [];
	for (let i = 0; i < count; i++) {
		segments.push({ kind: 'line', from: pts[i], to: pts[(i + 1) % pts.length] });
	}
	return segments;
}

/** The `d` string for a smooth (Catmull-Rom) path through `points`. */
export function smoothPath(points: Point[], close = false): string {
	const segments = smoothSegments(points, close);
	if (segments.length === 0) return '';
	const first = finitePoint(segments[0].from);
	const parts = [`M ${round(first[0])} ${round(first[1])}`];
	for (const seg of segments) {
		if (seg.kind === 'cubic') {
			parts.push(
				`C ${round(seg.c1[0])} ${round(seg.c1[1])} ${round(seg.c2[0])} ${round(seg.c2[1])} ${round(seg.to[0])} ${round(seg.to[1])}`
			);
		} else {
			parts.push(`L ${round(seg.to[0])} ${round(seg.to[1])}`);
		}
	}
	if (close) parts.push('Z');
	return parts.join(' ');
}

/** The pure inverse of arcPath's bend → apex math: given a dragged apex
 *  point, the signed `bend` that puts the arc's apex at its projection onto
 *  the chord's perpendicular bisector. bend = ((apex − mid) · n) / L with
 *  n = (dy, −dx)/L — so dragging across the chord flips the sign, exactly
 *  mirroring pointAt(arc, 0.5). Rounded to 3 decimals for clean copied
 *  tags, clamped to [-1, 1]; a degenerate (zero-length) chord returns 0. */
export function bendFromApex(from: Point, to: Point, apex: Point): number {
	const [fx, fy] = finitePoint(from);
	const [tx, ty] = finitePoint(to);
	const dx = tx - fx;
	const dy = ty - fy;
	const len2 = dx * dx + dy * dy;
	if (len2 === 0) return 0;
	const [ax, ay] = finitePoint(apex);
	const mx = (fx + tx) / 2;
	const my = (fy + ty) / 2;
	const bend = ((ax - mx) * dy - (ay - my) * dx) / len2;
	return clampBend(Math.round(bend * 1000) / 1000 + 0);
}

/** Snap a dragged point to the nearest angular detent (default 90°: horizontal
 *  or vertical only — no diagonal, matching Block's Shift axis-lock) relative to
 *  `ref`, by PROJECTING onto the snapped ray — a horizontal snap keeps the
 *  dragged x and pins y to ref's, the drawing-tool behavior. Pass `stepDeg=45`
 *  for a shape that wants diagonal detents too. Coincident points return
 *  unchanged. */
export function snapToAngles(p: Point, ref: Point, stepDeg = 90): Point {
	const [px, py] = finitePoint(p);
	const [rx, ry] = finitePoint(ref);
	const dx = px - rx;
	const dy = py - ry;
	if (dx === 0 && dy === 0) return [px, py];
	const step = ((finite(stepDeg, 45) || 45) * Math.PI) / 180;
	const a = Math.round(Math.atan2(dy, dx) / step) * step;
	const ux = Math.cos(a);
	const uy = Math.sin(a);
	const t = dx * ux + dy * uy;
	return [round(rx + ux * t), round(ry + uy * t)];
}

/** Anchor point for a shape's visible label: the point at parameter `at`,
 *  offset `offset` px perpendicular to the local tangent. Positive offset is
 *  to the LEFT of the direction of travel — screen-up on a left-to-right
 *  shape, outside the bulge on a positively-bent arc. */
export function labelPos(shape: PathShape, at = 0.5, offset = 20): Point {
	const [x, y] = pointAt(shape, at);
	const a = angleAt(shape, at);
	const o = finite(offset);
	return [round(x + Math.sin(a) * o), round(y - Math.cos(a) * o)];
}

/** Format a point list for an SVG <polygon points> attribute. */
export function polygonPoints(points: Point[]): string {
	return points.map(([x, y]) => `${round(x)},${round(y)}`).join(' ');
}

/** A shape sampled into a fixed-count polyline `d` (M + `segments` L's).
 *  Used for animating arcs: SVG arc-command flags (large-arc/sweep) don't
 *  interpolate, so a bend sign-flip or threshold cross would jump between
 *  two `A` keyframes — a same-count polyline morphs smoothly instead. The
 *  count is constant across stops (that's the point), so `d: path()`
 *  interpolates. */
export function samplePath(shape: PathShape, segments = 64): string {
	const n = Math.max(1, Math.floor(finite(segments, 64)));
	const p0 = pointAt(shape, 0);
	let d = `M ${round(p0[0])} ${round(p0[1])}`;
	for (let k = 1; k <= n; k++) {
		const p = pointAt(shape, k / n);
		d += ` L ${round(p[0])} ${round(p[1])}`;
	}
	return d;
}

/** `samples + 1` parameter values t₀…tₙ whose points are uniformly spaced by
 *  ARC LENGTH along the shape (t₀ = 0, tₙ = 1). A bézier's parameter t is not
 *  proportional to distance — a rider sampled uniformly in t sprints where the
 *  control points stretch the parameterization and dawdles where they bunch
 *  it. Uniform-length spacing gives constant travel speed, which is also what
 *  locks a Sprite to a draw-on stroke's pen tip: `stroke-dashoffset` reveals
 *  by arc length, so with a shared duration + timing function the two meet at
 *  every frame. Built from a dense chord-length table (`resolution` segments,
 *  linearly interpolated); a degenerate (zero-length) shape falls back to
 *  uniform t. */
export function uniformLengthParams(shape: PathShape, samples: number, resolution = 256): number[] {
	const n = Math.max(1, Math.floor(finite(samples, 1)));
	const res = Math.max(n, Math.floor(finite(resolution, 256)));
	// Cumulative chord lengths over `res` uniform-t segments.
	const cum = new Array<number>(res + 1);
	cum[0] = 0;
	let prev = pointAt(shape, 0);
	for (let i = 1; i <= res; i++) {
		const p = pointAt(shape, i / res);
		cum[i] = cum[i - 1] + Math.hypot(p[0] - prev[0], p[1] - prev[1]);
		prev = p;
	}
	const total = cum[res];
	if (!(total > 0)) return Array.from({ length: n + 1 }, (_, k) => k / n);
	// Walk the table once: for each target fraction, interpolate t within the
	// bracketing segment. Both sequences are monotonic, so `i` never rewinds.
	const out = new Array<number>(n + 1);
	out[0] = 0;
	let i = 1;
	for (let k = 1; k < n; k++) {
		const target = (k / n) * total;
		while (i < res && cum[i] < target) i++;
		const span = cum[i] - cum[i - 1];
		const frac = span > 0 ? (target - cum[i - 1]) / span : 0;
		out[k] = (i - 1 + frac) / res;
	}
	out[n] = 1;
	return out;
}

// ─── Shape evaluators (Phase 2) ─────────────────────────────────────────────
// pointAt/angleAt over the PathShape union power label placement and curved
// arrow tangents now, and Phase 3's bend handle later. All t are clamped to
// [0, 1]; all inputs are coerced finite.

const TWO_PI = Math.PI * 2;

function clamp01(t: number): number {
	const v = finite(t);
	return v < 0 ? 0 : v > 1 ? 1 : v;
}

function lerpPoint(a: Point, b: Point, t: number): Point {
	return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t];
}

/** `bend` (the sagitta as a signed fraction of the chord — see Arc) is
 *  clamped to [-1, 1]: at |bend| = 1 the bulge already equals the whole
 *  chord length, and beyond that arcs degenerate into near-loops. */
export function clampBend(bend: number): number {
	return Math.max(-1, Math.min(1, finite(bend)));
}

/** The circle behind an arc shape: center, radius, start angle, and the
 *  signed angular span (positive = SVG sweep 1). Positive bend bulges toward
 *  the side of unit normal (dy, -dx)/|chord| — screen-up for a left-to-right
 *  chord. Returns null when the arc degenerates to a straight line
 *  (bend 0 or a zero-length chord). */
function arcGeometry(
	from: Point,
	to: Point,
	bend: number
): { cx: number; cy: number; r: number; a0: number; delta: number } | null {
	const b = clampBend(bend);
	const [fx, fy] = finitePoint(from);
	const [tx, ty] = finitePoint(to);
	const dx = tx - fx;
	const dy = ty - fy;
	const len = Math.hypot(dx, dy);
	if (len === 0 || b === 0) return null;
	const s = Math.abs(b) * len; // sagitta
	const r = (len * len) / (8 * s) + s / 2;
	const side = Math.sign(b);
	const bulgeX = (dy / len) * side; // unit vector from chord toward the bulge
	const bulgeY = (-dx / len) * side;
	const cx = (fx + tx) / 2 - bulgeX * (r - s);
	const cy = (fy + ty) / 2 - bulgeY * (r - s);
	const a0 = Math.atan2(fy - cy, fx - cx);
	const a1 = Math.atan2(ty - cy, tx - cx);
	// Positive bend traverses in increasing-angle direction (sweep 1), so its
	// span is in (0, 2π); negative bend mirrors to (-2π, 0).
	let delta = a1 - a0;
	if (b > 0 && delta <= 0) delta += TWO_PI;
	if (b < 0 && delta >= 0) delta -= TWO_PI;
	return { cx, cy, r, a0, delta };
}

/** The point at parameter t ∈ [0, 1] along a shape. */
export function pointAt(shape: PathShape, t: number): Point {
	const u = clamp01(t);
	// A polyline has waypoints, not from/to: delegate to its segment chain
	// (arc-length-distributed t, so travel speed is uniform across segments).
	if (shape.kind === 'polyline') return pointAtMulti(polylineSegments(shape), u);
	const from = finitePoint(shape.from);
	const to = finitePoint(shape.to);
	switch (shape.kind) {
		case 'line': {
			const [x, y] = lerpPoint(from, to, u);
			return [round(x), round(y)];
		}
		case 'quadratic': {
			const c = finitePoint(shape.c1);
			const v = 1 - u;
			return [
				round(v * v * from[0] + 2 * v * u * c[0] + u * u * to[0]),
				round(v * v * from[1] + 2 * v * u * c[1] + u * u * to[1])
			];
		}
		case 'cubic': {
			const c1 = finitePoint(shape.c1);
			const c2 = finitePoint(shape.c2);
			const v = 1 - u;
			return [
				round(v * v * v * from[0] + 3 * v * v * u * c1[0] + 3 * v * u * u * c2[0] + u * u * u * to[0]),
				round(v * v * v * from[1] + 3 * v * v * u * c1[1] + 3 * v * u * u * c2[1] + u * u * u * to[1])
			];
		}
		case 'arc': {
			const g = arcGeometry(from, to, shape.bend);
			if (!g) {
				const [x, y] = lerpPoint(from, to, u);
				return [round(x), round(y)];
			}
			const a = g.a0 + g.delta * u;
			return [round(g.cx + Math.cos(a) * g.r), round(g.cy + Math.sin(a) * g.r)];
		}
	}
}

/** The raw (unrounded) tangent vector at t, before degeneracy fallbacks. */
function tangentAt(shape: PathShape, u: number): [number, number] {
	// Handled directly in angleAt (delegated to the segment chain), like arc.
	if (shape.kind === 'polyline') return [0, 0];
	const from = finitePoint(shape.from);
	const to = finitePoint(shape.to);
	switch (shape.kind) {
		case 'line':
			return [to[0] - from[0], to[1] - from[1]];
		case 'quadratic': {
			const c = finitePoint(shape.c1);
			const v = 1 - u;
			return [
				2 * v * (c[0] - from[0]) + 2 * u * (to[0] - c[0]),
				2 * v * (c[1] - from[1]) + 2 * u * (to[1] - c[1])
			];
		}
		case 'cubic': {
			const c1 = finitePoint(shape.c1);
			const c2 = finitePoint(shape.c2);
			const v = 1 - u;
			return [
				3 * v * v * (c1[0] - from[0]) + 6 * v * u * (c2[0] - c1[0]) + 3 * u * u * (to[0] - c2[0]),
				3 * v * v * (c1[1] - from[1]) + 6 * v * u * (c2[1] - c1[1]) + 3 * u * u * (to[1] - c2[1])
			];
		}
		case 'arc':
			return [0, 0]; // handled directly in angleAt (exact from the circle)
	}
}

/** The tangent angle (radians) at parameter t ∈ [0, 1] along a shape.
 *  Degenerate tangents (a control point sitting on an endpoint, zero-length
 *  shapes) fall back to a finite-difference sample, then to the chord angle
 *  — never NaN. */
export function angleAt(shape: PathShape, t: number): number {
	const u = clamp01(t);
	// Delegate to the segment chain: within a segment the tangent is exact; AT
	// a straight corner it snaps to the next segment's heading (no continuous
	// tangent exists there — `smooth` is the fix, not fancier sampling).
	if (shape.kind === 'polyline') return angleAtMulti(polylineSegments(shape), u);
	if (shape.kind === 'arc') {
		const g = arcGeometry(shape.from, shape.to, shape.bend);
		if (g) {
			const a = g.a0 + g.delta * u;
			// Tangent is perpendicular to the radius, in the direction of travel.
			return a + (g.delta > 0 ? Math.PI / 2 : -Math.PI / 2);
		}
		return segmentAngle(shape.from, shape.to);
	}
	const [dx, dy] = tangentAt(shape, u);
	if (Math.hypot(dx, dy) > 1e-9) return Math.atan2(dy, dx);
	// Degenerate derivative: sample a small step around t.
	const before = pointAt(shape, Math.max(0, u - 0.01));
	const after = pointAt(shape, Math.min(1, u + 0.01));
	if (Math.hypot(after[0] - before[0], after[1] - before[1]) > 1e-9) {
		return Math.atan2(after[1] - before[1], after[0] - before[0]);
	}
	return segmentAngle(shape.from, shape.to);
}

/** The same shape traversed the other way (from ↔ to). Used to shorten a
 *  shape at its START: reverse, shorten the tail, reverse back. Kind-
 *  preserving, so a SegmentShape in is a SegmentShape out (the overload). */
export function reverseShape(shape: SegmentShape): SegmentShape;
export function reverseShape(shape: PathShape): PathShape;
export function reverseShape(shape: PathShape): PathShape {
	switch (shape.kind) {
		case 'line':
			return { kind: 'line', from: shape.to, to: shape.from };
		case 'quadratic':
			return { kind: 'quadratic', from: shape.to, to: shape.from, c1: shape.c1 };
		case 'cubic':
			return { kind: 'cubic', from: shape.to, to: shape.from, c1: shape.c2, c2: shape.c1 };
		case 'arc':
			// Same physical arc, opposite travel direction: the bulge sits on the
			// other side RELATIVE to the new direction, so the sign flips.
			return { kind: 'arc', from: shape.to, to: shape.from, bend: -shape.bend };
		case 'polyline':
			// Same waypoints walked backwards; smooth/close are direction-blind
			// (Catmull-Rom through reversed points mirrors the original curve).
			return { ...shape, points: [...shape.points].reverse() };
	}
}

/** Trim ~`by` px off the TAIL of a shape, returning a shape of the same kind
 *  that follows the original geometry (exact de Casteljau subdivision for
 *  curves, exact angular trim for arcs; the px→parameter conversion uses the
 *  end-tangent speed, a first-order approximation that is plenty for
 *  arrowhead-sized trims). `by` ≤ 0 returns the shape unchanged; `by` beyond
 *  the whole shape collapses it to its start. Kind-preserving, so a
 *  SegmentShape in is a SegmentShape out (the overload). */
export function shortenShape(shape: SegmentShape, by: number): SegmentShape;
export function shortenShape(shape: PathShape, by: number): PathShape;
export function shortenShape(shape: PathShape, by: number): PathShape {
	const amount = finite(by);
	if (amount <= 0) return shape;
	switch (shape.kind) {
		case 'line':
			return { kind: 'line', from: shape.from, to: shorten(shape.from, shape.to, amount) };
		case 'quadratic': {
			const t = trimParameter(shape, amount);
			const from = finitePoint(shape.from);
			const c = finitePoint(shape.c1);
			return {
				kind: 'quadratic',
				from: shape.from,
				c1: roundPoint(lerpPoint(from, c, t)),
				to: pointAt(shape, t)
			};
		}
		case 'cubic': {
			const t = trimParameter(shape, amount);
			const from = finitePoint(shape.from);
			const c1 = finitePoint(shape.c1);
			const c2 = finitePoint(shape.c2);
			const a = lerpPoint(from, c1, t);
			const b = lerpPoint(c1, c2, t);
			const d = lerpPoint(a, b, t);
			return {
				kind: 'cubic',
				from: shape.from,
				c1: roundPoint(a),
				c2: roundPoint(d),
				to: pointAt(shape, t)
			};
		}
		case 'arc': {
			const g = arcGeometry(shape.from, shape.to, shape.bend);
			if (!g) {
				return { kind: 'arc', from: shape.from, to: shorten(shape.from, shape.to, amount), bend: 0 };
			}
			const arcLength = g.r * Math.abs(g.delta);
			const t = arcLength === 0 ? 0 : Math.max(0, 1 - amount / arcLength);
			const span = Math.abs(g.delta) * t;
			const chord = 2 * g.r * Math.sin(span / 2);
			const sagitta = g.r * (1 - Math.cos(span / 2));
			const bend = chord === 0 ? 0 : clampBend(Math.sign(shape.bend) * (sagitta / chord));
			return { kind: 'arc', from: shape.from, to: pointAt(shape, t), bend };
		}
		case 'polyline': {
			// Walk back from the tail, dropping whole segments the trim swallows,
			// then pull the last point along its segment. Chord lengths, so a
			// `smooth` trim is first-order like trimParameter — plenty for
			// arrowhead-sized trims. A closed loop has no tail: unchanged.
			if (shape.close) return shape;
			const pts = shape.points.map(finitePoint);
			let remaining = amount;
			while (pts.length >= 2) {
				const a = pts[pts.length - 2];
				const b = pts[pts.length - 1];
				const len = Math.hypot(b[0] - a[0], b[1] - a[1]);
				if (remaining < len) {
					pts[pts.length - 1] = shorten(a, b, remaining);
					break;
				}
				remaining -= len;
				pts.pop();
			}
			return { ...shape, points: pts };
		}
	}
}

function roundPoint(p: Point): Point {
	return [round(p[0]), round(p[1])];
}

/** The parameter that sits ~`by` px back from the end of a curve, using the
 *  end-tangent speed as the local px-per-parameter rate. (SegmentShape: a
 *  polyline trims point-wise in shortenShape, never through a parameter.) */
function trimParameter(shape: SegmentShape, by: number): number {
	const [dx, dy] = tangentAt(shape, 1);
	let speed = Math.hypot(dx, dy);
	if (speed < 1e-9) {
		// Degenerate end tangent: fall back to the chord as a length estimate.
		const from = finitePoint(shape.from);
		const to = finitePoint(shape.to);
		speed = Math.hypot(to[0] - from[0], to[1] - from[1]);
	}
	if (speed < 1e-9) return 0;
	return clamp01(1 - by / speed);
}

// ─── Multi-segment path (Phase 4) ───────────────────────────────────────────
// One continuous stroke chaining line/curve/arc segments — so a whole route
// is ONE <path> with one draw/drawDelay reveal, one arrowhead at the real end,
// and joins that meet (round linejoin) instead of butting stroke caps. All the
// per-segment math reuses the evaluators above, so the NaN-safety discipline is
// inherited for free: a half-typed segment is dropped, never emitted as NaNpx.

/** Coerce a possibly-malformed point to a safe finite one. */
function safePoint(p: Point | undefined): Point {
	return Array.isArray(p) ? finitePoint(p) : [0, 0];
}

/** Resolve a chained segment list into concrete PathShapes. Each segment's
 *  start defaults to the previous segment's `to` (or `start` for the first),
 *  so a path is authored as a start point plus a list of destinations; an
 *  explicit `from` lifts the pen for a disjoint sub-path. Kind is chosen by the
 *  control data present: `bend` → arc, else `c1` → curve (cubic when `c2` is
 *  set, else quadratic), else line. A malformed segment (no `to`) is dropped
 *  rather than throwing, so a mid-edit typo can't blow up the stroke. */
export function pathShapes(start: Point, segments: PathSegment[]): SegmentShape[] {
	if (!Array.isArray(segments)) return [];
	const shapes: SegmentShape[] = [];
	let cursor = safePoint(start);
	for (const seg of segments) {
		if (!seg || !Array.isArray(seg.to)) continue;
		const from = Array.isArray(seg.from) ? finitePoint(seg.from) : cursor;
		const to = finitePoint(seg.to);
		if (seg.bend != null) {
			shapes.push({ kind: 'arc', from, to, bend: clampBend(seg.bend) });
		} else if (seg.c1 != null) {
			const c1 = safePoint(seg.c1);
			if (seg.c2 != null) shapes.push({ kind: 'cubic', from, to, c1, c2: safePoint(seg.c2) });
			else shapes.push({ kind: 'quadratic', from, to, c1 });
		} else {
			shapes.push({ kind: 'line', from, to });
		}
		cursor = to;
	}
	return shapes;
}

/** The `d` string for a single PathShape, via the existing per-kind builders. */
function shapePath(shape: PathShape): string {
	switch (shape.kind) {
		case 'line':
			return linePath(shape.from, shape.to);
		case 'quadratic':
			return curvePath(shape.from, shape.to, shape.c1);
		case 'cubic':
			return curvePath(shape.from, shape.to, shape.c1, shape.c2);
		case 'arc':
			return arcPath(shape.from, shape.to, shape.bend);
		case 'polyline':
			return shape.smooth
				? smoothPath(shape.points, shape.close)
				: polylinePath(shape.points, shape.close);
	}
}

/** One `d` string for a chained shape list: each segment's builder joined,
 *  with the redundant leading `M` dropped wherever a segment starts exactly
 *  where the previous one ended (the pen is already there). A segment whose
 *  `from` differs from the previous `to` keeps its `M` — a genuine pen lift, so
 *  disjoint sub-paths render as gaps rather than a spurious connecting line. */
export function multiPath(shapes: PathShape[]): string {
	if (!Array.isArray(shapes) || shapes.length === 0) return '';
	let d = '';
	let prevTo: Point | null = null;
	// A polyline in the chain contributes its whole segment chain (never
	// recursive — the chain is only lines and cubics), so the join logic below
	// sees uniform from/to segments.
	const flat = shapes.flatMap((s) => (s.kind === 'polyline' ? polylineSegments(s) : [s]));
	for (const s of flat) {
		const from = finitePoint(s.from);
		const full = shapePath(s);
		if (prevTo && from[0] === prevTo[0] && from[1] === prevTo[1]) {
			d += ' ' + full.replace(/^M\s+\S+\s+\S+\s+/, '');
		} else {
			d += (d ? ' ' : '') + full;
		}
		prevTo = finitePoint(s.to);
	}
	return d;
}

/** Approximate arc length of one shape by chord summation (enough for label
 *  placement and global-t location). */
function shapeLength(shape: PathShape, samples = 24): number {
	const n = Math.max(1, Math.floor(finite(samples, 24)));
	let len = 0;
	let prev = pointAt(shape, 0);
	for (let k = 1; k <= n; k++) {
		const p = pointAt(shape, k / n);
		len += Math.hypot(p[0] - prev[0], p[1] - prev[1]);
		prev = p;
	}
	return len;
}

/** The segment (and local parameter) at global t ∈ [0, 1] across a chained
 *  shape list, distributed by cumulative arc length so t is roughly uniform
 *  along the whole stroke. Null for an empty list; a zero-length total (all
 *  degenerate) reports the last shape at t. */
function locateMulti(shapes: PathShape[], t: number): { shape: PathShape; u: number } | null {
	if (!Array.isArray(shapes) || shapes.length === 0) return null;
	const u = clamp01(t);
	const lens = shapes.map((s) => shapeLength(s));
	const total = lens.reduce((a, b) => a + b, 0);
	const lastShape = shapes[shapes.length - 1];
	if (total === 0) return { shape: lastShape, u };
	let target = u * total;
	for (let i = 0; i < shapes.length; i++) {
		if (target <= lens[i] || i === shapes.length - 1) {
			return { shape: shapes[i], u: lens[i] === 0 ? 0 : clamp01(target / lens[i]) };
		}
		target -= lens[i];
	}
	return { shape: lastShape, u: 1 };
}

/** The point at global t ∈ [0, 1] along a chained shape list (empty → [0, 0]). */
export function pointAtMulti(shapes: PathShape[], t: number): Point {
	const loc = locateMulti(shapes, t);
	return loc ? pointAt(loc.shape, loc.u) : [0, 0];
}

/** The tangent angle (radians) at global t along a chained shape list
 *  (empty → 0). */
export function angleAtMulti(shapes: PathShape[], t: number): number {
	const loc = locateMulti(shapes, t);
	return loc ? angleAt(loc.shape, loc.u) : 0;
}

/** Anchor for a chained path's visible label: the point at global `at`, offset
 *  `offset` px perpendicular to the local tangent (positive = to the LEFT of
 *  travel — screen-up on a left-to-right stroke). The multi-segment twin of
 *  labelPos. */
export function labelPosMulti(shapes: PathShape[], at = 0.5, offset = 20): Point {
	const [x, y] = pointAtMulti(shapes, at);
	const a = angleAtMulti(shapes, at);
	const o = finite(offset);
	return [round(x + Math.sin(a) * o), round(y - Math.cos(a) * o)];
}

/** Unwrap a sequence of angles (radians) so CONSECUTIVE values differ by at most
 *  π — adding/subtracting 2π multiples so a rotation keyframe track takes the
 *  SHORTEST path between stops instead of spinning the long way (or several full
 *  turns) when a raw angle jumps the atan2 branch cut or, for an arc, comes back
 *  un-normalized (its tangent is `a0 + delta ± π/2`, which can exceed 2π). The
 *  first element is normalized to (-π, π]; each later one is shifted to sit
 *  within π of its predecessor. Without this an arrowhead riding a Path's end
 *  tangent whirls a full turn between keyframes. */
export function unwrapAngles(angles: number[]): number[] {
	if (!Array.isArray(angles) || angles.length === 0) return [];
	const norm = (a: number) => {
		let v = finite(a);
		while (v > Math.PI) v -= TWO_PI;
		while (v <= -Math.PI) v += TWO_PI;
		return v;
	};
	const out = [norm(angles[0])];
	for (let i = 1; i < angles.length; i++) {
		let a = finite(angles[i]);
		const prev = out[i - 1];
		while (a - prev > Math.PI) a -= TWO_PI;
		while (a - prev <= -Math.PI) a += TWO_PI;
		out.push(a);
	}
	return out;
}

/** The whole chained path sampled into a fixed-count polyline `d` (M + `segments`
 *  L's), for ANIMATING a multi-segment Path. A keyframe morph tweens `d: path()`
 *  only when every keyframe's `d` shares one command structure — but a Path's
 *  segment kinds (and even count) can differ between keyframes, and arc flags
 *  don't interpolate at all. Sampling the whole chain to the SAME number of
 *  straight segments at every keyframe sidesteps both: constant-count polylines
 *  morph smoothly. (The multi-segment twin of `samplePath`; the static render
 *  still uses the exact `multiPath`.) Empty chain → '' */
export function sampleMultiPath(shapes: PathShape[], segments = 96): string {
	if (!Array.isArray(shapes) || shapes.length === 0) return '';
	const n = Math.max(1, Math.floor(finite(segments, 96)));
	const p0 = pointAtMulti(shapes, 0);
	let d = `M ${round(p0[0])} ${round(p0[1])}`;
	for (let k = 1; k <= n; k++) {
		const p = pointAtMulti(shapes, k / n);
		d += ` L ${round(p[0])} ${round(p[1])}`;
	}
	return d;
}
