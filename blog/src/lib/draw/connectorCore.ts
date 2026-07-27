// Pure geometry for <Connector> — auto-routing an arrow between two boxes.
// No component imports, no DOM, no stores: everything here is independently
// unit-testable (tests/connectorCore.test.ts), the same discipline drawCore.ts
// follows for the shapes.
//
// Everything is NaN-safe (finite()/round() from drawCore) and degenerate-safe:
// zero-size boxes, coincident centers and boxes shorter than the arrowhead all
// produce a drawable path rather than `NaNpx`.

import { curvePath, finite, finitePoint, round, segmentAngle, shorten } from './drawCore';
import type { Point } from './types';

export type { Point };

/** A named anchor's box in canvas px — structurally a Block's geometry. */
export interface Rect {
	x: number;
	y: number;
	width: number;
	height: number;
}

export type Side = 'top' | 'right' | 'bottom' | 'left';
/** A side, or 'auto' to let the router pick the one facing the other box. */
export type SideOpt = Side | 'auto';
/** straight = shortest line, ortho = right-angled elbow, curve = S-bend. */
export type Route = 'straight' | 'ortho' | 'curve';

const NORMALS: Record<Side, Point> = {
	top: [0, -1],
	right: [1, 0],
	bottom: [0, 1],
	left: [-1, 0]
};

const OPPOSITE: Record<Side, Side> = {
	top: 'bottom',
	right: 'left',
	bottom: 'top',
	left: 'right'
};

/** Outward unit normal of a side. */
export function sideNormal(side: Side): Point {
	return NORMALS[side];
}

export function oppositeSide(side: Side): Side {
	return OPPOSITE[side];
}

/** Is this side on the horizontal axis (left/right) rather than vertical? */
export function isHorizontal(side: Side): boolean {
	return side === 'left' || side === 'right';
}

/** Normalize a possibly-garbage Rect. A point anchor is a zero-size Rect. */
function safeRect(r: Rect): Rect {
	return {
		x: finite(r.x),
		y: finite(r.y),
		width: Math.max(0, finite(r.width)),
		height: Math.max(0, finite(r.height))
	};
}

/** A point anchor, expressed as the zero-size Rect the router understands. */
export function pointRect(p: Point): Rect {
	const [x, y] = finitePoint(p);
	return { x, y, width: 0, height: 0 };
}

export function rectCenter(r: Rect): Point {
	const s = safeRect(r);
	return [round(s.x + s.width / 2), round(s.y + s.height / 2)];
}

/** The midpoint of one edge, pushed `gap` px straight out along its normal. */
export function sideCenter(r: Rect, side: Side, gap = 0): Point {
	const s = safeRect(r);
	const [cx, cy] = rectCenter(s);
	const g = finite(gap);
	switch (side) {
		case 'top':
			return [cx, round(s.y - g)];
		case 'bottom':
			return [cx, round(s.y + s.height + g)];
		case 'left':
			return [round(s.x - g), cy];
		default:
			return [round(s.x + s.width + g), cy];
	}
}

/** Which side of `r` the ray from its center toward `toward` actually crosses —
 *  i.e. the side `borderPoint` would land on. That means comparing the
 *  direction against the box's own DIAGONAL (|dx|·hh vs |dy|·hw), not against
 *  the raw axes: a long flat box is crossed top/bottom by all but the shallowest
 *  directions, even ones where |dx| > |dy|. Keeping the two functions in
 *  agreement is what lets `straight` (border hits) and `ortho`/`curve` (side
 *  centers) leave a box by the same edge. A zero-size box (a point anchor) has
 *  no diagonal, so it falls back to the raw dominant axis. */
export function facingSide(r: Rect, toward: Point): Side {
	const s = safeRect(r);
	const [cx, cy] = rectCenter(s);
	const [tx, ty] = finitePoint(toward);
	const dx = tx - cx;
	const dy = ty - cy;
	if (dx === 0 && dy === 0) return 'right';
	const hw = s.width / 2;
	const hh = s.height / 2;
	// Degenerate box: no aspect to weigh by, so compare the raw components.
	const horizontal = hw === 0 && hh === 0
		? Math.abs(dx) >= Math.abs(dy)
		: Math.abs(dx) * hh >= Math.abs(dy) * hw;
	if (horizontal) return dx >= 0 ? 'right' : 'left';
	return dy >= 0 ? 'bottom' : 'top';
}

