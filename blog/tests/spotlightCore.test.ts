// Pure geometry of the Spotlight overlay. No DOM, no component — the same
// contract connectorCore.test.ts / drawCore.test.ts hold: every number that
// reaches an SVG attribute is finite, and every degenerate input (garbage box,
// bad pad, a box off the canvas) still yields a drawable rectangle.
import { describe, expect, it } from 'vitest';
import { spotlightRect } from '../src/lib/draw/spotlightCore';

const W = 1920;
const H = 1080;

describe('spotlightRect', () => {
	it('grows the box by pad on every side and rounds the corners', () => {
		const r = spotlightRect({ x: 100, y: 100, width: 200, height: 80 }, 10, 16, W, H);
		expect(r).toEqual({ x: 90, y: 90, width: 220, height: 100, radius: 16 });
	});

	it('caps the radius at half the shorter side so a small box stays a rectangle', () => {
		const r = spotlightRect({ x: 100, y: 100, width: 20, height: 20 }, 0, 50, W, H);
		expect(r.width).toBe(20);
		expect(r.height).toBe(20);
		expect(r.radius).toBe(10); // min(50, 20/2, 20/2)
	});

	it('treats a negative or NaN pad as zero', () => {
		expect(spotlightRect({ x: 100, y: 100, width: 40, height: 40 }, -20, 0, W, H)).toMatchObject({
			x: 100, y: 100, width: 40, height: 40
		});
		expect(spotlightRect({ x: 100, y: 100, width: 40, height: 40 }, NaN, 0, W, H)).toMatchObject({
			x: 100, y: 100, width: 40, height: 40
		});
	});

	it('clamps a box that spills past the canvas edge to a non-negative width', () => {
		const r = spotlightRect({ x: 1900, y: 100, width: 200, height: 80 }, 10, 16, W, H);
		expect(r.x).toBe(1890);
		expect(r.width).toBe(30); // right clamped from 2110 to 1920
		expect(r.width).toBeGreaterThanOrEqual(0);
	});

	it('collapses a box entirely off-canvas to a zero-width sliver, never inside-out', () => {
		const r = spotlightRect({ x: 5000, y: 100, width: 100, height: 50 }, 0, 8, W, H);
		expect(r.x).toBe(1920);
		expect(r.width).toBe(0);
		expect(r.height).toBe(50);
	});

	it('never emits NaN from a garbage box', () => {
		const r = spotlightRect(
			{ x: NaN, y: Infinity, width: NaN, height: -5 } as unknown as { x: number; y: number; width: number; height: number },
			5,
			10,
			W,
			H
		);
		for (const v of [r.x, r.y, r.width, r.height, r.radius]) expect(Number.isFinite(v)).toBe(true);
		expect(r.width).toBeGreaterThanOrEqual(0);
		expect(r.height).toBeGreaterThanOrEqual(0);
	});

	it('survives a zero-size canvas without going negative', () => {
		const r = spotlightRect({ x: 100, y: 100, width: 40, height: 40 }, 10, 8, 0, 0);
		expect(r).toEqual({ x: 0, y: 0, width: 0, height: 0, radius: 0 });
	});
});
