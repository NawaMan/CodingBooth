// Pure compiler for <Cursor>'s chained warpTo/moveTo/around scripts. No DOM,
// no component — the same contract cursorCore.test.ts / connectorCore.test.ts
// hold: every number that reaches generated CSS is finite, and every
// degenerate input still yields a drawable (or static) result.
import { describe, expect, it } from 'vitest';
import { compileScript, cursorScript, type ResolvedCursorCommand } from '../src/lib/draw/cursorScriptCore';
import { cursorRippleRadius } from '../src/lib/draw/cursorCore';

describe('compileScript — single command (no motion)', () => {
	it('a lone command is a static pose at pct 0, zero duration', () => {
		const r = compileScript([{ kind: 'warpTo', at: [500, 300], click: false }], 40);
		expect(r.totalSeconds).toBe(0);
		expect(r.stops).toEqual([{ pct: 0, x: 480, y: 280, w: 40, h: 40, rot: 0 }]);
		expect(r.ripples).toEqual([]);
	});

	it('a click on the lone command still fires a ripple, at delay 0', () => {
		const r = compileScript([{ kind: 'moveTo', at: [10, 20], times: 1, period: 3, click: true }], 40);
		expect(r.ripples).toEqual([{ x: 10, y: 20, r: cursorRippleRadius(40), delaySec: 0 }]);
	});

	it('empty input compiles to nothing', () => {
		expect(compileScript([], 40)).toEqual({ stops: [], ripples: [], totalSeconds: 0 });
	});
});

describe('compileScript — warpTo', () => {
	it('is an instant cut: a short, fixed-duration two-stop snap', () => {
		const cmds: ResolvedCursorCommand[] = [
			{ kind: 'warpTo', at: [0, 0], click: false },
			{ kind: 'warpTo', at: [500, 500], click: true }
		];
		const r = compileScript(cmds, 20);
		expect(r.totalSeconds).toBeCloseTo(0.05, 5);
		expect(r.stops).toHaveLength(2);
		expect(r.stops[0]).toMatchObject({ pct: 0, x: -10, y: -10 });
		expect(r.stops[1]).toMatchObject({ pct: 100, x: 490, y: 490 });
		expect(r.ripples).toEqual([{ x: 500, y: 500, r: cursorRippleRadius(20), delaySec: 0.05 }]);
	});
});

describe('compileScript — moveTo (one-way legs, alternating)', () => {
	it('times=1 (the default) is a single direct arrival — no return', () => {
		const cmds: ResolvedCursorCommand[] = [
			{ kind: 'warpTo', at: [100, 100], click: false },
			{ kind: 'moveTo', at: [300, 100], times: 1, period: 2, click: true }
		];
		const r = compileScript(cmds, 40);
		expect(r.totalSeconds).toBe(2);
		expect(r.stops.map((s) => s.pct)).toEqual([0, 100]);
		expect(r.stops[0]).toMatchObject({ x: 80, y: 80 });
		expect(r.stops[1]).toMatchObject({ x: 280, y: 80 }); // arrives, stays
		expect(r.ripples).toEqual([{ x: 300, y: 100, r: cursorRippleRadius(40), delaySec: 2 }]);
	});

	it('times=2 is one there-and-back shake, ending back where it started', () => {
		const cmds: ResolvedCursorCommand[] = [
			{ kind: 'warpTo', at: [0, 0], click: false },
			{ kind: 'moveTo', at: [100, 0], times: 2, period: 2, click: true }
		];
		const r = compileScript(cmds, 20);
		expect(r.totalSeconds).toBe(4); // 2 legs × 2s
		expect(r.stops.map((s) => s.pct)).toEqual([0, 50, 100]);
		expect(r.stops[1]).toMatchObject({ x: 90, y: -10 }); // leg 1: arrives
		expect(r.stops[2]).toMatchObject({ x: -10, y: -10 }); // leg 2: back home
		// Only ONE arrival at the target — the return leg isn't a "click".
		expect(r.ripples).toEqual([{ x: 100, y: 0, r: cursorRippleRadius(20), delaySec: 2 }]);
	});

	it('times=3 alternates to/from/to, ending at the target with two ripples', () => {
		const cmds: ResolvedCursorCommand[] = [
			{ kind: 'warpTo', at: [0, 0], click: false },
			{ kind: 'moveTo', at: [100, 0], times: 3, period: 2, click: true }
		];
		const r = compileScript(cmds, 20);
		expect(r.totalSeconds).toBe(6); // 3 legs × 2s
		expect(r.stops.map((s) => s.pct)).toEqual([0, 33.33, 66.67, 100]);
		expect(r.stops[r.stops.length - 1]).toMatchObject({ x: 90, y: -10 }); // ends AT the target
		expect(r.ripples).toHaveLength(2); // legs 1 and 3 — the two arrivals
		expect(r.ripples.map((p) => p.delaySec)).toEqual([2, 6]);
	});

	it('an ODD leg count hands the target off as "current" to what comes next', () => {
		const cmds: ResolvedCursorCommand[] = [
			{ kind: 'warpTo', at: [0, 0], click: false },
			{ kind: 'moveTo', at: [100, 0], times: 1, period: 1, click: false }, // odd → current = [100,0]
			{ kind: 'moveTo', at: [500, 500], times: 2, period: 1, click: false } // its "home" reveals current
		];
		const r = compileScript(cmds, 20);
		const last = r.stops[r.stops.length - 1]; // leg 2 of the 2nd moveTo returns "home"
		expect(last).toMatchObject({ x: 90, y: -10 }); // [100,0] − 10, not [0,0]
	});

	it('an EVEN leg count hands "home" (unchanged) off to what comes next', () => {
		const cmds: ResolvedCursorCommand[] = [
			{ kind: 'warpTo', at: [0, 0], click: false },
			{ kind: 'moveTo', at: [100, 0], times: 2, period: 1, click: false }, // even → current = [0,0]
			{ kind: 'moveTo', at: [500, 500], times: 2, period: 1, click: false }
		];
		const r = compileScript(cmds, 20);
		const last = r.stops[r.stops.length - 1];
		expect(last).toMatchObject({ x: -10, y: -10 }); // still [0,0] − 10
	});
});

