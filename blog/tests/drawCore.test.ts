import { describe, expect, it } from 'vitest';
import {
	angleAt,
	arcPath,
	arrowHead,
	bendFromApex,
	clampBend,
	curvePath,
	defaultArrowSize,
	finite,
	finitePoint,
	labelPos,
	labelPosMulti,
	linePath,
	multiPath,
	pathShapes,
	pointAt,
	pointAtMulti,
	angleAtMulti,
	sampleMultiPath,
	unwrapAngles,
	polygonPoints,
	polylinePath,
	polylineSegments,
	smoothPath,
	smoothSegments,
	reverseShape,
	round,
	segmentAngle,
	shorten,
	shortenShape,
	snapToAngles,
	uniformLengthParams
} from '../src/lib/draw/drawCore';
import type { PathSegment, PathShape, Point } from '../src/lib/draw/types';

/** Angles compared on the unit circle, so 3π/2 ≡ -π/2. */
function expectAngle(actual: number, expected: number) {
	expect(Math.cos(actual)).toBeCloseTo(Math.cos(expected), 6);
	expect(Math.sin(actual)).toBeCloseTo(Math.sin(expected), 6);
}

function dist(a: Point, b: Point): number {
	return Math.hypot(a[0] - b[0], a[1] - b[1]);
}

describe('finite / finitePoint / round', () => {
	it('passes finite numbers through', () => {
		expect(finite(42)).toBe(42);
		expect(finite(-0.5)).toBe(-0.5);
	});

	it('coerces NaN and infinities to the fallback', () => {
		expect(finite(NaN)).toBe(0);
		expect(finite(Infinity)).toBe(0);
		expect(finite(-Infinity)).toBe(0);
		expect(finite(NaN, 4)).toBe(4);
	});

	it('finitePoint sanitizes both coordinates', () => {
		expect(finitePoint([NaN, 7])).toEqual([0, 7]);
		expect(finitePoint([3, Infinity])).toEqual([3, 0]);
	});

	it('round keeps 2 decimals and never emits NaN', () => {
		expect(round(1.2345)).toBe(1.23);
		expect(round(-1.005)).toBeCloseTo(-1, 2);
		expect(round(NaN)).toBe(0);
	});
});

describe('segmentAngle', () => {
	it('measures the four cardinal directions', () => {
		expect(segmentAngle([0, 0], [10, 0])).toBe(0);
		expect(segmentAngle([0, 0], [0, 10])).toBeCloseTo(Math.PI / 2); // SVG y grows down
		expect(segmentAngle([0, 0], [-10, 0])).toBeCloseTo(Math.PI);
		expect(segmentAngle([0, 0], [0, -10])).toBeCloseTo(-Math.PI / 2);
	});

	it('handles diagonals and negative coordinates', () => {
		expect(segmentAngle([-10, -10], [0, 0])).toBeCloseTo(Math.PI / 4);
	});

	it('returns 0 (never NaN) for a zero-length segment', () => {
		expect(segmentAngle([5, 5], [5, 5])).toBe(0);
	});

	it('coerces non-finite inputs instead of propagating NaN', () => {
		expect(Number.isNaN(segmentAngle([NaN, 0], [10, 0]))).toBe(false);
	});
});

describe('shorten', () => {
	it('moves the endpoint back along the segment', () => {
		expect(shorten([0, 0], [10, 0], 4)).toEqual([6, 0]);
		expect(shorten([0, 0], [0, 10], 4)).toEqual([0, 6]);
	});

	it('works with negative coordinates', () => {
		expect(shorten([-10, 0], [-2, 0], 3)).toEqual([-5, 0]);
	});

	it('returns `to` unchanged for a zero-length segment', () => {
		expect(shorten([5, 5], [5, 5], 10)).toEqual([5, 5]);
	});

	it('clamps at `from` when `by` exceeds the segment length', () => {
		expect(shorten([2, 3], [12, 3], 999)).toEqual([2, 3]);
	});

	it('extends past `to` for negative `by`', () => {
		expect(shorten([0, 0], [10, 0], -5)).toEqual([15, 0]);
	});

	it('never emits NaN for non-finite inputs', () => {
		const [x, y] = shorten([NaN, 0], [10, Infinity], NaN);
		expect(Number.isFinite(x)).toBe(true);
		expect(Number.isFinite(y)).toBe(true);
	});
});

