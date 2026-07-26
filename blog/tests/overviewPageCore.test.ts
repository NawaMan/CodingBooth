import { describe, expect, it } from 'vitest';
import {
	currentTileDirection,
	filterOverviewTiles,
	gridColumnCount,
	gridRowsPerPage,
	isTypingTarget,
	mountedTiles,
	moveFocus,
	overviewGridKeyIntent,
	overviewPageKeyIntent,
	overviewPageTiles,
	tileScale
} from '$lib/utils/overviewPageCore';
import type { Page } from '$lib/utils/navigate';

// The pure layer behind the all-slides grid. Three decisions live here and each
// one has a way of going quietly wrong in the browser: a scale that can turn into
// NaN (a tile rendered at `scale(NaN)` is simply blank), a tile list that must
// agree with the deck's own idea of its linear order, and a key press that must
// not fire while the speaker is typing into the presenter's timer box.

const deck: Array<Page> = [
	{ path: 'title.html', title: 'Title' },
	{ path: 'intro.html', title: 'Intro' },
	{ path: 'appendix-gc.html', title: 'Appendix — GC', hidden: true },
	{ path: 'outro.html', title: 'Outro' }
];

// A KeyboardEvent is all overviewPageKeyIntent reads, so build the shape it reads
// rather than dispatching into a DOM.
function key(init: Partial<KeyboardEvent> & { key: string }): KeyboardEvent {
	return {
		defaultPrevented: false,
		ctrlKey: false,
		metaKey: false,
		altKey: false,
		target: null,
		...init
	} as KeyboardEvent;
}

const el = (tagName: string, isContentEditable = false) =>
	({ tagName, isContentEditable }) as unknown as EventTarget;

describe('tileScale — fit a slide into its box, or render nothing', () => {
	it('fits by the binding axis (the smaller ratio), so the slide is never cropped', () => {
		// A 480x270 box is exactly 1/4 of the canvas on both axes.
		expect(tileScale(480, 270, 1920, 1080)).toBe(0.25);
		// A box that is wide for its height binds on HEIGHT.
		expect(tileScale(1920, 270, 1920, 1080)).toBe(0.25);
		// ...and one that is tall for its width binds on WIDTH.
		expect(tileScale(480, 1080, 1920, 1080)).toBe(0.25);
	});

	it('returns 0 for an unmeasured box rather than a scale', () => {
		// clientWidth/clientHeight are 0 until layout runs — the tile is briefly
		// zero-sized, which the next tick fixes. That is recoverable; NaN is not.
		expect(tileScale(0, 0, 1920, 1080)).toBe(0);
		expect(tileScale(480, 0, 1920, 1080)).toBe(0);
	});

	it('is total — junk in, a drawable number out (never NaN)', () => {
		const junk = [NaN, Infinity, -Infinity, -10];
		for (const n of junk) {
			expect(tileScale(n, 270, 1920, 1080)).not.toBeNaN();
			expect(tileScale(480, n, 1920, 1080)).not.toBeNaN();
			// A zero-size canvas would otherwise divide by zero.
			expect(tileScale(480, 270, n, 1080)).not.toBeNaN();
			expect(tileScale(480, 270, 1920, n)).not.toBeNaN();
		}
		expect(tileScale(NaN, NaN, NaN, NaN)).toBe(0);
	});
});

