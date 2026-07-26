import { describe, expect, it } from 'vitest';
import { stepTocSelection } from '../src/lib/chrome/presenterTocCore';

describe('stepTocSelection', () => {
	it('an unplaced cursor (< 0) lands on the first row going down', () => {
		expect(stepTocSelection(-1, 1, 5)).toBe(0);
	});

	it('an unplaced cursor (< 0) lands on the last row going up', () => {
		expect(stepTocSelection(-1, -1, 5)).toBe(4);
	});

	it('wraps forward past the last row to the first', () => {
		expect(stepTocSelection(4, 1, 5)).toBe(0);
	});

	it('wraps backward past the first row to the last', () => {
		expect(stepTocSelection(0, -1, 5)).toBe(4);
	});

	it('steps by an arbitrary delta', () => {
		expect(stepTocSelection(0, 2, 5)).toBe(2);
	});

	it('an empty list has no selection', () => {
		expect(stepTocSelection(-1, 1, 0)).toBe(-1);
		expect(stepTocSelection(2, 1, 0)).toBe(-1);
	});

	it('is total: junk numbers in, a valid index (or -1) out', () => {
		expect(stepTocSelection(NaN, NaN, 5)).toBe(0);
		expect(stepTocSelection(0, 1, NaN)).toBe(-1);
		expect(stepTocSelection(1.9, 1.9, 5)).toBe(2);
	});
});