describe('arrowHead', () => {
	it('puts the tip first, exactly at the given point', () => {
		const [tip] = arrowHead([100, 50], 0, 20);
		expect(tip).toEqual([100, 50]);
	});

	it('builds a rightward 2:1 head: base `size` back, half-size to each side', () => {
		const [tip, a, b] = arrowHead([100, 0], 0, 20);
		expect(tip).toEqual([100, 0]);
		expect(a).toEqual([80, 10]);
		expect(b).toEqual([80, -10]);
	});

	it('rotates with the angle (pointing down)', () => {
		const [tip, a, b] = arrowHead([0, 100], Math.PI / 2, 20);
		expect(tip).toEqual([0, 100]);
		expect(a).toEqual([-10, 80]);
		expect(b).toEqual([10, 80]);
	});

	it('collapses to the tip for size 0', () => {
		expect(arrowHead([5, 5], 1, 0)).toEqual([
			[5, 5],
			[5, 5],
			[5, 5]
		]);
	});

	it('never emits NaN for non-finite inputs', () => {
		for (const [x, y] of arrowHead([NaN, 5], Infinity, NaN)) {
			expect(Number.isFinite(x)).toBe(true);
			expect(Number.isFinite(y)).toBe(true);
		}
	});
});

describe('defaultArrowSize', () => {
	it('scales with thickness', () => {
		expect(defaultArrowSize(6)).toBe(24);
		expect(defaultArrowSize(10)).toBe(40);
	});

	it('has a floor so thin lines still get a visible head', () => {
		expect(defaultArrowSize(1)).toBe(12);
	});

	it('falls back to the default thickness when non-finite', () => {
		expect(defaultArrowSize(NaN)).toBe(16);
	});
});

describe('linePath', () => {
	it('emits a simple M/L d string', () => {
		expect(linePath([100, 200], [900, 540])).toBe('M 100 200 L 900 540');
	});

	it('rounds long decimals', () => {
		expect(linePath([1.2345, 0], [2.9999, 0])).toBe('M 1.23 0 L 3 0');
	});

	it('never contains NaN', () => {
		expect(linePath([NaN, 1], [2, Infinity])).not.toContain('NaN');
	});
});

describe('curvePath', () => {
	it('quadratic with one control point, cubic with two', () => {
		expect(curvePath([0, 0], [100, 0], [50, 100])).toBe('M 0 0 Q 50 100 100 0');
		expect(curvePath([0, 0], [100, 0], [0, 100], [100, 100])).toBe(
			'M 0 0 C 0 100 100 100 100 0'
		);
	});

	it('never contains NaN', () => {
		expect(curvePath([NaN, 0], [1, Infinity], [NaN, NaN])).not.toContain('NaN');
	});
});

describe('arcPath', () => {
	it('bend 0 renders exactly the straight from→to line', () => {
		expect(arcPath([400, 540], [1500, 540], 0)).toBe('M 400 540 L 1500 540');
	});

	it('positive vs negative bend flips only the sweep flag (opposite sides)', () => {
		expect(arcPath([400, 540], [1500, 540], 0.3)).toBe(
			'M 400 540 A 623.33 623.33 0 0 1 1500 540'
		);
		expect(arcPath([400, 540], [1500, 540], -0.3)).toBe(
			'M 400 540 A 623.33 623.33 0 0 0 1500 540'
		);
	});

	it('|bend| > 0.5 sets the large-arc flag; beyond 1 it clamps to 1', () => {
		const atOne = arcPath([0, 0], [100, 0], 1);
		expect(atOne).toBe('M 0 0 A 62.5 62.5 0 1 1 100 0'); // r = L²/(8s) + s/2 = 12.5 + 50
		expect(arcPath([0, 0], [100, 0], 5)).toBe(atOne); // clamped
	});

	it('vertical chord: a semicircle to the (dy, -dx) side', () => {
		expect(arcPath([100, 100], [100, 300], 0.5)).toBe('M 100 100 A 100 100 0 0 1 100 300');
	});

	it('zero-length chord degenerates to a point line, never NaN', () => {
		expect(arcPath([5, 5], [5, 5], 0.4)).toBe('M 5 5 L 5 5');
		expect(arcPath([NaN, 0], [100, Infinity], NaN)).not.toContain('NaN');
	});
});