describe('overviewPageTiles — the deck as a grid', () => {
	it('drops hidden appendices and numbers what remains 1..n', () => {
		const tiles = overviewPageTiles(deck, 'intro.html');
		// The appendix is a real slide but not part of the forward march, so the
		// grid — which IS browsing — does not offer it. Same list the ToC lists.
		expect(tiles.map((t) => t.path)).toEqual(['title.html', 'intro.html', 'outro.html']);
		// Numbering counts the LISTED pages, so it matches what paging from the
		// start would give you — the appendix does not consume a number.
		expect(tiles.map((t) => t.number)).toEqual([1, 2, 3]);
		expect(tiles.map((t) => t.title)).toEqual(['Title', 'Intro', 'Outro']);
	});

	it('previews each slide with ?clean, relative to the current document', () => {
		const tiles = overviewPageTiles(deck, '');
		// `?clean` is the deck's own no-chrome render, so a tile shows the slide and
		// not a nav bar and another OVERVIEW button. Relative, so it resolves under
		// whatever prefix the deck is served from.
		expect(tiles[0].src).toBe('./title.html?clean');
		expect(tiles[2].src).toBe('./outro.html?clean');
	});

	it('marks exactly the slide we are standing on', () => {
		const tiles = overviewPageTiles(deck, 'outro.html');
		expect(tiles.filter((t) => t.isCurrent).map((t) => t.path)).toEqual(['outro.html']);
	});

	it('marks nothing when the current path is unknown, rather than guessing', () => {
		// Standing on a hidden appendix, or on a path that is not in this deck.
		expect(overviewPageTiles(deck, 'appendix-gc.html').some((t) => t.isCurrent)).toBe(false);
		expect(overviewPageTiles(deck, 'nowhere.html').some((t) => t.isCurrent)).toBe(false);
	});

	it('is total — a junk pages array yields no tiles rather than throwing', () => {
		expect(overviewPageTiles([], 'x.html')).toEqual([]);
		expect(overviewPageTiles(null as unknown as Array<Page>, 'x.html')).toEqual([]);
		expect(overviewPageTiles(undefined as unknown as Array<Page>, '')).toEqual([]);
	});
});

describe('filterOverviewTiles — title, file name, page number as strings', () => {
	const tiles = overviewPageTiles(
		[
			{ path: 'title.html', title: 'Title' },
			{ path: 'intro.html', title: 'Intro' },
			{ path: 'backpressure-deep.html', title: 'Backpressure Deep Dive' },
			{ path: 'outro.html', title: 'Outro' },
			{ path: 'slide-10.html', title: 'Ten' },
			{ path: 'slide-12.html', title: 'Twelve' }
		],
		'intro.html'
	);

	it('returns the full list for an empty or whitespace query', () => {
		expect(filterOverviewTiles(tiles, '')).toEqual(tiles);
		expect(filterOverviewTiles(tiles, '   ')).toEqual(tiles);
	});

	it('matches title case-insensitively', () => {
		expect(filterOverviewTiles(tiles, 'deep dive').map((t) => t.path)).toEqual([
			'backpressure-deep.html'
		]);
		expect(filterOverviewTiles(tiles, 'TITLE').map((t) => t.path)).toEqual(['title.html']);
	});

	it('matches file name (path and stem without .html)', () => {
		expect(filterOverviewTiles(tiles, 'intro.html').map((t) => t.path)).toEqual(['intro.html']);
		expect(filterOverviewTiles(tiles, 'backpressure-deep').map((t) => t.path)).toEqual([
			'backpressure-deep.html'
		]);
	});

	it('matches page number as a substring of the number string', () => {
		// "1" hits 1 (Title), 5 (slide-10 → number 5), and 6 (slide-12 → number 6)?
		// Numbers are 1..6 in list order: title=1, intro=2, backpressure=3, outro=4, ten=5, twelve=6.
		// So "1" matches only page 1. "2" matches page 2 only in this deck of 6.
		// Build a denser case for multi-digit substring:
		const dense = overviewPageTiles(
			Array.from({ length: 15 }, (_, i) => ({
				path: `p${i + 1}.html`,
				title: `P${i + 1}`
			})),
			''
		);
		// "1" matches 1, 10, 11, 12, 13, 14, 15
		expect(filterOverviewTiles(dense, '1').map((t) => t.number)).toEqual([
			1, 10, 11, 12, 13, 14, 15
		]);
		expect(filterOverviewTiles(dense, '12').map((t) => t.number)).toEqual([12]);
	});

	it('keeps deck order and original numbers (does not renumber filtered hits)', () => {
		const hits = filterOverviewTiles(tiles, 'o'); // Outro, intro? Intro has no o... "Intro" has no 'o'? I-n-t-r-o yes
		// title "Intro", "Outro", path might also match
		expect(hits.every((t, _i, arr) => {
			const full = tiles.find((x) => x.path === t.path);
			return full && full.number === t.number;
		})).toBe(true);
		// Order is deck order, not relevance
		const idx = hits.map((h) => tiles.findIndex((t) => t.path === h.path));
		expect(idx).toEqual([...idx].sort((a, b) => a - b));
	});

	it('is total — junk tiles or query do not throw', () => {
		expect(filterOverviewTiles(null as unknown as typeof tiles, 'x')).toEqual([]);
		expect(filterOverviewTiles(undefined as unknown as typeof tiles, 'x')).toEqual([]);
		// @ts-expect-error total guard
		expect(filterOverviewTiles(tiles, null)).toEqual(tiles);
		expect(
			filterOverviewTiles([{ path: 'x.html', title: undefined, number: 1 } as never], 'x').map(
				(t) => t.path
			)
		).toEqual(['x.html']);
	});
});

