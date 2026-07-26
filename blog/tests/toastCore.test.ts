// Pure timing/placement of the Toast. No DOM, no component — the same contract
// spotlightCore.test.ts / drawCore.test.ts hold: every value is total and finite,
// and junk (undefined, NaN, a string, Infinity) yields a sensible answer rather
// than a `setTimeout(NaN)` that flashes the toast away on the frame it appears.
import { describe, expect, it } from 'vitest';
import { autoDismissMs, clampDim, toastPlacement } from '../src/lib/utils/toastCore';

describe('toastPlacement', () => {
	it('passes through the three known placements', () => {
		expect(toastPlacement('top')).toBe('top');
		expect(toastPlacement('center')).toBe('center');
		expect(toastPlacement('bottom')).toBe('bottom');
	});

	it('falls back to bottom for an unknown or missing value', () => {
		expect(toastPlacement('middle')).toBe('bottom');
		expect(toastPlacement('')).toBe('bottom');
		expect(toastPlacement(undefined)).toBe('bottom');
		expect(toastPlacement(null)).toBe('bottom');
		expect(toastPlacement(42 as unknown)).toBe('bottom');
	});
});

describe('autoDismissMs', () => {
	it('uses a finite positive duration as-is', () => {
		expect(autoDismissMs(2600)).toBe(2600);
		expect(autoDismissMs(500)).toBe(500);
	});

	it('treats 0 or a negative duration as sticky (0 = never auto-dismiss)', () => {
		expect(autoDismissMs(0)).toBe(0);
		expect(autoDismissMs(-1)).toBe(0);
		expect(autoDismissMs(-9999)).toBe(0);
	});

	it('falls back to the default dwell for a non-finite duration', () => {
		expect(autoDismissMs(undefined)).toBe(2600);
		expect(autoDismissMs(NaN)).toBe(2600);
		expect(autoDismissMs(Infinity)).toBe(2600);
		expect(autoDismissMs('soon' as unknown)).toBe(2600);
	});

	it('honours a custom fallback, and never returns a negative fallback', () => {
		expect(autoDismissMs(undefined, 1000)).toBe(1000);
		expect(autoDismissMs(NaN, -50)).toBe(0);
	});
});

describe('clampDim', () => {
	it('clamps into 0–1', () => {
		expect(clampDim(0.4)).toBe(0.4);
		expect(clampDim(0)).toBe(0);
		expect(clampDim(1)).toBe(1);
		expect(clampDim(2)).toBe(1);
		expect(clampDim(-0.5)).toBe(0);
	});

	it('falls back for junk without emitting NaN', () => {
		expect(clampDim(undefined)).toBe(0.4);
		expect(clampDim(NaN)).toBe(0.4);
		expect(clampDim('dark' as unknown)).toBe(0.4);
		expect(Number.isFinite(clampDim(Infinity))).toBe(true);
	});
});