describe('pointAt / angleAt', () => {
	const line: PathShape = { kind: 'line', from: [0, 0], to: [100, 0] };
	const quad: PathShape = { kind: 'quadratic', from: [0, 0], to: [100, 0], c1: [50, 100] };
	const cubic: PathShape = { kind: 'cubic', from: [0, 0], to: [100, 0], c1: [0, 100], c2: [100, 100] };
	const arc: PathShape = { kind: 'arc', from: [400, 540], to: [1500, 540], bend: 0.3 };

	it('line: endpoints, midpoint, constant angle', () => {
		expect(pointAt(line, 0)).toEqual([0, 0]);
		expect(pointAt(line, 0.5)).toEqual([50, 0]);
		expect(pointAt(line, 1)).toEqual([100, 0]);
		expectAngle(angleAt(line, 0.5), 0);
	});

	it('quadratic: hand-computed point and tangents', () => {
		expect(pointAt(quad, 0)).toEqual([0, 0]);
		expect(pointAt(quad, 0.5)).toEqual([50, 50]); // 0.25·p0 + 0.5·c1 + 0.25·p1
		expect(pointAt(quad, 1)).toEqual([100, 0]);
		expectAngle(angleAt(quad, 0), Math.atan2(100, 50)); // toward c1
		expectAngle(angleAt(quad, 1), Math.atan2(-100, 50)); // away from c1
		expectAngle(angleAt(quad, 0.5), 0); // symmetric apex — horizontal
	});

	it('cubic: hand-computed point and tangents', () => {
		expect(pointAt(cubic, 0.5)).toEqual([50, 75]); // (p0 + 3c1 + 3c2 + p1) / 8
		expectAngle(angleAt(cubic, 0), Math.PI / 2); // straight toward c1 (down in SVG y)
		expectAngle(angleAt(cubic, 1), -Math.PI / 2); // from c2 to the end
		expectAngle(angleAt(cubic, 0.5), 0);
	});

	it('arc: apex at t=0.5, sagitta above the chord for positive bend', () => {
		expect(pointAt(arc, 0)).toEqual([400, 540]);
		expect(pointAt(arc, 1)).toEqual([1500, 540]);
		expect(pointAt(arc, 0.5)).toEqual([950, 210]); // 540 − 0.3·1100 (bulges screen-up)
		expectAngle(angleAt(arc, 0.5), 0); // travelling rightward over the top
	});

	it('arc: negative bend mirrors to the other side of the chord', () => {
		const down: PathShape = { kind: 'arc', from: [400, 540], to: [1500, 540], bend: -0.3 };
		expect(pointAt(down, 0.5)).toEqual([950, 870]); // 540 + 330
		expectAngle(angleAt(down, 0.5), 0);
	});

	it('arc: bend 0.5 is a semicircle', () => {
		const semi: PathShape = { kind: 'arc', from: [0, 0], to: [100, 0], bend: 0.5 };
		expect(pointAt(semi, 0.5)).toEqual([50, -50]); // r = 50, apex straight up
		expectAngle(angleAt(semi, 0), Math.PI / 2 + Math.PI); // leaving straight up... start tangent
	});

	it('arc: vertical chord', () => {
		const vert: PathShape = { kind: 'arc', from: [100, 100], to: [100, 300], bend: 0.5 };
		// chord points down (+y); positive bend bulges toward (dy,−dx)/L = (+1, 0)
		expect(pointAt(vert, 0.5)).toEqual([200, 200]);
	});

	it('arc: bend 0 and zero-length chords degenerate to the straight line', () => {
		const flat: PathShape = { kind: 'arc', from: [0, 0], to: [100, 0], bend: 0 };
		expect(pointAt(flat, 0.5)).toEqual([50, 0]);
		expectAngle(angleAt(flat, 0.5), 0);
		const dot: PathShape = { kind: 'arc', from: [5, 5], to: [5, 5], bend: 0.4 };
		expect(pointAt(dot, 0.5)).toEqual([5, 5]);
		expect(Number.isFinite(angleAt(dot, 0.5))).toBe(true);
	});

	it('t is clamped to [0, 1] and non-finite t is safe', () => {
		expect(pointAt(line, -3)).toEqual([0, 0]);
		expect(pointAt(line, 42)).toEqual([100, 0]);
		expect(pointAt(line, NaN)).toEqual([0, 0]);
	});

	it('degenerate control points never yield NaN angles', () => {
		const degenerate: PathShape = { kind: 'quadratic', from: [0, 0], to: [100, 0], c1: [0, 0] };
		expect(Number.isFinite(angleAt(degenerate, 0))).toBe(true);
		const point: PathShape = { kind: 'cubic', from: [5, 5], to: [5, 5], c1: [5, 5], c2: [5, 5] };
		expect(Number.isFinite(angleAt(point, 0.5))).toBe(true);
	});
});

describe('clampBend', () => {
	it('clamps |bend| to 1 and coerces non-finite to 0', () => {
		expect(clampBend(0.3)).toBe(0.3);
		expect(clampBend(5)).toBe(1);
		expect(clampBend(-5)).toBe(-1);
		expect(clampBend(NaN)).toBe(0);
	});
});

describe('reverseShape', () => {
	it('keeps every shape kind on its original geometry', () => {
		const quad: PathShape = { kind: 'quadratic', from: [0, 0], to: [100, 0], c1: [50, 100] };
		expect(pointAt(reverseShape(quad), 0.25)).toEqual(pointAt(quad, 0.75));
		const cubic: PathShape = { kind: 'cubic', from: [0, 0], to: [100, 0], c1: [0, 100], c2: [100, 100] };
		expect(pointAt(reverseShape(cubic), 0.5)).toEqual(pointAt(cubic, 0.5));
		const arc: PathShape = { kind: 'arc', from: [400, 540], to: [1500, 540], bend: 0.3 };
		expect(pointAt(reverseShape(arc), 0.5)).toEqual(pointAt(arc, 0.5)); // same apex
	});
});