/** Where the ray from `r`'s center toward `toward` crosses `r`'s border,
 *  pushed a further `gap` px along the same direction. This is what makes a
 *  straight connector attach to the box edge at whatever angle it arrives —
 *  no side snapping. Coincident center/target returns the center. */
export function borderPoint(r: Rect, toward: Point, gap = 0): Point {
	const s = safeRect(r);
	const c = rectCenter(s);
	const [tx, ty] = finitePoint(toward);
	const dx = tx - c[0];
	const dy = ty - c[1];
	if (dx === 0 && dy === 0) return c;
	const hw = s.width / 2;
	const hh = s.height / 2;
	// Per-axis exit parameter; a zero component never binds (Infinity).
	const tX = dx === 0 ? Infinity : hw / Math.abs(dx);
	const tY = dy === 0 ? Infinity : hh / Math.abs(dy);
	const t = Math.min(tX, tY);
	const len = Math.hypot(dx, dy);
	const k = t + finite(gap) / len;
	return [round(c[0] + dx * k), round(c[1] + dy * k)];
}

/** Drop consecutive duplicate points (an elbow can collapse onto an endpoint
 *  when the boxes line up). Keeps at least the two endpoints. */
export function dedupePoints(points: Point[]): Point[] {
	const out: Point[] = [];
	for (const p of points) {
		const last = out[out.length - 1];
		if (!last || last[0] !== p[0] || last[1] !== p[1]) out.push(p);
	}
	return out.length >= 2 ? out : points.slice(0, 2);
}

/** The right-angled waypoints from `p1` (leaving `fs`) to `p2` (entering `ts`).
 *  Same-axis sides get a two-corner elbow across the midline between them;
 *  perpendicular sides get one corner where the two runs meet. */
export function orthoPoints(p1: Point, p2: Point, fs: Side, ts: Side): Point[] {
	const [ax, ay] = finitePoint(p1);
	const [bx, by] = finitePoint(p2);
	const fh = isHorizontal(fs);
	const th = isHorizontal(ts);
	if (fh && th) {
		const mx = round((ax + bx) / 2);
		return dedupePoints([[ax, ay], [mx, ay], [mx, by], [bx, by]]);
	}
	if (!fh && !th) {
		const my = round((ay + by) / 2);
		return dedupePoints([[ax, ay], [ax, my], [bx, my], [bx, by]]);
	}
	// Mixed: the corner sits where the horizontal run meets the vertical one.
	const corner: Point = fh ? [bx, ay] : [ax, by];
	return dedupePoints([[ax, ay], corner, [bx, by]]);
}

/** A polyline `d` with the interior corners rounded off by up to `radius` px.
 *  Each corner is cut back along both of its legs by the same amount — never
 *  more than half the shorter leg, so adjacent corners can't overrun each
 *  other — and bridged with a quadratic whose control point is the corner. */
export function roundedPolylinePath(points: Point[], radius = 0): string {
	const pts = points.map(finitePoint);
	if (pts.length < 2) return '';
	const r = Math.max(0, finite(radius));
	if (r === 0 || pts.length === 2) {
		return (
			`M ${round(pts[0][0])} ${round(pts[0][1])} ` +
			pts.slice(1).map(([x, y]) => `L ${round(x)} ${round(y)}`).join(' ')
		);
	}

	const along = (from: Point, to: Point, by: number): Point => {
		const dx = to[0] - from[0];
		const dy = to[1] - from[1];
		const len = Math.hypot(dx, dy);
		if (len === 0) return [from[0], from[1]];
		const t = Math.min(by / len, 1);
		return [round(from[0] + dx * t), round(from[1] + dy * t)];
	};
	const dist = (a: Point, b: Point) => Math.hypot(b[0] - a[0], b[1] - a[1]);

	let d = `M ${round(pts[0][0])} ${round(pts[0][1])}`;
	for (let i = 1; i < pts.length - 1; i++) {
		const prev = pts[i - 1];
		const corner = pts[i];
		const next = pts[i + 1];
		// Half of each leg is the hard limit: two neighbouring corners then meet
		// at most at the leg's midpoint instead of crossing over.
		const cut = Math.min(r, dist(prev, corner) / 2, dist(corner, next) / 2);
		if (cut <= 0) {
			d += ` L ${round(corner[0])} ${round(corner[1])}`;
			continue;
		}
		const enter = along(corner, prev, cut);
		const exit = along(corner, next, cut);
		d += ` L ${round(enter[0])} ${round(enter[1])}`;
		d += ` Q ${round(corner[0])} ${round(corner[1])} ${round(exit[0])} ${round(exit[1])}`;
	}
	const last = pts[pts.length - 1];
	return `${d} L ${round(last[0])} ${round(last[1])}`;
}

