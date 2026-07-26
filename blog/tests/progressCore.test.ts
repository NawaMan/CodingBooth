import { describe, expect, it } from 'vitest';
import { currentSlidePath, progressOf } from '$lib/utils/progressCore';
import type { Page } from '$lib/utils/navigate';

const DECK: Array<Page> = [
	{ path: 'a.html', title: 'A' },
	{ path: 'b.html', title: 'B' },
	{ path: 'c.html', title: 'C' },
	{ path: 'd.html', title: 'D', hidden: true } // an appendix — not part of the march
];

describe('currentSlidePath', () => {
	it('takes the last path segment, tolerating the trailing slash', () => {
		expect(currentSlidePath('/geeklight/title.html/')).toBe('title.html');
		expect(currentSlidePath('/geeklight/title.html')).toBe('title.html');
		expect(currentSlidePath('title.html')).toBe('title.html');
	});

	it('is total — a non-string yields "" (matches nothing) rather than throwing', () => {
		expect(currentSlidePath(undefined)).toBe('');
		expect(currentSlidePath(null)).toBe('');
		expect(currentSlidePath(42)).toBe('');
		expect(currentSlidePath('/')).toBe('');
	});
});

describe('progressOf', () => {
	it('reports 1-based position, visible total, and a monotonic fraction', () => {
		expect(progressOf(DECK, 'a.html')).toEqual({
			index: 0, position: 1, total: 3, fraction: 1 / 3, present: true
		});
		expect(progressOf(DECK, 'c.html')).toEqual({
			index: 2, position: 3, total: 3, fraction: 1, present: true
		});
	});

	it('counts VISIBLE slides only — a hidden appendix is neither in the total nor present', () => {
		const p = progressOf(DECK, 'd.html');
		expect(p.total).toBe(3); // d is hidden, so the denominator stays 3
		expect(p.present).toBe(false);
		expect(p.fraction).toBe(0);
		expect(p.position).toBe(0);
	});

	it('an off-list route is not present and shows no progress', () => {
		expect(progressOf(DECK, 'ghost.html')).toEqual({
			index: -1, position: 0, total: 3, fraction: 0, present: false
		});
	});

	it('a single-slide deck reads as complete (1 / 1)', () => {
		const one: Array<Page> = [{ path: 'only.html', title: 'Only' }];
		expect(progressOf(one, 'only.html')).toEqual({
			index: 0, position: 1, total: 1, fraction: 1, present: true
		});
	});

	it('is total and NaN-safe on junk — no throw, no NaN', () => {
		for (const junk of [null, undefined, 'nope', 42, {}]) {
			const p = progressOf(junk, 'a.html');
			expect(p).toEqual({ index: -1, position: 0, total: 0, fraction: 0, present: false });
			expect(Number.isNaN(p.fraction)).toBe(false);
		}
		// junk elements in an otherwise real array are skipped, not dereferenced
		const messy = [null, { path: 'a.html', title: 'A' }, undefined] as unknown;
		expect(progressOf(messy, 'a.html')).toEqual({
			index: 0, position: 1, total: 1, fraction: 1, present: true
		});
		// a non-string path never throws
		expect(progressOf(DECK, undefined).present).toBe(false);
	});
});