describe('shortenShape', () => {
	it('line: same as shorten()', () => {
		const s = shortenShape({ kind: 'line', from: [0, 0], to: [100, 0] }, 20);
		expect(s).toEqual({ kind: 'line', from: [0, 0], to: [80, 0] });
	});

	it('quadratic/cubic: the new endpoint sits ~by px back, on the original curve', () => {
		const quad: PathShape = { kind: 'quadratic', from: [0, 0], to: [100, 0], c1: [50, 100] };
		const sq = shortenShape(quad, 10);
		expect(sq.kind).toBe('quadratic');
		expect(dist(pointAt(sq, 1), [100, 0])).toBeGreaterThan(7);
		expect(dist(pointAt(sq, 1), [100, 0])).toBeLessThan(13);
		const cubic: PathShape = { kind: 'cubic', from: [0, 0], to: [100, 0], c1: [0, 100], c2: [100, 100] };
		const sc = shortenShape(cubic, 10);
		// the trimmed tail must stay on the source curve (de Casteljau is exact):
		// end speed |3(to − c2)| = 300 px per unit t, so by=10 trims to t = 1 − 10/300
		expect(dist(pointAt(sc, 1), pointAt(cubic, 1 - 10 / 300))).toBeLessThan(0.05);
	});

	it('arc: exact angular trim — the sub-arc stays on the same circle', () => {
		const semi: PathShape = { kind: 'arc', from: [0, 0], to: [100, 0], bend: 0.5 };
		// arc length = π·50 ≈ 157.08; trim half of it → ends at the apex
		const half = shortenShape(semi, (Math.PI * 50) / 2);
		expect(half.kind).toBe('arc');
		expect(pointAt(half, 1)).toEqual([50, -50]);
		// the sub-arc's own midpoint must land on the original quarter point
		expect(dist(pointAt(half, 0.5), pointAt(semi, 0.25))).toBeLessThan(0.05);
	});

	it('by ≤ 0 returns the shape unchanged; huge by collapses to the start', () => {
		const quad: PathShape = { kind: 'quadratic', from: [0, 0], to: [100, 0], c1: [50, 100] };
		expect(shortenShape(quad, 0)).toBe(quad);
		expect(shortenShape(quad, -5)).toBe(quad);
		const collapsed = shortenShape({ kind: 'line', from: [0, 0], to: [100, 0] }, 9999);
		expect(pointAt(collapsed, 1)).toEqual([0, 0]);
	});

	it('never emits NaN for degenerate shapes', () => {
		const dot: PathShape = { kind: 'arc', from: [5, 5], to: [5, 5], bend: 0.3 };
		const s = shortenShape(dot, 10);
		expect(pointAt(s, 1).every(Number.isFinite)).toBe(true);
	});
});

describe('polylinePath', () => {
	it('joins the points with straight segments; close appends Z', () => {
		const pts: Point[] = [
			[100, 900],
			[400, 700],
			[700, 950]
		];
		expect(polylinePath(pts)).toBe('M 100 900 L 400 700 L 700 950');
		expect(polylinePath(pts, true)).toBe('M 100 900 L 400 700 L 700 950 Z');
	});

	it('fewer than 2 points render nothing; non-finite coords never leak', () => {
		expect(polylinePath([])).toBe('');
		expect(polylinePath([[5, 5]])).toBe('');
		expect(polylinePath([[NaN, 0], [1, Infinity]])).not.toContain('NaN');
	});
});

describe('smoothSegments / smoothPath', () => {
	const pts: Point[] = [
		[100, 900],
		[400, 700],
		[700, 950],
		[1100, 600]
	];

	it('passes exactly THROUGH every input point at segment boundaries', () => {
		const segments = smoothSegments(pts);
		expect(segments).toHaveLength(pts.length - 1);
		segments.forEach((seg, i) => {
			expect(pointAt(seg, 0)).toEqual(pts[i]);
			expect(pointAt(seg, 1)).toEqual(pts[i + 1]);
		});
	});

	it('2 points degenerate to a straight line', () => {
		expect(smoothPath([[0, 0], [100, 50]])).toBe('M 0 0 L 100 50');
	});

	it('collinear points stay collinear (control points on the line)', () => {
		const line: Point[] = [
			[0, 0],
			[50, 50],
			[100, 100],
			[150, 150]
		];
		for (const seg of smoothSegments(line)) {
			for (const t of [0.25, 0.5, 0.75]) {
				const [x, y] = pointAt(seg, t);
				expect(y).toBeCloseTo(x, 6); // still on y = x
			}
		}
	});

	it('close wraps the neighbors and appends Z', () => {
		const segments = smoothSegments(pts, true);
		expect(segments).toHaveLength(pts.length); // one extra seam segment
		expect(pointAt(segments[pts.length - 1], 0)).toEqual(pts[pts.length - 1]);
		expect(pointAt(segments[pts.length - 1], 1)).toEqual(pts[0]);
		expect(smoothPath(pts, true).endsWith('Z')).toBe(true);
	});

	it('handles empty/single/non-finite input safely', () => {
		expect(smoothPath([])).toBe('');
		expect(smoothPath([[5, 5]])).toBe('');
		expect(smoothPath([[NaN, 0], [1, 2], [Infinity, 4]])).not.toContain('NaN');
	});
});

