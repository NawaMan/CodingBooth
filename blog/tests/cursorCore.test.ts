// Pure geometry/timing for <Cursor>. No DOM, no component — the same
// contract connectorCore.test.ts / spotlightCore.test.ts hold: every number
// that reaches generated CSS is finite, and every degenerate input (no
// targets, one target, garbage size/timing) still yields a drawable result.
import { describe, expect, it } from 'vitest';
import { cursorRippleRadius, cursorRipples, cursorSpriteStops } from '../src/lib/draw/cursorCore';

describe('cursorSpriteStops', () => {
	it('returns nothing for zero targets — Cursor then renders nothing', () => {
		expect(cursorSpriteStops([], 40)).toEqual([]);
	});

	it('a single target is a static (non-animating) stop at pct 0', () => {
		const s = cursorSpriteStops([{ x: 500, y: 300, click: false }], 40);
		expect(s).toEqual([{ pct: 0, x: 480, y: 280, w: 40, h: 40, rot: 0 }]);
	});

	it("a target's own size overrides the shared box for just that stop", () => {
		const s = cursorSpriteStops(
			[
				{ x: 100, y: 100, click: false },
				{ x: 500, y: 500, click: false, size: 80 }
			],
			40
		);
		expect(s[0]).toMatchObject({ x: 80, y: 80, w: 40, h: 40 });
		expect(s[1]).toMatchObject({ x: 460, y: 460, w: 80, h: 80 });
	});

	it('evenly spaces N targets 0..100%, box top-left = centre − size/2', () => {
		const s = cursorSpriteStops(
			[
				{ x: 0, y: 0, click: false },
				{ x: 100, y: 100, click: false },
				{ x: 200, y: 200, click: true }
			],
			20
		);
		expect(s.map((r) => r.pct)).toEqual([0, 50, 100]);
		expect(s[0]).toMatchObject({ x: -10, y: -10, w: 20, h: 20 });
		expect(s[2]).toMatchObject({ x: 190, y: 190, w: 20, h: 20 });
	});

	it('is NaN-safe: garbage coordinates and size still yield finite stops', () => {
		const s = cursorSpriteStops(
			[
				{ x: NaN, y: Infinity, click: false },
				{ x: -5, y: 10, click: false }
			],
			NaN
		);
		for (const stop of s) {
			for (const v of [stop.x, stop.y, stop.w, stop.h, stop.rot]) {
				expect(Number.isFinite(v)).toBe(true);
			}
			expect(stop.w).toBeGreaterThanOrEqual(1);
			expect(stop.h).toBeGreaterThanOrEqual(1);
		}
	});
});

describe('cursorRipples', () => {
	it('returns nothing when no target is marked click', () => {
		expect(
			cursorRipples(
				[
					{ x: 0, y: 0, click: false },
					{ x: 100, y: 100, click: false }
				],
				0,
				1,
				40
			)
		).toEqual([]);
	});

	it('times a ripple at delay + animate·pct, matching Sprite\'s own placement', () => {
		const r = cursorRipples(
			[
				{ x: 0, y: 0, click: false },
				{ x: 200, y: 100, click: true },
				{ x: 400, y: 100, click: true }
			],
			0.5,
			2,
			40
		);
		expect(r).toEqual([
			{ x: 200, y: 100, r: cursorRippleRadius(40), delaySec: 0.5 + 2 * 0.5 }, // 2nd of 3 → pct 0.5
			{ x: 400, y: 100, r: cursorRippleRadius(40), delaySec: 0.5 + 2 * 1 } // last → pct 1
		]);
	});

	it('a single clicked target fires at just the hold — there is no flight to time against', () => {
		const r = cursorRipples([{ x: 10, y: 20, click: true }], 0.3, 5, 40);
		expect(r).toEqual([{ x: 10, y: 20, r: cursorRippleRadius(40), delaySec: 0.3 }]);
	});

	it("a target's own size drives ITS ripple radius, not the shared default", () => {
		const r = cursorRipples([{ x: 10, y: 20, click: true, size: 100 }], 0, 1, 40);
		expect(r[0].r).toBe(cursorRippleRadius(100));
		expect(r[0].r).not.toBe(cursorRippleRadius(40));
	});

	it('is NaN-safe: garbage delay/animate never produce a negative or NaN offset', () => {
		const r = cursorRipples(
			[
				{ x: 0, y: 0, click: false },
				{ x: 10, y: 10, click: true }
			],
			NaN,
			-5,
			40
		);
		expect(Number.isFinite(r[0].delaySec)).toBe(true);
		expect(r[0].delaySec).toBeGreaterThanOrEqual(0);
	});
});

describe('cursorRippleRadius', () => {
	it('scales with the glyph size, floored so a tiny cursor still gets a visible flash', () => {
		expect(cursorRippleRadius(40)).toBe(22);
		expect(cursorRippleRadius(2)).toBe(4); // floor, not 1.1
	});

	it('falls back to the default size for garbage input', () => {
		expect(cursorRippleRadius(NaN)).toBe(cursorRippleRadius(40));
	});
});