/** Total length of a polyline. */
function polylineLength(points: Point[]): number {
	let total = 0;
	for (let i = 1; i < points.length; i++) {
		total += Math.hypot(points[i][0] - points[i - 1][0], points[i][1] - points[i - 1][1]);
	}
	return total;
}

/** The point at fraction `t` (0–1) of a polyline's arc length, plus the
 *  direction of travel there. Corners are sharp, so `t` landing exactly on a
 *  vertex takes the outgoing segment's angle. */
export function polylineAt(points: Point[], t: number): { point: Point; angle: number } {
	const pts = points.map(finitePoint);
	if (pts.length < 2) return { point: pts[0] ?? [0, 0], angle: 0 };
	const total = polylineLength(pts);
	if (total === 0) return { point: pts[0], angle: 0 };
	let remaining = Math.max(0, Math.min(1, finite(t, 0.5))) * total;
	for (let i = 1; i < pts.length; i++) {
		const a = pts[i - 1];
		const b = pts[i];
		const seg = Math.hypot(b[0] - a[0], b[1] - a[1]);
		if (seg === 0) continue;
		if (remaining <= seg || i === pts.length - 1) {
			const f = Math.min(remaining / seg, 1);
			return {
				point: [round(a[0] + (b[0] - a[0]) * f), round(a[1] + (b[1] - a[1]) * f)],
				angle: segmentAngle(a, b)
			};
		}
		remaining -= seg;
	}
	return { point: pts[pts.length - 1], angle: 0 };
}

/** A cubic Bézier's point and tangent angle at parameter `t`. */
export function cubicAt(p0: Point, c1: Point, c2: Point, p1: Point, t: number): { point: Point; angle: number } {
	const u = Math.max(0, Math.min(1, finite(t, 0.5)));
	const v = 1 - u;
	const at = (i: 0 | 1) =>
		v * v * v * p0[i] + 3 * v * v * u * c1[i] + 3 * v * u * u * c2[i] + u * u * u * p1[i];
	const dAt = (i: 0 | 1) =>
		3 * v * v * (c1[i] - p0[i]) + 6 * v * u * (c2[i] - c1[i]) + 3 * u * u * (p1[i] - c2[i]);
	const dx = dAt(0);
	const dy = dAt(1);
	return {
		point: [round(at(0)), round(at(1))],
		// A degenerate tangent (coincident control points) falls back to the chord.
		angle: dx === 0 && dy === 0 ? segmentAngle(p0, p1) : Math.atan2(dy, dx)
	};
}

/** Offset a point `by` px perpendicular to `angle`. Positive is to the LEFT of
 *  the direction of travel — the same sign convention as drawCore.labelPos. */
export function perpendicular(point: Point, angle: number, by: number): Point {
	const o = finite(by);
	return [round(point[0] + Math.sin(angle) * o), round(point[1] - Math.cos(angle) * o)];
}

export interface ConnectorOptions {
	route?: Route;
	/** Px of clearance between a box's edge and the shaft's endpoint. */
	gap?: number;
	fromSide?: SideOpt;
	toSide?: SideOpt;
	/** Corner radius for `ortho` elbows. Ignored by the other routes. */
	radius?: number;
	/** Arrowhead length; the shaft is pulled back by this much behind a head. */
	arrowSize?: number;
	arrowStart?: boolean;
	arrowEnd?: boolean;
	/** Where along the shaft the label sits (0–1) and how far off it (px). */
	labelAt?: number;
	labelOffset?: number;
}

export interface ConnectorGeometry {
	/** The shaft `d`, already pulled back behind whichever heads are present. */
	d: string;
	/** Arrow tips — the true endpoints, on the box edges. */
	start: Point;
	end: Point;
	/** Direction each head points, in radians (outward, toward its tip). */
	startAngle: number;
	endAngle: number;
	/** Anchor for the visible label, already offset off the shaft. */
	label: Point;
	/** Which side each end leaves/enters. Straight routes report the side the
	 *  attachment point landed on, so callers can reason about it. */
	fromSide: Side;
	toSide: Side;
}

/** Route one connector between two boxes. This is the whole component's brain:
 *  everything Connector.svelte does is feed props in and render the result. */
