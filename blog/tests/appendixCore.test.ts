import { describe, expect, it } from 'vitest';
import {
	KIND_OUT,
	KIND_STEP,
	RETURN_PARAM,
	appendixHref,
	appendixKinds,
	appendixNavigation,
	appendixRun,
	carryReturn,
	carryReturnThrough,
	isSlidePath,
	readReturnParam,
	returnHref,
	slidePathOf,
	type RunPage
} from '$lib/utils/appendixCore';

// The pure layer behind AppendixPage / AppendixLink. The asymmetry it encodes is
// the thing worth testing: `to` (which appendix) is AUTHOR input and passes
// through, while `?return=` arrives in the URL where anyone can write it — so it
// is validated, and a refused address degrades to "no address" rather than to a
// navigation somewhere surprising.

const q = (s: string) => new URL(`http://x/slides/appendix.html${s}`).searchParams;

describe('isSlidePath — what we are willing to navigate to', () => {
	it('accepts a plain in-deck slide name', () => {
		expect(isSlidePath('heap-layout.html')).toBe(true);
		expect(isSlidePath('title.html')).toBe(true);
		expect(isSlidePath('a')).toBe(true);
	});

	it('refuses anything that could leave the deck folder', () => {
		for (const hostile of [
			'../../etc/passwd',       // traversal
			'..',
			'a/b.html',               // any slash at all
			'//evil.example',         // protocol-relative — a slash-slash host
			'https://evil.example',
			'http://evil.example',
			'javascript:alert(1)',    // a scheme is not a slide
			'\\evil'
		])
			expect(isSlidePath(hostile)).toBe(false);
	});

	it('refuses junk, absent, and the absurdly long', () => {
		expect(isSlidePath(null)).toBe(false);
		expect(isSlidePath(undefined)).toBe(false);
		expect(isSlidePath('')).toBe(false);
		expect(isSlidePath('has space.html')).toBe(false);
		expect(isSlidePath('?x=1')).toBe(false);
		expect(isSlidePath('a#frag')).toBe(false);
		expect(isSlidePath('x'.repeat(200))).toBe(false);
	});
});

describe('readReturnParam — the return address, as untrusted input', () => {
	it('reads a valid return address', () => {
		expect(readReturnParam(q('?return=heap-layout.html'))).toBe('heap-layout.html');
	});

	it('tolerates surrounding whitespace (a hand-typed or wrapped URL)', () => {
		expect(readReturnParam(q('?return=%20heap.html%20'))).toBe('heap.html');
	});

	// An absent address is the ordinary case — a direct link or a bookmark — so it
	// is null, not an error, and the page degrades to its deck fallback.
	it('treats an absent return as no address', () => {
		expect(readReturnParam(q(''))).toBe(null);
		expect(readReturnParam(q('?other=1'))).toBe(null);
		expect(readReturnParam(null)).toBe(null);
		expect(readReturnParam(undefined)).toBe(null);
	});

	// The point of the module: a hostile address is INDISTINGUISHABLE from none, so
	// there is exactly one degraded path to render — never a RETURN control that
	// walks the audience off the deck.
	it('refuses an address that would leave the deck, degrading to no address', () => {
		expect(readReturnParam(q('?return=https://evil.example'))).toBe(null);
		expect(readReturnParam(q('?return=../../secrets.html'))).toBe(null);
		expect(readReturnParam(q('?return=//evil.example'))).toBe(null);
		expect(readReturnParam(q('?return='))).toBe(null);
	});
});

describe('slidePathOf — the caller stamping its own name', () => {
	it('takes the slide name out of a pathname', () => {
		expect(slidePathOf('/slides/heap-layout.html')).toBe('heap-layout.html');
		expect(slidePathOf('/deck/sub/title.html')).toBe('title.html');
	});

	it('ignores a trailing slash (the deck serves both shapes)', () => {
		expect(slidePathOf('/slides/heap-layout.html/')).toBe('heap-layout.html');
	});

	it('has no answer for a pathname with no slide in it', () => {
		expect(slidePathOf('/')).toBe(null);
		expect(slidePathOf('')).toBe(null);
		expect(slidePathOf(null)).toBe(null);
	});
});

