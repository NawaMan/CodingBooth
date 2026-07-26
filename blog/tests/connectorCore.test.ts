// Pure geometry of the Connector router. No DOM, no components — the same
// contract drawCore.test.ts holds for the shapes: every number that reaches an
// SVG attribute is finite, and every degenerate input still yields a path.
import { describe, expect, it } from 'vitest';
import {
	borderPoint,
	connectorGeometry,
	cubicAt,
	dedupePoints,
	facingSide,
	oppositeSide,
	orthoPoints,
	perpendicular,
	pointRect,
	polylineAt,
	rectCenter,
	roundedPolylinePath,
	sideCenter,
	sideNormal,
	type Point,
	type Rect
} from '../src/lib/draw/connectorCore';

const box = (x: number, y: number, width = 100, height = 100): Rect => ({ x, y, width, height });

describe('rect helpers', () => {
	it('centers a box', () => {
		expect(rectCenter(box(100, 200, 300, 100))).toEqual([250, 250]);
	});

	it('places side centers, pushed out by the gap', () => {
		const r = box(100, 100, 200, 100); // 100..300 x 100..200, center [200, 150]
		expect(sideCenter(r, 'top')).toEqual([200, 100]);
		expect(sideCenter(r, 'bottom')).toEqual([200, 200]);
		expect(sideCenter(r, 'left')).toEqual([100, 150]);
		expect(sideCenter(r, 'right')).toEqual([300, 150]);
		expect(sideCenter(r, 'right', 10)).toEqual([310, 150]);
		expect(sideCenter(r, 'top', 10)).toEqual([200, 90]);
	});

	it('normals point out of their side; opposites pair up', () => {
		expect(sideNormal('top')).toEqual([0, -1]);
		expect(sideNormal('left')).toEqual([-1, 0]);
		expect(oppositeSide('top')).toBe('bottom');
		expect(oppositeSide('left')).toBe('right');
	});
});

describe('facingSide', () => {
	const r = box(0, 0, 100, 100);

	it('picks the edge facing the target', () => {
		expect(facingSide(r, [500, 50])).toBe('right');
		expect(facingSide(r, [-500, 50])).toBe('left');
		expect(facingSide(r, [50, 500])).toBe('bottom');
		expect(facingSide(r, [50, -500])).toBe('top');
	});

	it('weighs the direction against the box diagonal, not the raw axes', () => {
		// Both targets sit down-and-right at the SAME angle from their box center,
		// with |dx| and |dy| ordered the same way — only the aspect differs, and it
		// alone decides the edge (a naive |dx| vs |dy| test gets both backwards).
		const wide = box(0, 0, 400, 40); // center [200, 20]
		expect(facingSide(wide, [300, 70])).toBe('bottom'); // |dx| 100 > |dy| 50
		const tall = box(0, 0, 40, 400); // center [20, 200]
		expect(facingSide(tall, [70, 300])).toBe('right'); // |dx| 50 < |dy| 100
	});

	it('agrees with where borderPoint actually lands', () => {
		const wide = box(0, 0, 400, 40);
		// The ray crosses y = 40 (the bottom edge), inside the box's x range.
		expect(borderPoint(wide, [300, 70])).toEqual([240, 40]);
		expect(facingSide(wide, [300, 70])).toBe('bottom');
	});

	it('degenerates safely: a point anchor uses the dominant axis', () => {
		const p = pointRect([10, 10]);
		expect(facingSide(p, [100, 20])).toBe('right');
		expect(facingSide(p, [20, 100])).toBe('bottom');
		// Coincident target — no direction at all, but still a valid side.
		expect(facingSide(p, [10, 10])).toBe('right');
	});
});

describe('borderPoint', () => {
	const r = box(0, 0, 200, 100); // center [100, 50]

	it('hits the border along the ray from the center', () => {
		expect(borderPoint(r, [1000, 50])).toEqual([200, 50]); // straight right
		expect(borderPoint(r, [100, -1000])).toEqual([100, 0]); // straight up
	});

	it('hits a corner exactly when the ray runs down the diagonal', () => {
		// Direction (100, 50) from the center — the box half-extents exactly.
		expect(borderPoint(r, [200, 100])).toEqual([200, 100]);
	});

	it('adds the gap along the same direction', () => {
		expect(borderPoint(r, [1000, 50], 20)).toEqual([220, 50]);
	});

	it('returns the center for a coincident target (never NaN)', () => {
		expect(borderPoint(r, [100, 50])).toEqual([100, 50]);
	});

	it('handles a zero-size box (a point anchor)', () => {
		const p = pointRect([40, 40]);
		expect(borderPoint(p, [140, 40])).toEqual([40, 40]);
		expect(borderPoint(p, [140, 40], 10)).toEqual([50, 40]);
	});
});