describe('isTypingTarget — narrower than stepKeys, deliberately', () => {
	it('counts text fields, where `o` is a letter the user meant', () => {
		expect(isTypingTarget(el('INPUT'))).toBe(true);
		expect(isTypingTarget(el('TEXTAREA'))).toBe(true);
		expect(isTypingTarget(el('SELECT'))).toBe(true);
		expect(isTypingTarget(el('DIV', true))).toBe(true); // contentEditable
	});

	it('does NOT count buttons and links — the difference that makes Escape work', () => {
		// stepKeys.isInteractiveTarget DOES count these, and rightly so: Space must
		// activate a focused button instead of paging. Borrowing that guard here
		// would be a bug — with the grid open the focus is ON a tile button, so
		// Escape would be unable to close the overlay it just opened.
		expect(isTypingTarget(el('BUTTON'))).toBe(false);
		expect(isTypingTarget(el('A'))).toBe(false);
		expect(isTypingTarget(null)).toBe(false);
	});
});

describe('overviewPageKeyIntent — what a key press means to the grid', () => {
	it('`o` opens it and closes it again', () => {
		expect(overviewPageKeyIntent(key({ key: 'o' }), false)).toBe('open');
		expect(overviewPageKeyIntent(key({ key: 'o' }), true)).toBe('close');
		expect(overviewPageKeyIntent(key({ key: 'O' }), false)).toBe('open'); // caps lock
	});

	it('Escape only ever closes, and only when the grid is open', () => {
		expect(overviewPageKeyIntent(key({ key: 'Escape' }), true)).toBe('close');
		// Left alone when the grid is shut, so the deck's OTHER Escape listeners
		// (the ToC, SizeMode, Annotate) still get their key.
		expect(overviewPageKeyIntent(key({ key: 'Escape' }), false)).toBe('ignore');
	});

	it('keeps its hands off the browser’s own chords', () => {
		// Ctrl/Cmd+O is "open file". A slide deck stealing it would be hostile.
		expect(overviewPageKeyIntent(key({ key: 'o', ctrlKey: true }), false)).toBe('ignore');
		expect(overviewPageKeyIntent(key({ key: 'o', metaKey: true }), false)).toBe('ignore');
		expect(overviewPageKeyIntent(key({ key: 'o', altKey: true }), false)).toBe('ignore');
	});

	it('stays out of the way while the speaker is typing', () => {
		// The presenter console's timer box, a DataTable's search field.
		expect(overviewPageKeyIntent(key({ key: 'o', target: el('INPUT') }), false)).toBe('ignore');
		expect(overviewPageKeyIntent(key({ key: 'Escape', target: el('INPUT') }), true)).toBe('ignore');
	});

	it('closes on Escape even when another listener already handled it', () => {
		// Order-independence, and the bug that made it necessary: the ToC used to
		// preventDefault EVERY Escape (open or shut), and it listens first, so a grid
		// that deferred to an already-handled Escape could never close itself.
		// Escape is judged on OUR state alone — like spaceIntent, whichever listener
		// the browser calls first, each acts only on the intent that is its own.
		expect(overviewPageKeyIntent(key({ key: 'Escape', defaultPrevented: true }), true)).toBe(
			'close'
		);
		// Still not ours when the grid is shut, handled or not.
		expect(overviewPageKeyIntent(key({ key: 'Escape', defaultPrevented: true }), false)).toBe(
			'ignore'
		);
	});

	it('ignores a LETTER someone else has already handled, and every other key', () => {
		// The letter does defer: if something else acted on this `o`, it is not ours
		// to reinterpret. (Escape is the deliberate exception, above.)
		expect(overviewPageKeyIntent(key({ key: 'o', defaultPrevented: true }), false)).toBe('ignore');
		expect(overviewPageKeyIntent(key({ key: 'ArrowRight' }), false)).toBe('ignore');
		expect(overviewPageKeyIntent(key({ key: ' ' }), false)).toBe('ignore');
	});
});