describe('compileScript — around (orbit)', () => {
	it('enters at the angle of the current point relative to the centre', () => {
		const cmds: ResolvedCursorCommand[] = [
			{ kind: 'warpTo', at: [600, 300], click: false }, // straight above the centre
			{ kind: 'around', at: [600, 400], rx: 100, ry: 50, times: 1, period: 3.2, click: true }
		];
		const r = compileScript(cmds, 20);
		expect(r.totalSeconds).toBeCloseTo(3.2, 3);
		// One full lap returns to the entry angle — same point it started the loop at.
		const last = r.stops[r.stops.length - 1];
		expect(last.x).toBeCloseTo(600 - 10, 0); // centre.x + rx·cos(entry) − size/2, entry ≈ −90°
		expect(last.y).toBeCloseTo(350 - 10, 0); // centre.y − ry
		expect(r.ripples).toHaveLength(1); // exactly one, at the completed lap
		expect(r.ripples[0].delaySec).toBeCloseTo(3.2, 3);
	});

	it('multiple laps fire one ripple per completed lap, not per sample', () => {
		const cmds: ResolvedCursorCommand[] = [
			{ kind: 'warpTo', at: [700, 300], click: false },
			{ kind: 'around', at: [600, 300], rx: 100, ry: 100, times: 3, period: 1, click: true }
		];
		const r = compileScript(cmds, 20);
		expect(r.ripples).toHaveLength(3);
		expect(r.ripples.map((p) => Math.round(p.delaySec * 100) / 100)).toEqual([1, 2, 3]);
	});

	it('a degenerate rx/ry orbits along a flat line rather than throwing', () => {
		const cmds: ResolvedCursorCommand[] = [
			{ kind: 'warpTo', at: [500, 500], click: false },
			{ kind: 'around', at: [500, 500], rx: 0, ry: 80, times: 1, period: 1, click: false }
		];
		const r = compileScript(cmds, 20);
		for (const s of r.stops) {
			for (const v of [s.x, s.y, s.w, s.h, s.rot]) expect(Number.isFinite(v)).toBe(true);
		}
	});
});

describe('compileScript — attention (a size pulse in place)', () => {
	it('a single pulse grows the glyph and returns, without moving', () => {
		const cmds: ResolvedCursorCommand[] = [
			{ kind: 'warpTo', at: [500, 500], click: false },
			{ kind: 'attention', times: 1, period: 0.6, scale: 1.5, click: true }
		];
		const r = compileScript(cmds, 40);
		expect(r.totalSeconds).toBeCloseTo(0.6, 5);
		expect(r.stops.map((s) => s.pct)).toEqual([0, 50, 100]);
		expect(r.stops[0]).toMatchObject({ x: 480, y: 480, w: 40, h: 40 });
		expect(r.stops[1]).toMatchObject({ x: 470, y: 470, w: 60, h: 60 }); // peak: 1.5×
		expect(r.stops[2]).toMatchObject({ x: 480, y: 480, w: 40, h: 40 }); // settles back
		expect(r.ripples).toEqual([{ x: 500, y: 500, r: cursorRippleRadius(60), delaySec: 0.3 }]); // peak size 40×1.5
	});

	it('times=2 pulses twice, one ripple per peak', () => {
		const cmds: ResolvedCursorCommand[] = [
			{ kind: 'warpTo', at: [0, 0], click: false },
			{ kind: 'attention', times: 2, period: 0.5, scale: 1.4, click: true }
		];
		const r = compileScript(cmds, 40);
		expect(r.totalSeconds).toBeCloseTo(1, 5);
		expect(r.ripples).toHaveLength(2);
		expect(r.ripples.map((p) => p.delaySec)).toEqual([0.25, 0.75]);
	});

	it('as the very first command it degenerates to the canvas origin — documented, never NaN', () => {
		const cmds: ResolvedCursorCommand[] = [
			{ kind: 'attention', times: 1, period: 0.4, scale: 1.2, click: false }
		];
		const r = compileScript(cmds, 40);
		expect(r.totalSeconds).toBe(0); // a lone command is always static
		expect(r.stops).toEqual([{ pct: 0, x: -20, y: -20, w: 40, h: 40, rot: 0 }]);
	});
});