export function connectorGeometry(a: Rect, b: Rect, opts: ConnectorOptions = {}): ConnectorGeometry {
	const route: Route = opts.route ?? 'straight';
	const gap = finite(opts.gap ?? 0);
	const radius = Math.max(0, finite(opts.radius ?? 0));
	const size = Math.max(0, finite(opts.arrowSize ?? 0));
	const fromOpt: SideOpt = opts.fromSide ?? 'auto';
	const toOpt: SideOpt = opts.toSide ?? 'auto';
	const labelAt = opts.labelAt ?? 0.5;
	const labelOffset = opts.labelOffset ?? 20;

	const ra = safeRect(a);
	const rb = safeRect(b);

	let start: Point;
	let end: Point;
	let fs: Side;
	let ts: Side;
	let points: Point[] | null = null;
	let c1: Point | null = null;
	let c2: Point | null = null;

	if (route === 'straight') {
		// Aim A at B's forced attachment point if there is one, else at its center;
		// then aim B back at wherever A actually landed. Two passes, so an explicit
		// side on one end still steers the other end's border hit.
		const targetForA = toOpt === 'auto' ? rectCenter(rb) : sideCenter(rb, toOpt, gap);
		start = fromOpt === 'auto' ? borderPoint(ra, targetForA, gap) : sideCenter(ra, fromOpt, gap);
		end = toOpt === 'auto' ? borderPoint(rb, start, gap) : sideCenter(rb, toOpt, gap);
		fs = fromOpt === 'auto' ? facingSide(ra, end) : fromOpt;
		ts = toOpt === 'auto' ? facingSide(rb, start) : toOpt;
		points = [start, end];
	} else {
		fs = fromOpt === 'auto' ? facingSide(ra, rectCenter(rb)) : fromOpt;
		ts = toOpt === 'auto' ? facingSide(rb, rectCenter(ra)) : toOpt;
		start = sideCenter(ra, fs, gap);
		end = sideCenter(rb, ts, gap);
		if (route === 'ortho') {
			points = orthoPoints(start, end, fs, ts);
		} else {
			// Curve: pull each control point straight out of its own side, by a
			// fraction of the span. The floor keeps short hops from going limp.
			const span = Math.hypot(end[0] - start[0], end[1] - start[1]);
			const k = Math.max(40, span / 2.5);
			const na = sideNormal(fs);
			const nb = sideNormal(ts);
			c1 = [round(start[0] + na[0] * k), round(start[1] + na[1] * k)];
			c2 = [round(end[0] + nb[0] * k), round(end[1] + nb[1] * k)];
		}
	}

	// Head directions come from the shaft's own tangent at each tip.
	let startAngle: number;
	let endAngle: number;
	let label: Point;

	if (points) {
		const shaft = points.map((p) => [...p] as Point);
		endAngle = segmentAngle(shaft[shaft.length - 2], shaft[shaft.length - 1]);
		startAngle = segmentAngle(shaft[1], shaft[0]);
		// Pull the shaft back behind each head so no stroke pokes past a tip.
		if (opts.arrowEnd && size > 0) {
			shaft[shaft.length - 1] = shorten(shaft[shaft.length - 2], shaft[shaft.length - 1], size);
		}
		if (opts.arrowStart && size > 0) {
			shaft[0] = shorten(shaft[1], shaft[0], size);
		}
		const here = polylineAt(points, labelAt);
		label = perpendicular(here.point, here.angle, labelOffset);
		return {
			d: roundedPolylinePath(dedupePoints(shaft), route === 'ortho' ? radius : 0),
			start,
			end,
			startAngle,
			endAngle,
			label,
			fromSide: fs,
			toSide: ts
		};
	}

	// Curve. The end tangents are fixed by the control points, so pulling a tip
	// back along its own tangent shortens the shaft without bending it.
	const cc1 = c1 as Point;
	const cc2 = c2 as Point;
	endAngle = segmentAngle(cc2, end);
	startAngle = segmentAngle(cc1, start);
	const shaftEnd = opts.arrowEnd && size > 0 ? shorten(cc2, end, size) : end;
	const shaftStart = opts.arrowStart && size > 0 ? shorten(cc1, start, size) : start;
	const here = cubicAt(start, cc1, cc2, end, labelAt);
	label = perpendicular(here.point, here.angle, labelOffset);
	return {
		d: curvePath(shaftStart, shaftEnd, cc1, cc2),
		start,
		end,
		startAngle,
		endAngle,
		label,
		fromSide: fs,
		toSide: ts
	};
}