describe('orthoPoints', () => {
	it('same-axis sides get a two-corner elbow across the midline', () => {
		const pts = orthoPoints([100, 50], [300, 150], 'right', 'left');
		expect(pts).toEqual([
			[100, 50],
			[200, 50],
			[200, 150],
			[300, 150]
		]);
	});

	it('vertical sides elbow across the horizontal midline', () => {
		const pts = orthoPoints([100, 50], [300, 150], 'bottom', 'top');
		expect(pts).toEqual([
			[100, 50],
			[100, 100],
			[300, 100],
			[300, 150]
		]);
	});

	it('perpendicular sides get a single corner', () => {
		expect(orthoPoints([100, 50], [300, 150], 'right', 'top')).toEqual([
			[100, 50],
			[300, 50],
			[300, 150]
		]);
		expect(orthoPoints([100, 50], [300, 150], 'bottom', 'left')).toEqual([
			[100, 50],
			[100, 150],
			[300, 150]
		]);
	});

	it('collapses the elbow when the boxes line up', () => {
		// Same y: the two corners land on the endpoints, so the elbow vanishes.
		expect(orthoPoints([100, 50], [300, 50], 'right', 'left')).toEqual([
			[100, 50],
			[200, 50],
			[300, 50]
		]);
	});
});

describe('dedupePoints', () => {
	it('drops consecutive duplicates', () => {
		expect(dedupePoints([[0, 0], [0, 0], [10, 0], [10, 0], [10, 10]])).toEqual([
			[0, 0],
			[10, 0],
			[10, 10]
		]);
	});

	it('never returns fewer than two points', () => {
		expect(dedupePoints([[5, 5], [5, 5]])).toEqual([[5, 5], [5, 5]]);
	});
});

describe('roundedPolylinePath', () => {
	it('emits a plain polyline when the radius is 0', () => {
		expect(roundedPolylinePath([[0, 0], [10, 0], [10, 10]], 0)).toBe('M 0 0 L 10 0 L 10 10');
	});

	it('a two-point line is never rounded', () => {
		expect(roundedPolylinePath([[0, 0], [10, 0]], 12)).toBe('M 0 0 L 10 0');
	});

	it('cuts each corner back and bridges it with a quadratic at the corner', () => {
		const d = roundedPolylinePath([[0, 0], [100, 0], [100, 100]], 20);
		expect(d).toBe('M 0 0 L 80 0 Q 100 0 100 20 L 100 100');
	});

	it('clamps the cut to half of the shorter leg, so corners never overrun', () => {
		// Middle leg is 20 long; a radius of 100 must cut at most 10 per corner.
		const d = roundedPolylinePath([[0, 0], [100, 0], [100, 20], [200, 20]], 100);
		expect(d).toBe('M 0 0 L 90 0 Q 100 0 100 10 L 100 10 Q 100 20 110 20 L 200 20');
	});

	it('renders nothing for fewer than two points', () => {
		expect(roundedPolylinePath([[0, 0]], 10)).toBe('');
	});
});

describe('polylineAt', () => {
	const L: Point[] = [
		[0, 0],
		[100, 0],
		[100, 100]
	];

	it('walks by arc length, not by vertex count', () => {
		// Total length 200; halfway is the corner itself.
		expect(polylineAt(L, 0.5).point).toEqual([100, 0]);
		expect(polylineAt(L, 0.25).point).toEqual([50, 0]);
		expect(polylineAt(L, 0.75).point).toEqual([100, 50]);
	});

	it('reports the direction of travel', () => {
		expect(polylineAt(L, 0.25).angle).toBeCloseTo(0);
		expect(polylineAt(L, 0.75).angle).toBeCloseTo(Math.PI / 2);
	});

	it('clamps t and survives a zero-length polyline', () => {
		expect(polylineAt(L, -5).point).toEqual([0, 0]);
		expect(polylineAt(L, 5).point).toEqual([100, 100]);
		expect(polylineAt([[7, 7], [7, 7]], 0.5)).toEqual({ point: [7, 7], angle: 0 });
	});
});

describe('cubicAt', () => {
	it('evaluates the midpoint of a symmetric curve', () => {
		const { point, angle } = cubicAt([0, 0], [100, 0], [100, 100], [0, 100], 0.5);
		expect(point).toEqual([75, 50]);
		expect(angle).toBeCloseTo(Math.PI / 2); // straight down at the apex
	});

	it('falls back to the chord angle when the tangent degenerates', () => {
		const { angle } = cubicAt([0, 0], [0, 0], [0, 0], [100, 0], 0);
		expect(angle).toBeCloseTo(0);
	});
});

describe('perpendicular', () => {
	it('offsets to the LEFT of the direction of travel', () => {
		// Heading right (+x): left is screen-up (-y).
		expect(perpendicular([100, 100], 0, 20)).toEqual([100, 80]);
		// Heading down (+y): left is +x.
		expect(perpendicular([100, 100], Math.PI / 2, 20)).toEqual([120, 100]);
	});
});