describe('compileScript — per-command size overrides', () => {
	it('a size set on one command becomes AMBIENT for every command after it', () => {
		const cmds: ResolvedCursorCommand[] = [
			{ kind: 'warpTo', at: [0, 0], click: false },
			{ kind: 'moveTo', at: [100, 0], times: 1, period: 1, click: false, size: 80 },
			{ kind: 'warpTo', at: [200, 0], click: false } // no size of its own
		];
		const r = compileScript(cmds, 40);
		expect(r.stops[0]).toMatchObject({ x: -20, y: -20, w: 40, h: 40 }); // default box
		expect(r.stops[1]).toMatchObject({ x: 60, y: -40, w: 80, h: 80 }); // overridden
		expect(r.stops[2]).toMatchObject({ x: 160, y: -40, w: 80, h: 80 }); // still ambient
	});

	it('a size on the FIRST command sets the initial ambient too', () => {
		const r = compileScript([{ kind: 'warpTo', at: [0, 0], click: false, size: 100 }], 40);
		expect(r.stops).toEqual([{ pct: 0, x: -50, y: -50, w: 100, h: 100, rot: 0 }]);
	});

	it('a garbage size is ignored — the ambient stays at whatever it was', () => {
		const cmds: ResolvedCursorCommand[] = [
			{ kind: 'warpTo', at: [0, 0], click: false },
			{ kind: 'warpTo', at: [100, 0], click: false, size: NaN },
			{ kind: 'warpTo', at: [200, 0], click: false, size: -5 }
		];
		const r = compileScript(cmds, 40);
		for (const s of r.stops) expect(s.w).toBe(40);
	});
});

describe('compileScript — NaN safety', () => {
	it('garbage coordinates, radii and timing never produce NaN/Infinity', () => {
		const cmds: ResolvedCursorCommand[] = [
			{ kind: 'warpTo', at: [NaN, Infinity], click: false },
			{
				kind: 'moveTo',
				at: [-Infinity, 10],
				times: NaN as unknown as number,
				period: -5,
				click: true
			},
			{ kind: 'around', at: [10, NaN], rx: NaN, ry: -20, times: 0, period: NaN, click: true }
		];
		const r = compileScript(cmds, NaN);
		for (const s of r.stops) {
			for (const v of [s.pct, s.x, s.y, s.w, s.h, s.rot]) expect(Number.isFinite(v)).toBe(true);
			expect(s.w).toBeGreaterThanOrEqual(1);
			expect(s.h).toBeGreaterThanOrEqual(1);
		}
		for (const p of r.ripples) {
			expect(Number.isFinite(p.x)).toBe(true);
			expect(Number.isFinite(p.y)).toBe(true);
			expect(Number.isFinite(p.delaySec)).toBe(true);
			expect(p.delaySec).toBeGreaterThanOrEqual(0);
		}
		expect(Number.isFinite(r.totalSeconds)).toBe(true);
	});
});

describe('cursorScript builder', () => {
	it('chains into a plain, serializable command array — nothing executes', () => {
		const cmds = cursorScript()
			.warpTo([0, 0])
			.moveTo('save-btn', { times: 2, period: 1, size: 60 })
			.around('dial', 80, 40, { times: 1, period: 2, click: true })
			.attention({ times: 2, click: true })
			.build();
		expect(cmds).toEqual([
			{ kind: 'warpTo', at: [0, 0] },
			{ kind: 'moveTo', at: 'save-btn', times: 2, period: 1, size: 60 },
			{ kind: 'around', at: 'dial', rx: 80, ry: 40, times: 1, period: 2, click: true },
			{ kind: 'attention', times: 2, click: true }
		]);
	});
});