describe('polyline PathShape (waypoints as a shape)', () => {
	// An L of two equal 100px legs: right, then down.
	const L: PathShape = { kind: 'polyline', points: [[0, 0], [100, 0], [100, 100]] };

	it('polylineSegments expands to straight lines (and the close seam)', () => {
		expect(polylineSegments({ points: [[0, 0], [100, 0], [100, 100]] })).toEqual([
			{ kind: 'line', from: [0, 0], to: [100, 0] },
			{ kind: 'line', from: [100, 0], to: [100, 100] }
		]);
		const closed = polylineSegments({ points: [[0, 0], [100, 0], [100, 100]], close: true });
		expect(closed).toHaveLength(3);
		expect(closed[2]).toEqual({ kind: 'line', from: [100, 100], to: [0, 0] });
	});

	it('polylineSegments smooth delegates to the Catmull-Rom cubics', () => {
		const pts: Point[] = [[0, 0], [100, 0], [100, 100]];
		expect(polylineSegments({ points: pts, smooth: true })).toEqual(smoothSegments(pts));
	});

	it('polylineSegments is total: fewer than 2 points → no segments', () => {
		expect(polylineSegments({ points: [] })).toEqual([]);
		expect(polylineSegments({ points: [[5, 5]] })).toEqual([]);
	});

	it('pointAt distributes t by arc length across the legs', () => {
		expect(pointAt(L, 0)).toEqual([0, 0]);
		expect(pointAt(L, 0.25)).toEqual([50, 0]);
		expect(pointAt(L, 0.5)).toEqual([100, 0]); // equal legs → the corner
		expect(pointAt(L, 0.75)).toEqual([100, 50]);
		expect(pointAt(L, 1)).toEqual([100, 100]);
	});

	it('pointAt on a closed polyline returns to the start at t=1', () => {
		const sq: PathShape = {
			kind: 'polyline',
			points: [[0, 0], [100, 0], [100, 100], [0, 100]],
			close: true
		};
		expect(pointAt(sq, 0)).toEqual([0, 0]);
		expect(pointAt(sq, 0.5)).toEqual([100, 100]); // halfway round the square
		expect(pointAt(sq, 1)).toEqual([0, 0]);
	});

	it('angleAt is the leg heading — it SNAPS at the corner, never blends', () => {
		expectAngle(angleAt(L, 0.25), 0); // heading right
		expectAngle(angleAt(L, 0.75), Math.PI / 2); // heading down (+y)
	});

	it('a smooth polyline still passes exactly THROUGH every waypoint', () => {
		const S: PathShape = { kind: 'polyline', points: [[0, 0], [100, 0], [100, 100]], smooth: true };
		expect(pointAt(S, 0)).toEqual([0, 0]);
		expect(pointAt(S, 1)).toEqual([100, 100]);
		// The middle waypoint is ON the curve: some sampled t passes through it.
		const min = Math.min(
			...Array.from({ length: 101 }, (_, i) => dist(pointAt(S, i / 100), [100, 0]))
		);
		expect(min).toBeLessThan(3);
	});

	it('reverseShape walks the same waypoints backwards', () => {
		expect(reverseShape(L)).toEqual({
			kind: 'polyline',
			points: [
				[100, 100],
				[100, 0],
				[0, 0]
			]
		});
	});

	it('shortenShape trims the tail leg point-wise', () => {
		expect(shortenShape(L, 40)).toEqual({
			kind: 'polyline',
			points: [
				[0, 0],
				[100, 0],
				[100, 60]
			]
		});
	});

	it('shortenShape drops whole legs the trim swallows', () => {
		// 130px eats the whole down leg, then 30px more off the first.
		expect(shortenShape(L, 130)).toEqual({
			kind: 'polyline',
			points: [
				[0, 0],
				[70, 0]
			]
		});
	});

	it('shortenShape leaves a closed loop untouched (no tail to trim)', () => {
		const sq: PathShape = { kind: 'polyline', points: [[0, 0], [100, 0], [100, 100]], close: true };
		expect(shortenShape(sq, 40)).toEqual(sq);
	});

	it('multiPath flattens a polyline into the chained d', () => {
		expect(multiPath([L])).toBe('M 0 0 L 100 0 L 100 100');
	});

	it('is total on junk: empty points evaluate safely', () => {
		const empty: PathShape = { kind: 'polyline', points: [] };
		expect(pointAt(empty, 0.5)).toEqual([0, 0]);
		expect(angleAt(empty, 0.5)).toBe(0);
	});
});