describe('appendixHref — the jump in, carrying the way back', () => {
	it('stamps the caller as the return address', () => {
		expect(appendixHref('appendix-gc.html', 'heap-layout.html'))
			.toBe('./appendix-gc.html?return=heap-layout.html');
		expect(RETURN_PARAM).toBe('return');
	});

	// Not knowing where we are is not a reason to break the link — the appendix
	// still opens, it just shows its DECK fallback instead of a RETURN.
	it('still links when the caller has no name to stamp', () => {
		expect(appendixHref('appendix-gc.html', null)).toBe('./appendix-gc.html');
		expect(appendixHref('appendix-gc.html', '../elsewhere')).toBe('./appendix-gc.html');
	});
});

describe('returnHref — the jump back', () => {
	it('resolves a valid address within the deck', () => {
		expect(returnHref('heap-layout.html')).toBe('./heap-layout.html');
	});

	it('has no href for a missing or refused address', () => {
		expect(returnHref(null)).toBe(null);
		expect(returnHref(undefined)).toBe(null);
		expect(returnHref('https://evil.example')).toBe(null);
	});
});

// An appendix is a CHAPTER: contiguous hidden slides you page through like a book's
// back matter. The run is that chapter, and its EDGES are the way out.
const deck: Array<RunPage> = [
	{ path: 'title.html' },
	{ path: 'heap.html' },
	{ path: 'gc-1.html', hidden: true },      // ┐ one appendix,
	{ path: 'gc-2.html', hidden: true },      // ┘ two slides
	{ path: 'threads.html' },
	{ path: 'barrier.html', hidden: true },   // a second, separate appendix
	{ path: 'thanks.html' }
];

describe('appendixRun — the chapter a slide belongs to', () => {
	it('gathers the contiguous hidden slides around this one', () => {
		expect(appendixRun(deck, 'gc-1.html').map((p) => p.path)).toEqual(['gc-1.html', 'gc-2.html']);
		expect(appendixRun(deck, 'gc-2.html').map((p) => p.path)).toEqual(['gc-1.html', 'gc-2.html']);
	});

	// Separated by a visible slide, so it is a DIFFERENT appendix — runs must not
	// merge across the body of the deck, or paging off the end of one would land in
	// the middle of another.
	it('does not reach across a visible slide into another appendix', () => {
		expect(appendixRun(deck, 'barrier.html').map((p) => p.path)).toEqual(['barrier.html']);
	});

	// An appendix that is NOT hidden lives in the deck's normal flow (a book's back
	// matter you can simply page into). It has no run of its own: its neighbours are
	// the deck's, so the deck's own navigation applies.
	it('is empty for a slide that is not hidden', () => {
		expect(appendixRun(deck, 'heap.html')).toEqual([]);
		expect(appendixRun(deck, 'not-listed.html')).toEqual([]);
	});
});