describe('mountedTiles — which tiles hold a live document', () => {
	it('always mounts the current slide, so the grid opens already showing it', () => {
		expect([...mountedTiles(new Set(), 3)]).toEqual([3]);
	});

	it('keeps every tile that has been seen — mounting is one-way', () => {
		// Unmounting on scroll-out would reload (and re-boot) a slide every time it
		// drifted past. Keeping it costs one already-parsed document.
		const seen = new Set([1, 2, 5]);
		expect([...mountedTiles(seen, 2)].sort((a, b) => a - b)).toEqual([1, 2, 5]);
	});

	it('does not mutate the set it is given', () => {
		const seen = new Set([1]);
		mountedTiles(seen, 9);
		expect([...seen]).toEqual([1]);
	});

	it('is total — no current slide (0) and junk numbers add nothing', () => {
		expect([...mountedTiles(new Set([1]), 0)]).toEqual([1]);
		expect([...mountedTiles(new Set([NaN]), NaN)]).toEqual([]);
	});
});

describe('currentTileDirection — which way to scroll for the current slide', () => {
	const grid = { top: 100, bottom: 500 };

	it('is "unknown" when there is no current tile (no match, or not yet mounted)', () => {
		expect(currentTileDirection(grid, null)).toBe('unknown');
	});

	it('is "visible" when the tile is fully inside the viewport', () => {
		expect(currentTileDirection(grid, { top: 150, bottom: 250 })).toBe('visible');
	});

	it('is "visible" when the tile only PARTLY overlaps — nothing to scroll for', () => {
		expect(currentTileDirection(grid, { top: 450, bottom: 550 })).toBe('visible'); // spills below
		expect(currentTileDirection(grid, { top: 50, bottom: 150 })).toBe('visible'); // spills above
	});

	it('is "above" once the tile has fully scrolled past the top edge', () => {
		expect(currentTileDirection(grid, { top: -200, bottom: 50 })).toBe('above');
	});

	it('is "below" once the tile has fully scrolled past the bottom edge', () => {
		expect(currentTileDirection(grid, { top: 550, bottom: 700 })).toBe('below');
	});

	it('treats a tile exactly flush with an edge as still visible (boundary, not past it)', () => {
		expect(currentTileDirection(grid, { top: 500, bottom: 600 })).toBe('visible');
		expect(currentTileDirection(grid, { top: 0, bottom: 100 })).toBe('visible');
	});
});

describe('gridColumnCount — how many tiles share the first row', () => {
	it('counts the leading tiles that share the first top edge', () => {
		expect(gridColumnCount([10, 10, 10, 10, 400, 400, 400, 400])).toBe(4);
	});

	it('tolerates a few px of sub-pixel jitter between same-row tiles', () => {
		expect(gridColumnCount([10, 10.4, 9.6, 400])).toBe(3);
	});

	it('is 1 for a single column (each tile its own row)', () => {
		expect(gridColumnCount([10, 200, 390])).toBe(1);
	});

	it('is total-safe: an empty list is still 1, never 0', () => {
		expect(gridColumnCount([])).toBe(1);
	});
});

describe('gridRowsPerPage — PageUp/PageDown step size', () => {
	it('floors to whole rows that fit the visible height', () => {
		expect(gridRowsPerPage(1000, 300)).toBe(3);
	});

	it('is never less than 1, even in a viewport shorter than one row', () => {
		expect(gridRowsPerPage(100, 300)).toBe(1);
	});

	it('falls back to 1 rather than dividing by zero or NaN', () => {
		expect(gridRowsPerPage(1000, 0)).toBe(1);
		expect(gridRowsPerPage(1000, NaN)).toBe(1);
		expect(gridRowsPerPage(NaN, 300)).toBe(1);
	});
});