describe('bendFromApex', () => {
	it('round-trips with the forward math: pointAt(arc, 0.5) → the same bend', () => {
		for (const bend of [0.3, -0.3, 0.5, 0.75, -0.6]) {
			const arc: PathShape = { kind: 'arc', from: [400, 540], to: [1500, 540], bend };
			expect(bendFromApex([400, 540], [1500, 540], pointAt(arc, 0.5))).toBeCloseTo(bend, 3);
		}
	});

	it('round-trips on a vertical chord too', () => {
		const arc: PathShape = { kind: 'arc', from: [100, 100], to: [100, 300], bend: 0.5 };
		expect(bendFromApex([100, 100], [100, 300], pointAt(arc, 0.5))).toBeCloseTo(0.5, 3);
	});

	it('dragging across the chord flips the sign', () => {
		expect(bendFromApex([0, 0], [100, 0], [50, -30])).toBe(0.3); // above → positive
		expect(bendFromApex([0, 0], [100, 0], [50, 30])).toBe(-0.3); // below → negative
	});

	it('an apex on the chord means bend 0; off-perpendicular drags project', () => {
		expect(bendFromApex([0, 0], [100, 0], [50, 0])).toBe(0);
		expect(bendFromApex([0, 0], [100, 0], [80, -30])).toBe(0.3); // x is ignored
	});

	it('clamps to ±1 and survives degenerate/non-finite input', () => {
		expect(bendFromApex([0, 0], [100, 0], [50, -500])).toBe(1);
		expect(bendFromApex([5, 5], [5, 5], [50, 50])).toBe(0); // zero-length chord
		expect(Number.isFinite(bendFromApex([NaN, 0], [100, 0], [Infinity, -30]))).toBe(true);
	});
});

describe('snapToAngles', () => {
	it('snaps near-horizontal to horizontal (keeps x, pins y to the reference)', () => {
		expect(snapToAngles([100, 10], [0, 0])).toEqual([100, 0]);
		expect(snapToAngles([-100, -8], [0, 0])).toEqual([-100, 0]);
	});

	it('snaps near-vertical to vertical', () => {
		expect(snapToAngles([10, 100], [0, 0])).toEqual([0, 100]);
	});

	it('defaults to 90° detents — a near-diagonal drag locks to the dominant axis, not a diagonal', () => {
		// [60, 50] is past 45° toward horizontal → pure X (y pinned), no diagonal.
		expect(snapToAngles([60, 50], [0, 0])).toEqual([60, 0]);
		// A hair steeper than 45° → pure Y (x pinned).
		expect(snapToAngles([50, 60], [0, 0])).toEqual([0, 60]);
	});

	it('still offers 45° diagonals when a caller opts in with stepDeg=45', () => {
		const [x, y] = snapToAngles([60, 50], [0, 0], 45);
		expect(x).toBeCloseTo(55, 5);
		expect(y).toBeCloseTo(55, 5);
	});

	it('works relative to a non-origin reference', () => {
		expect(snapToAngles([210, 108], [100, 100])).toEqual([210, 100]);
	});

	it('coincident points and non-finite input are safe', () => {
		expect(snapToAngles([5, 5], [5, 5])).toEqual([5, 5]);
		expect(snapToAngles([NaN, 3], [0, Infinity]).every(Number.isFinite)).toBe(true);
	});
});

describe('labelPos', () => {
	it('line: perpendicular offset, positive is screen-up on a rightward line', () => {
		const line: PathShape = { kind: 'line', from: [0, 0], to: [100, 0] };
		expect(labelPos(line, 0.5, 20)).toEqual([50, -20]);
		expect(labelPos(line, 0.5, -20)).toEqual([50, 20]);
		expect(labelPos(line, 0.25, 10)).toEqual([25, -10]);
	});

	it('arc: labelAt 0.5 sits at the apex, offset outside the bulge', () => {
		const arc: PathShape = { kind: 'arc', from: [400, 540], to: [1500, 540], bend: 0.3 };
		expect(labelPos(arc, 0.5, 20)).toEqual([950, 190]); // apex [950, 210] − 20 further up
	});

	it('defaults to the midpoint with a 20px offset, never NaN', () => {
		const line: PathShape = { kind: 'line', from: [0, 0], to: [100, 0] };
		expect(labelPos(line)).toEqual([50, -20]);
		const dot: PathShape = { kind: 'line', from: [5, 5], to: [5, 5] };
		expect(labelPos(dot, NaN, NaN).every(Number.isFinite)).toBe(true);
	});
});

describe('polygonPoints', () => {
	it('formats a point list for the points attribute', () => {
		const pts: Point[] = [
			[1, 2],
			[3.456, 4]
		];
		expect(polygonPoints(pts)).toBe('1,2 3.46,4');
	});

	it('never contains NaN', () => {
		expect(polygonPoints([[NaN, Infinity]])).toBe('0,0');
	});
});