describe('appendixNavigation — paging a chapter, and walking out of it', () => {
	const run = appendixRun(deck, 'gc-1.html');
	const exit = './heap.html';   // the caller

	it('pages within the run, carrying the return address with it', () => {
		const nav = appendixNavigation(run, 'gc-1.html', exit, 'heap.html');
		expect(nav.next).toBe('./gc-2.html?return=heap.html');
	});

	// The heart of the design: off the END of the appendix is the way BACK. Since the
	// NavigationBar drives → and Space from `next`, this is also what makes the
	// ordinary forward march return from an appendix, with no key of its own.
	it('leaves the appendix by paging forward off its last slide', () => {
		const nav = appendixNavigation(run, 'gc-2.html', exit, 'heap.html');
		expect(nav.next).toBe('./heap.html');
	});

	it('leaves the appendix by paging back off its first slide', () => {
		const nav = appendixNavigation(run, 'gc-1.html', exit, 'heap.html');
		expect(nav.prev).toBe('./heap.html');
	});

	// FIRST/LAST are the APPENDIX's ends, not the deck's: inside a chapter, "last"
	// means its last page. Jumping to the end of the deck from here would land the
	// audience on a slide the talk has not reached.
	it('bounds FIRST and LAST to the run', () => {
		const nav = appendixNavigation(run, 'gc-2.html', exit, 'heap.html');
		expect(nav.first).toBe('./gc-1.html?return=heap.html');
		expect(nav.last).toBeUndefined();          // already on it
		expect(appendixNavigation(run, 'gc-1.html', exit, 'heap.html').last)
			.toBe('./gc-2.html?return=heap.html');
	});

	// Reached cold (a bookmark), the exit is the deck rather than a caller — but it is
	// still an exit, so the run's edges still lead out of it.
	it('with no caller, the edges lead to the deck', () => {
		const nav = appendixNavigation(run, 'gc-2.html', './title.html', null);
		expect(nav.next).toBe('./title.html');
		expect(nav.first).toBe('./gc-1.html');   // nothing to carry
	});

	it('has nothing to say about a slide outside the run', () => {
		expect(appendixNavigation(run, 'threads.html', exit, 'heap.html'))
			.toEqual({ first: undefined, last: undefined, prev: undefined, next: undefined });
	});
});

describe('appendixKinds — what the motion says', () => {
	const run = appendixRun(deck, 'gc-1.html');   // gc-1 → gc-2

	// The vertical axis means one thing only: entering and leaving the talk. So a step
	// that stays INSIDE the appendix is sideways (you are reading), and a step off
	// either end is the appendix closing — whichever key does it.
	it('steps sideways within the appendix', () => {
		expect(appendixKinds(run, 'gc-1.html').next).toBe(KIND_STEP);
		expect(appendixKinds(run, 'gc-2.html').prev).toBe(KIND_STEP);
	});

	it('lifts away at either end, regardless of the direction travelled', () => {
		expect(appendixKinds(run, 'gc-2.html').next).toBe(KIND_OUT);   // off the end, forward
		expect(appendixKinds(run, 'gc-1.html').prev).toBe(KIND_OUT);   // off the front, back
	});

	// A one-slide appendix is all edge: both ways out of it are ways out.
	it('a single-slide appendix leaves in both directions', () => {
		const solo = appendixRun(deck, 'barrier.html');
		expect(appendixKinds(solo, 'barrier.html')).toEqual({ next: KIND_OUT, prev: KIND_OUT });
	});
});

describe('carryReturn — the address travels with every link', () => {
	it('stamps the address onto a link', () => {
		expect(carryReturn('./gc-2.html', 'heap.html')).toBe('./gc-2.html?return=heap.html');
	});

	it('leaves a link alone when there is no address, or it already carries one', () => {
		expect(carryReturn('./gc-2.html', null)).toBe('./gc-2.html');
		expect(carryReturn('./gc-2.html', '../evil')).toBe('./gc-2.html');
		expect(carryReturn('./gc-2.html?return=x.html', 'heap.html')).toBe('./gc-2.html?return=x.html');
	});

	it('joins an existing query with & rather than a second ?', () => {
		expect(carryReturn('./gc-2.html?present', 'heap.html')).toBe('./gc-2.html?present&return=heap.html');
	});

	// The in-flow case: an appendix that is not hidden pages with the DECK's own
	// navigation, and the address has to survive that paging too.
	it('threads the address through a whole navigation set', () => {
		const nav = { first: './a.html', last: './d.html', prev: './b.html', next: undefined };
		expect(carryReturnThrough(nav, 'heap.html')).toEqual({
			first: './a.html?return=heap.html',
			last:  './d.html?return=heap.html',
			prev:  './b.html?return=heap.html',
			next:  undefined
		});
	});
});