describe('moveFocus — roving keyboard focus over the grid', () => {
	// 12 tiles, 4 columns (3 rows), 2 rows fit the visible viewport per page.
	const total = 12;
	const cols = 4;
	const rowsPerPage = 2;

	it('left/right step by one, clamped at the ends (no wraparound)', () => {
		expect(moveFocus(5, total, cols, rowsPerPage, 'right')).toBe(6);
		expect(moveFocus(5, total, cols, rowsPerPage, 'left')).toBe(4);
		expect(moveFocus(1, total, cols, rowsPerPage, 'left')).toBe(1);
		expect(moveFocus(total, total, cols, rowsPerPage, 'right')).toBe(total);
	});

	it('up/down step by a whole row (the column count)', () => {
		expect(moveFocus(6, total, cols, rowsPerPage, 'down')).toBe(10);
		expect(moveFocus(6, total, cols, rowsPerPage, 'up')).toBe(2);
	});

	it('up/down clamp into range rather than landing off-grid', () => {
		expect(moveFocus(2, total, cols, rowsPerPage, 'up')).toBe(1); // 2-4 = -2 → clamped
		expect(moveFocus(11, total, cols, rowsPerPage, 'down')).toBe(total); // 11+4=15 → clamped
	});

	it('pageUp/pageDown step by a whole page (columns * rowsPerPage)', () => {
		expect(moveFocus(9, total, cols, rowsPerPage, 'pageDown')).toBe(total); // 9+8=17 → clamped
		expect(moveFocus(9, total, cols, rowsPerPage, 'pageUp')).toBe(1); // 9-8=1
	});

	it('first/last (Home/End) jump straight to the ends regardless of position', () => {
		expect(moveFocus(7, total, cols, rowsPerPage, 'first')).toBe(1);
		expect(moveFocus(7, total, cols, rowsPerPage, 'last')).toBe(total);
	});

	it('is total-safe: an empty deck yields 0, never a fabricated tile number', () => {
		expect(moveFocus(1, 0, cols, rowsPerPage, 'right')).toBe(0);
	});
});

describe('overviewGridKeyIntent — what a key means to the roving grid', () => {
	const el = (tagName: string) => ({ tagName, isContentEditable: false }) as unknown as EventTarget;
	const key = (init: Partial<KeyboardEvent> & { key: string }): KeyboardEvent =>
		({
			key: init.key,
			ctrlKey: init.ctrlKey ?? false,
			metaKey: init.metaKey ?? false,
			altKey: init.altKey ?? false,
			shiftKey: init.shiftKey ?? false,
			target: init.target ?? null
		}) as KeyboardEvent;

	it('maps the arrows, Home/End and PageUp/PageDown to movement intents', () => {
		expect(overviewGridKeyIntent(key({ key: 'ArrowLeft' }))).toBe('left');
		expect(overviewGridKeyIntent(key({ key: 'ArrowRight' }))).toBe('right');
		expect(overviewGridKeyIntent(key({ key: 'ArrowUp' }))).toBe('up');
		expect(overviewGridKeyIntent(key({ key: 'ArrowDown' }))).toBe('down');
		expect(overviewGridKeyIntent(key({ key: 'Home' }))).toBe('first');
		expect(overviewGridKeyIntent(key({ key: 'End' }))).toBe('last');
		expect(overviewGridKeyIntent(key({ key: 'PageUp' }))).toBe('pageUp');
		expect(overviewGridKeyIntent(key({ key: 'PageDown' }))).toBe('pageDown');
	});

	it('Enter commits; Space goes to the current slide — neither is movement', () => {
		expect(overviewGridKeyIntent(key({ key: 'Enter' }))).toBe('commit');
		expect(overviewGridKeyIntent(key({ key: ' ' }))).toBe('toCurrent');
	});

	it('ignores an unrelated key', () => {
		expect(overviewGridKeyIntent(key({ key: 'a' }))).toBe('ignore');
	});

	it('leaves a modified chord alone — Cmd/Ctrl/Alt belong to the browser or OS', () => {
		expect(overviewGridKeyIntent(key({ key: 'ArrowLeft', metaKey: true }))).toBe('ignore');
		expect(overviewGridKeyIntent(key({ key: 'ArrowRight', ctrlKey: true }))).toBe('ignore');
		expect(overviewGridKeyIntent(key({ key: 'Enter', altKey: true }))).toBe('ignore');
	});

	it('never fires while the caret is in a text field', () => {
		expect(overviewGridKeyIntent(key({ key: 'ArrowRight', target: el('INPUT') }))).toBe('ignore');
	});
});