describe('pathShapes (multi-segment resolution)', () => {
	it('chains each segment start from the previous end (or `start` for the first)', () => {
		const shapes = pathShapes([0, 0], [{ to: [100, 0] }, { to: [100, 100] }]);
		expect(shapes).toEqual([
			{ kind: 'line', from: [0, 0], to: [100, 0] },
			{ kind: 'line', from: [100, 0], to: [100, 100] }
		]);
	});

	it('picks the KIND from the control data present', () => {
		const [line, quad, cubic, arc] = pathShapes(
			[0, 0],
			[
				{ to: [10, 0] },
				{ to: [20, 0], c1: [15, 10] },
				{ to: [30, 0], c1: [24, 10], c2: [26, -10] },
				{ to: [40, 0], bend: 0.3 }
			]
		);
		expect(line.kind).toBe('line');
		expect(quad.kind).toBe('quadratic');
		expect(cubic.kind).toBe('cubic');
		expect(arc.kind).toBe('arc');
	});

	it('gives `bend` precedence over control points, clamped to [-1, 1]', () => {
		const [seg] = pathShapes([0, 0], [{ to: [100, 0], bend: 5, c1: [50, 50] }]);
		expect(seg).toEqual({ kind: 'arc', from: [0, 0], to: [100, 0], bend: 1 });
	});

	it('honors an explicit per-segment `from` (a disjoint sub-path)', () => {
		const shapes = pathShapes([0, 0], [{ to: [100, 0] }, { from: [200, 0], to: [300, 0] }]);
		expect(shapes[1].from).toEqual([200, 0]);
	});

	it('drops a malformed segment (no `to`) rather than throwing', () => {
		const shapes = pathShapes([0, 0], [{ to: [50, 0] }, { c1: [10, 10] } as PathSegment, { to: [80, 0] }]);
		// The good segments still chain: the bad one is skipped, not a break.
		expect(shapes).toEqual([
			{ kind: 'line', from: [0, 0], to: [50, 0] },
			{ kind: 'line', from: [50, 0], to: [80, 0] }
		]);
	});

	it('is total on junk input (non-array segments, NaN points)', () => {
		expect(pathShapes([0, 0], 'nope' as unknown as PathSegment[])).toEqual([]);
		expect(pathShapes(undefined as unknown as Point, [])).toEqual([]);
		const [seg] = pathShapes([NaN, 5] as Point, [{ to: [Infinity, 10] }]);
		expect(seg).toEqual({ kind: 'line', from: [0, 5], to: [0, 10] });
	});
});

describe('multiPath', () => {
	it('joins a continuous chain into one path, dropping redundant Ms', () => {
		const shapes = pathShapes([0, 0], [{ to: [100, 0] }, { to: [100, 100] }]);
		expect(multiPath(shapes)).toBe('M 0 0 L 100 0 L 100 100');
	});

	it('keeps the M where a segment lifts the pen (a real gap)', () => {
		const shapes = pathShapes([0, 0], [{ to: [100, 0] }, { from: [200, 0], to: [300, 0] }]);
		const d = multiPath(shapes);
		expect(d).toBe('M 0 0 L 100 0 M 200 0 L 300 0');
		expect(d.match(/M /g)).toHaveLength(2); // two sub-paths
	});

	it('carries curve and arc commands through the chain', () => {
		const shapes = pathShapes(
			[0, 0],
			[{ to: [100, 0], c1: [50, 80] }, { to: [200, 0], bend: 0.5 }]
		);
		const d = multiPath(shapes);
		expect(d.startsWith('M 0 0 Q 50 80 100 0 ')).toBe(true);
		expect(d).toContain('A '); // the arc segment, no second M
		expect(d.match(/M /g)).toHaveLength(1);
	});

	it('is total: empty / non-array → empty string, never NaN', () => {
		expect(multiPath([])).toBe('');
		expect(multiPath(undefined as unknown as PathShape[])).toBe('');
		expect(multiPath(pathShapes([NaN, NaN] as Point, [{ to: [NaN, NaN] }]))).not.toContain('NaN');
	});
});

describe('pointAtMulti / angleAtMulti / labelPosMulti', () => {
	const shapes = pathShapes([0, 0], [{ to: [100, 0] }, { to: [100, 100] }]);

	it('walks the whole chain by arc length: t=0 start, t=1 end', () => {
		expect(pointAtMulti(shapes, 0)).toEqual([0, 0]);
		expect(pointAtMulti(shapes, 1)).toEqual([100, 100]);
	});

	it('lands the midpoint at the shared join (equal-length segments)', () => {
		expect(pointAtMulti(shapes, 0.5)).toEqual([100, 0]);
	});

	it('reports the local tangent of the containing segment', () => {
		expectAngle(angleAtMulti(shapes, 0), 0); // first segment points +x
		expectAngle(angleAtMulti(shapes, 1), Math.PI / 2); // last segment points +y (down)
	});

	it('offsets a label perpendicular to the local tangent', () => {
		expect(labelPosMulti(shapes, 0.5, 20)).toEqual([100, -20]);
	});

	it('is total on an empty chain (never NaN)', () => {
		expect(pointAtMulti([], 0.5)).toEqual([0, 0]);
		expect(angleAtMulti([], 0.5)).toBe(0);
		expect(labelPosMulti([]).every(Number.isFinite)).toBe(true);
	});
});

