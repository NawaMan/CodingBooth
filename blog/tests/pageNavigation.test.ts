import { describe, expect, it } from 'vitest';
import { getPageNavigation, visiblePages, type Page } from '$lib/utils/navigate';

// The deck's LINEAR ORDER — what →/Space page through and the TOC lists. A hidden
// slide (an appendix) is a real, prerendered route that is nonetheless not part of
// that order, and this is the one module that decides so: paging, the Table of
// Contents and the presenter console's next-slide preview all read it from here.

const deck: Array<Page> = [
	{ path: 'title.html',    title: 'Title' },
	{ path: 'heap.html',     title: 'Heap' },
	{ path: 'gc.html',       title: 'GC', hidden: true },   // the appendix
	{ path: 'threads.html',  title: 'Threads' },
	{ path: 'thanks.html',   title: 'Thanks' }
];

describe('visiblePages', () => {
	it('drops the hidden slides and keeps the rest in order', () => {
		expect(visiblePages(deck).map((p) => p.path))
			.toEqual(['title.html', 'heap.html', 'threads.html', 'thanks.html']);
	});

	it('is identity on a deck with no appendices', () => {
		const plain: Array<Page> = [{ path: 'a.html', title: 'A' }];
		expect(visiblePages(plain)).toEqual(plain);
	});
});

describe('getPageNavigation — paging steps OVER an appendix', () => {
	// The heart of it: heap → threads, as if gc.html were not in the file. A straight
	// run-through of the deck can never wander into the backup demo.
	it('skips a hidden slide when paging forward', () => {
		const nav = getPageNavigation(deck, 'heap.html', './');
		expect(nav.next).toBe('./threads.html');
	});

	it('skips a hidden slide when paging back', () => {
		const nav = getPageNavigation(deck, 'threads.html', './');
		expect(nav.prev).toBe('./heap.html');
	});

	it('keeps FIRST and LAST pointing at visible ends', () => {
		const nav = getPageNavigation(deck, 'heap.html', './');
		expect(nav.first).toBe('./title.html');
		expect(nav.last).toBe('./thanks.html');
	});

	// An appendix is LEFT by returning to whoever called it (AppendixPage), so it has
	// no neighbours of its own to offer. Being handed the deck's first slide as a
	// "next" would read as working navigation on a slide that has none.
	it('gives a hidden slide no navigation at all', () => {
		expect(getPageNavigation(deck, 'gc.html', './'))
			.toEqual({ first: undefined, last: undefined, prev: undefined, next: undefined });
	});

	it('gives a route missing from pages.ts no navigation either', () => {
		expect(getPageNavigation(deck, 'not-listed.html', './'))
			.toEqual({ first: undefined, last: undefined, prev: undefined, next: undefined });
	});
});

describe('getPageNavigation — the ordinary deck is unchanged', () => {
	const plain: Array<Page> = [
		{ path: 'a.html', title: 'A' },
		{ path: 'b.html', title: 'B' },
		{ path: 'c.html', title: 'C' }
	];

	it('pages through neighbours', () => {
		expect(getPageNavigation(plain, 'b.html', './'))
			.toEqual({ first: './a.html', last: './c.html', prev: './a.html', next: './c.html' });
	});

	it('has no prev on the first slide and no next on the last', () => {
		const first = getPageNavigation(plain, 'a.html', './');
		expect(first.prev).toBeUndefined();
		expect(first.first).toBeUndefined();   // already there
		expect(first.next).toBe('./b.html');

		const last = getPageNavigation(plain, 'c.html', './');
		expect(last.next).toBeUndefined();
		expect(last.last).toBeUndefined();     // already there
		expect(last.prev).toBe('./b.html');
	});
});
