import { describe, expect, it } from 'vitest';
import { frontZ, backZ } from '$lib/utils/stackingCore';

describe('frontZ', () => {
	it('lands one above the highest sibling', () => {
		expect(frontZ(0, [0, 1, 5])).toBe(6);
		expect(frontZ(2, [3])).toBe(4);
	});

	it('is a no-op when already the unique top (no churn)', () => {
		expect(frontZ(9, [0, 1, 5])).toBe(9);
	});

	it('still rises when tied for the top (ties are not "above")', () => {
		expect(frontZ(5, [5, 5])).toBe(6);
	});

	it('returns self when there are no other blocks', () => {
		expect(frontZ(3, [])).toBe(3);
	});

	it('ignores non-finite sibling values', () => {
		expect(frontZ(0, [NaN, 2, Infinity])).toBe(3);
	});

	it('treats a non-finite self as 0', () => {
		expect(frontZ(NaN, [1, 2])).toBe(3);
		expect(frontZ(NaN, [])).toBe(0);
	});
});

describe('backZ', () => {
	it('lands one below the lowest sibling', () => {
		expect(backZ(0, [0, 1, 5])).toBe(-1);
		expect(backZ(4, [3])).toBe(2);
	});

	it('is a no-op when already the unique bottom', () => {
		expect(backZ(-3, [0, 1, 5])).toBe(-3);
	});

	it('still sinks when tied for the bottom', () => {
		expect(backZ(0, [0, 0])).toBe(-1);
	});

	it('returns self when there are no other blocks', () => {
		expect(backZ(2, [])).toBe(2);
	});

	it('ignores non-finite sibling values', () => {
		// -Infinity/NaN are dropped, leaving [2]; self 3 is above it, so it sinks to 1.
		expect(backZ(3, [NaN, 2, -Infinity])).toBe(1);
	});
});