describe('sampleMultiPath (animation morph)', () => {
	const shapes = pathShapes([0, 0], [{ to: [100, 0] }, { to: [100, 100] }]);

	it('samples the whole chain into a fixed-count polyline (M + n L segments)', () => {
		expect(sampleMultiPath(shapes, 4)).toBe('M 0 0 L 50 0 L 100 0 L 100 50 L 100 100');
	});

	it('always emits the same command count regardless of segment kinds (so d:path morphs)', () => {
		const curvy = pathShapes([0, 0], [{ to: [100, 0], c1: [50, 80] }, { to: [200, 0], bend: 0.6 }]);
		const a = sampleMultiPath(shapes, 32);
		const b = sampleMultiPath(curvy, 32);
		const count = (d: string) => (d.match(/L /g) ?? []).length;
		expect(count(a)).toBe(32);
		expect(count(b)).toBe(32); // same L-count → the two poses interpolate
		expect(a.startsWith('M ')).toBe(true);
	});

	it('is total: empty chain → empty string, never NaN', () => {
		expect(sampleMultiPath([])).toBe('');
		expect(sampleMultiPath(pathShapes([NaN, NaN] as Point, [{ to: [NaN, NaN] }]), 8)).not.toContain('NaN');
	});
});

describe('unwrapAngles (shortest-path rotation keyframes)', () => {
	const rad = (d: number) => (d * Math.PI) / 180;
	const deg = (r: number) => (r * 180) / Math.PI;

	it('takes an un-normalized arc tangent the SHORT way, not a full spin', () => {
		// 426.84° (an arc end tangent that came back > 360°) → 66.84°, the
		// equivalent direction reached without whirling the head around.
		const u = unwrapAngles([0, rad(426.84)]);
		expect(u[0]).toBe(0);
		expect(deg(u[1])).toBeCloseTo(66.84, 1);
	});

	it('stays continuous across the atan2 branch cut (+170° → −170° is +20°)', () => {
		const u = unwrapAngles([rad(170), rad(-170)]);
		expect(deg(u[1] - u[0])).toBeCloseTo(20, 6); // the short way, not −340°
	});

	it('normalizes the first angle into (−π, π]', () => {
		expect(unwrapAngles([3 * Math.PI])[0]).toBeCloseTo(Math.PI, 6);
	});

	it('is total on junk (empty / non-array / NaN)', () => {
		expect(unwrapAngles([])).toEqual([]);
		expect(unwrapAngles(undefined as unknown as number[])).toEqual([]);
		expect(unwrapAngles([NaN, NaN]).every(Number.isFinite)).toBe(true);
	});
});

describe('uniformLengthParams', () => {
	const dist = (a: Point, b: Point) => Math.hypot(a[0] - b[0], a[1] - b[1]);
	/** Consecutive point-to-point distances along the shape at the given params. */
	const steps = (shape: PathShape, ts: number[]) => {
		const out: number[] = [];
		for (let k = 1; k < ts.length; k++) out.push(dist(pointAt(shape, ts[k - 1]), pointAt(shape, ts[k])));
		return out;
	};

	it('pins the endpoints and returns samples+1 monotonic params', () => {
		const cubic: PathShape = { kind: 'cubic', from: [0, 0], c1: [10, 0], c2: [20, 0], to: [1000, 0] };
		const ts = uniformLengthParams(cubic, 10);
		expect(ts).toHaveLength(11);
		expect(ts[0]).toBe(0);
		expect(ts[10]).toBe(1);
		for (let k = 1; k < ts.length; k++) expect(ts[k]).toBeGreaterThan(ts[k - 1]);
	});

	it('a line is already uniform: params ≈ k/n', () => {
		const line: PathShape = { kind: 'line', from: [0, 0], to: [800, 600] };
		const ts = uniformLengthParams(line, 8);
		ts.forEach((t, k) => expect(t).toBeCloseTo(k / 8, 3));
	});

	it('equalises travel on a parameter-skewed cubic (what syncs a rider to the pen tip)', () => {
		// Control points bunched at the start: uniform-t samples crawl early and
		// sprint late. Uniform-length samples must stride evenly instead.
		const skewed: PathShape = { kind: 'cubic', from: [0, 0], c1: [1, 0], c2: [2, 0], to: [1900, 0] };
		const before = steps(skewed, Array.from({ length: 11 }, (_, k) => k / 10));
		const after = steps(skewed, uniformLengthParams(skewed, 10));
		const spread = (d: number[]) => Math.max(...d) / Math.min(...d);
		expect(spread(before)).toBeGreaterThan(3); // the problem is real on this shape
		expect(spread(after)).toBeLessThan(1.05); // and the reparameterization removes it
	});

	it('a degenerate zero-length shape falls back to uniform t', () => {
		const dot: PathShape = { kind: 'line', from: [50, 50], to: [50, 50] };
		expect(uniformLengthParams(dot, 4)).toEqual([0, 0.25, 0.5, 0.75, 1]);
	});
});