describe('connectorGeometry', () => {
	// A left box and a right box, level with each other.
	const a = box(100, 100, 200, 100); // 100..300, center [200, 150]
	const b = box(500, 100, 200, 100); // 500..700, center [600, 150]

	it('straight: attaches on the facing borders, honouring the gap', () => {
		const g = connectorGeometry(a, b, { route: 'straight', gap: 10 });
		expect(g.start).toEqual([310, 150]);
		expect(g.end).toEqual([490, 150]);
		expect(g.fromSide).toBe('right');
		expect(g.toSide).toBe('left');
		expect(g.d).toBe('M 310 150 L 490 150');
	});

	it('straight: pulls the shaft back behind an arrowhead, tip stays on the box', () => {
		const g = connectorGeometry(a, b, { route: 'straight', gap: 0, arrowEnd: true, arrowSize: 20 });
		expect(g.end).toEqual([500, 150]); // the TIP is still on b's border
		expect(g.d).toBe('M 300 150 L 480 150'); // the shaft stops 20 short
		expect(g.endAngle).toBeCloseTo(0);
	});

	it('straight: both heads shorten both ends', () => {
		const g = connectorGeometry(a, b, {
			route: 'straight',
			gap: 0,
			arrowStart: true,
			arrowEnd: true,
			arrowSize: 20
		});
		expect(g.d).toBe('M 320 150 L 480 150');
		expect(g.startAngle).toBeCloseTo(Math.PI); // start head points back at a
	});

	it('straight: an explicit toSide steers the other end\'s border hit', () => {
		// Force entry through b's TOP: the shaft must now leave a diagonally, so
		// its start no longer sits on a's right-edge midpoint.
		const g = connectorGeometry(a, b, { route: 'straight', toSide: 'top', gap: 0 });
		expect(g.end).toEqual([600, 100]);
		expect(g.toSide).toBe('top');
		expect(g.start[1]).toBeLessThan(150); // it exits above the midpoint
	});

	it('ortho: right-angled elbow between the facing sides', () => {
		const g = connectorGeometry(a, b, { route: 'ortho', gap: 0, radius: 0 });
		// Level boxes: both elbow corners land on the midline, so they collapse
		// into the one point rather than emitting a zero-length jog.
		expect(g.d).toBe('M 300 150 L 400 150 L 500 150');
		expect(g.fromSide).toBe('right');
		expect(g.toSide).toBe('left');
	});

	it('ortho: stacked boxes elbow vertically and round their corners', () => {
		const below = box(500, 500, 200, 100);
		const g = connectorGeometry(a, below, { route: 'ortho', gap: 0, radius: 20 });
		expect(g.fromSide).toBe('bottom');
		expect(g.toSide).toBe('top');
		expect(g.d).toContain('Q'); // corners are rounded
		expect(g.d.startsWith('M 200 200')).toBe(true); // a's bottom-edge midpoint
	});

	it('curve: leaves and enters square to each side', () => {
		const g = connectorGeometry(a, b, { route: 'curve', gap: 0 });
		expect(g.d.startsWith('M 300 150 C')).toBe(true);
		// Control points pull straight out along each side's normal, so both the
		// exit and the entry tangent are horizontal.
		expect(g.startAngle).toBeCloseTo(Math.PI); // start head faces back left
		expect(g.endAngle).toBeCloseTo(0);
	});

	it('places the label off the shaft at labelAt', () => {
		const g = connectorGeometry(a, b, { route: 'straight', gap: 0, labelAt: 0.5, labelOffset: 30 });
		// Midpoint of the shaft, lifted 30px "left" of a rightward heading = up.
		expect(g.label).toEqual([400, 120]);
	});

	it('survives coincident boxes without emitting NaN', () => {
		const g = connectorGeometry(a, a, { route: 'straight', gap: 0, arrowEnd: true, arrowSize: 20 });
		expect(g.d).not.toContain('NaN');
		expect(Number.isFinite(g.start[0])).toBe(true);
		expect(Number.isFinite(g.endAngle)).toBe(true);
	});

	it('survives garbage geometry (half-typed props) on every route', () => {
		const bad = { x: NaN, y: undefined as unknown as number, width: -50, height: NaN };
		for (const route of ['straight', 'ortho', 'curve'] as const) {
			const g = connectorGeometry(bad, b, { route, gap: NaN, radius: NaN, arrowSize: NaN });
			expect(g.d).not.toContain('NaN');
			expect(g.label.every(Number.isFinite)).toBe(true);
		}
	});

	it('connects a point anchor to a box', () => {
		const g = connectorGeometry(pointRect([50, 150]), b, { route: 'straight', gap: 0 });
		expect(g.start).toEqual([50, 150]);
		expect(g.end).toEqual([500, 150]);
	});
});
