import { describe, expect, it } from 'vitest';
import { clamp, easeFn, interpAt, trackKeys, type CanvasStop } from '../src/lib/draw/canvasCore';

describe('clamp', () => {
	it('bounds a value into [lo, hi]', () => {
		expect(clamp(5, 0, 10)).toBe(5);
		expect(clamp(-1, 0, 10)).toBe(0);
		expect(clamp(11, 0, 10)).toBe(10);
	});
});

describe('easeFn', () => {
	it('is identity for linear and pins the endpoints for every curve', () => {
		for (const e of ['linear', 'ease', 'ease-in', 'ease-out', 'ease-in-out'] as const) {
			expect(easeFn(e)(0)).toBeCloseTo(0);
			expect(easeFn(e)(1)).toBeCloseTo(1);
		}
		expect(easeFn('linear')(0.37)).toBeCloseTo(0.37);
	});

	it('bends ease-in below the diagonal and ease-out above it at the midpoint', () => {
		expect(easeFn('ease-in')(0.5)).toBeLessThan(0.5);
		expect(easeFn('ease-out')(0.5)).toBeGreaterThan(0.5);
	});

	it('accepts a custom function and clamps its input to [0,1]', () => {
		const f = easeFn((t) => t * t);
		expect(f(0.5)).toBeCloseTo(0.25);
		expect(f(2)).toBeCloseTo(1); // input clamped to 1 → 1
		expect(f(-1)).toBeCloseTo(0);
	});

	it('falls back to linear for an unknown name', () => {
		// @ts-expect-error exercising the runtime fallback
		expect(easeFn('bogus')(0.42)).toBeCloseTo(0.42);
	});
});

describe('trackKeys', () => {
	it('lists numeric tracks in first-seen order, ignoring pct/ease', () => {
		const stops: CanvasStop[] = [
			{ pct: 0, x: 1, ease: 'ease-in' },
			{ pct: 100, x: 2, y: 3 }
		];
		expect(trackKeys(stops)).toEqual(['x', 'y']);
	});
});

describe('interpAt', () => {
	const stops: CanvasStop[] = [
		{ pct: 0, x: 0, y: 100 },
		{ pct: 100, x: 100, y: 0 }
	];

	it('returns endpoint values at the ends and the midpoint under linear', () => {
		expect(interpAt(stops, 0)).toEqual({ x: 0, y: 100 });
		expect(interpAt(stops, 100)).toEqual({ x: 100, y: 0 });
		const mid = interpAt(stops, 50);
		expect(mid.x).toBeCloseTo(50);
		expect(mid.y).toBeCloseTo(50);
	});

	it('holds at the nearest stop before the first / after the last (fill both)', () => {
		expect(interpAt(stops, -20)).toEqual({ x: 0, y: 100 });
		expect(interpAt(stops, 140)).toEqual({ x: 100, y: 0 });
	});

	it('applies the LEFT stop ease to the segment', () => {
		const eased: CanvasStop[] = [
			{ pct: 0, x: 0, ease: 'ease-in' },
			{ pct: 100, x: 100 }
		];
		// ease-in pulls the mid value below the linear 50.
		expect(interpAt(eased, 50).x).toBeLessThan(50);
	});

	it('sorts unsorted stops and picks the right segment', () => {
		const messy: CanvasStop[] = [
			{ pct: 100, v: 10 },
			{ pct: 0, v: 0 },
			{ pct: 50, v: 2 }
		];
		expect(interpAt(messy, 25).v).toBeCloseTo(1); // between 0 and 2
		expect(interpAt(messy, 75).v).toBeCloseTo(6); // between 2 and 10
	});

	it('falls back to the nearest defined value for a track absent from a bounding stop', () => {
		const partial: CanvasStop[] = [
			{ pct: 0, x: 0 },
			{ pct: 50, x: 10, y: 4 }, // y appears only here
			{ pct: 100, x: 20 }
		];
		// In [50,100], y is undefined at 100 → holds at the pct:50 value (4).
		expect(interpAt(partial, 75).y).toBeCloseTo(4);
	});

	it('returns {} for empty stops or stops with no numeric tracks', () => {
		expect(interpAt([], 50)).toEqual({});
		expect(interpAt([{ pct: 0 }, { pct: 100 }], 50)).toEqual({});
	});
});
