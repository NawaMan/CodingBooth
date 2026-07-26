// The pure half of the deck overview — the all-slides grid ("press O").
//
// The component owns the DOM: the iframes, the scroll container and the observer
// that mounts a tile as it comes into view. This module owns the arithmetic and
// the decisions, so both can be tested without a browser.
//
// Total, like the other *Core modules: an unmeasured box yields a scale of 0
// rather than NaN (a `transform: scale(NaN)` would blank the tile), a garbage
// pages array yields no tiles rather than throwing, and an unknown current path
// simply means no tile is marked current.
import { visiblePages, type Page } from '$lib/utils/navigate';

export interface OverviewTile {
	/** 1-based position in the deck's linear order — what the tile's label shows.
	    Counted over the LISTED pages, so it matches the number a viewer would get
	    by paging from the start, not the index in the raw array. */
	number: number;
	path: string;
	title: string;
	/** The preview URL. `?clean` is the deck's own "no chrome" render (SlideDeck
	    reads it), so a tile shows the slide and not a nav bar, a TOC and another
	    OVERVIEW button. Relative to the current slide document, so it resolves
	    whatever prefix the deck is served under — the same trick the presenter
	    console's previews use. */
	src: string;
	isCurrent: boolean;
}

/** Finite or the fallback — the NaN gate every measurement passes through. */
function finite(n: number, fallback = 0): number {
	return Number.isFinite(n) ? n : fallback;
}

/**
 * Fit a native-size slide into a measured box: the smaller of the two ratios, so
 * the whole slide is visible rather than cropped. The same exact-fit math the
 * presenter console's previews and the deck's FITTED mode use.
 *
 * Returns 0 while the box is still unmeasured — `clientWidth` is 0 before layout,
 * and a tile rendered at zero size is recoverable on the next tick, whereas one
 * rendered at NaN is not.
 */
export function tileScale(boxW: number, boxH: number, canvasW: number, canvasH: number): number {
	const bw = finite(boxW);
	const bh = finite(boxH);
	const cw = finite(canvasW);
	const ch = finite(canvasH);
	if (bw <= 0 || bh <= 0 || cw <= 0 || ch <= 0) return 0;
	return Math.min(bw / cw, bh / ch);
}

/**
 * The deck as tiles, in linear order.
 *
 * `hidden` appendices are dropped. The grid shows the deck's forward march — the
 * same list the Table of Contents lists and →/Space walk. An appendix is reached
 * from the slide that calls it, by name; it is deliberately not something you
 * stumble into while browsing, and the grid is browsing.
 */
export function overviewPageTiles(pages: Array<Page>, currentPath: string): OverviewTile[] {
	const listed = visiblePages(Array.isArray(pages) ? pages : []);
	return listed.map((p, i) => ({
		number: i + 1,
		path: p.path,
		title: p.title,
		src: `./${p.path}?clean`,
		isCurrent: p.path === currentPath
	}));
}

/**
 * Narrow the overview grid to tiles matching `query`.
 *
 * Case-insensitive substring match against title, file name (`path` and its stem
 * without `.html`), and the tile's page number treated as a string — so `"1"`
 * matches pages 1, 10, 11, 12… and `"intro"` matches both `intro.html` and a
 * title containing "Intro". An empty or whitespace query returns the full list
 * (the grid is unfiltered); junk input yields `[]` rather than throwing.
 *
 * Deliberately lighter than TOC full-text search: Overview filters what you can
 * already see on a tile (label + number + path), not body prose.
 */
export function filterOverviewTiles(tiles: OverviewTile[], query: string): OverviewTile[] {
	const list = Array.isArray(tiles) ? tiles : [];
	const q = (typeof query === 'string' ? query : '').trim().toLowerCase();
	if (!q) return list;
	return list.filter((t) => {
		if (!t) return false;
		const title = typeof t.title === 'string' ? t.title : '';
		const path = typeof t.path === 'string' ? t.path : '';
		const stem = path.replace(/\.html$/i, '');
		const num = String(t.number ?? '');
		return (
			title.toLowerCase().includes(q) ||
			path.toLowerCase().includes(q) ||
			stem.toLowerCase().includes(q) ||
			num.includes(q)
		);
	});
}

/**
 * Is this key press the user TYPING?
 *
 * Deliberately NARROWER than stepKeys' `isInteractiveTarget`, and the difference
 * is the point. That guard also counts BUTTON and A as interactive, which is
 * right for Space (Space activates a focused button — the deck must not page
 * instead). It is wrong for a letter key and for Escape: with the grid open the
 * focus IS on a tile button, so borrowing that guard would make Escape unable to
 * close the very overlay it opened.
 *
 * What must be protected is a text field — the presenter's timer box, a
 * DataTable's search — where `o` is a letter the user meant to type.
 */
export function isTypingTarget(t: EventTarget | null): boolean {
	const el = t as HTMLElement | null;
	if (!el) return false;
	if (el.isContentEditable) return true;
	return /^(INPUT|TEXTAREA|SELECT)$/.test(el.tagName ?? '');
}

export type OverviewIntent = 'open' | 'close' | 'ignore';

/**
 * What a key press means to the grid: `o` toggles it, Escape closes it.
 *
 * A modified press belongs to the browser, not to us — Ctrl/Cmd+O is "open
 * file", and stealing it would be a hostile thing for a slide deck to do.
 *
 * Escape only ever CLOSES, and only when the grid is open, so it stays available
 * to the other Escape listeners on the deck (the TOC, SizeMode, Annotate) when
 * the grid is not the thing on screen.
 */
export function overviewPageKeyIntent(e: KeyboardEvent, isOpen: boolean): OverviewIntent {
	if (e.ctrlKey || e.metaKey || e.altKey) return 'ignore';
	if (isTypingTarget(e.target)) return 'ignore';

	// Escape is judged on OUR OWN state, and deliberately NOT on defaultPrevented.
	//
	// Several listeners on the deck answer Escape (the ToC, Box, SizeMode, Annotate),
	// all of them on `window`, and which one the browser calls first is just mount
	// order. If the grid deferred to an already-handled Escape it would be unable to
	// close itself whenever one of those happened to be mounted earlier — which is
	// exactly the bug the ToC caused by preventDefault-ing every Escape, open or shut.
	//
	// So: order-independence, the same discipline spaceIntent gives Steps and
	// NavigationBar. Each listener acts only on the intent that belongs to it, judged
	// against its own state, and no listener can swallow the key out from under
	// another. An open grid is the topmost thing on the canvas; Escape closes it.
	if (e.key === 'Escape') return isOpen ? 'close' : 'ignore';

	// The letter, by contrast, DOES defer: if something else has already acted on
	// this `o`, it is not ours to reinterpret.
	if (e.defaultPrevented) return 'ignore';
	if (e.key === 'o' || e.key === 'O') return isOpen ? 'close' : 'open';
	return 'ignore';
}

/**
 * Which tiles should hold a live iframe?
 *
 * A tile is mounted once it has been seen near the viewport, and STAYS mounted —
 * mounting is one-way. Unmounting on scroll-out would make a tile reload (and
 * re-boot its slide) every time it drifted past, which is both slow and visibly
 * flickery; keeping it costs one already-parsed document.
 *
 * The current slide is always mounted, so the grid opens with the tile you are
 * standing on already showing rather than as a card that fills in a beat later.
 */
export function mountedTiles(seen: ReadonlySet<number>, currentNumber: number): Set<number> {
	const next = new Set<number>();
	for (const n of seen) if (Number.isFinite(n)) next.add(n);
	if (Number.isFinite(currentNumber) && currentNumber > 0) next.add(currentNumber);
	return next;
}

/** A `getBoundingClientRect()`-shaped rect, narrowed to the two edges this
    module actually compares — easy to build in a test without a DOM. */
export interface VerticalRect {
	top: number;
	bottom: number;
}

export type CurrentTileDirection = 'above' | 'below' | 'visible' | 'unknown';

/**
 * Where does the CURRENT tile sit relative to the grid's visible (scrolled)
 * viewport — so the CURRENT control can show a speaker which way to look, not
 * just that they should look.
 *
 * Compares EDGES, not a point: a tile that only partly overlaps the viewport
 * (its top above the fold, its bottom still showing) reads as 'visible' — it is
 * already on screen, nothing to scroll for. Only a tile that has fully scrolled
 * past one edge (its far edge crossed the near edge of the viewport) counts as
 * 'above' or 'below'.
 *
 * `tileRect` is `null` when there is no current slide yet (a fresh deck context,
 * or a `currentPath` that matches nothing) or the tile hasn't mounted its node —
 * 'unknown' either way, so the caller can hide the arrow rather than guess.
 */
export function currentTileDirection(
	gridRect: VerticalRect,
	tileRect: VerticalRect | null
): CurrentTileDirection {
	if (!tileRect) return 'unknown';
	if (tileRect.bottom < gridRect.top) return 'above';
	if (tileRect.top > gridRect.bottom) return 'below';
	return 'visible';
}

/**
 * Column count of a responsive grid (`repeat(auto-fill, minmax(...))`), read
 * back from actual tile positions rather than assumed — the column count isn't
 * a fixed constant, it depends on the window width. Counts how many LEADING
 * tiles (in render order, which is row-major) share the first tile's top edge.
 *
 * `epsilon` tolerates the sub-pixel jitter two same-row boxes can differ by.
 */
export function gridColumnCount(tileTops: number[], epsilon = 1): number {
	if (tileTops.length === 0) return 1;
	const first = tileTops[0];
	let n = 0;
	for (const top of tileTops) {
		if (Math.abs(top - first) > epsilon) break;
		n++;
	}
	return Math.max(1, n);
}

/** How many full rows fit in the grid's visible (scrolled) height — what
    PageUp/PageDown step by, one column-count's worth of tiles per row. A
    non-finite or non-positive `rowHeight` (one row total, nothing measured
    yet) falls back to a single row rather than dividing by zero. */
export function gridRowsPerPage(gridHeight: number, rowHeight: number): number {
	if (!Number.isFinite(gridHeight) || !Number.isFinite(rowHeight) || rowHeight <= 0) return 1;
	return Math.max(1, Math.floor(gridHeight / rowHeight));
}

export type GridNavIntent = 'left' | 'right' | 'up' | 'down' | 'first' | 'last' | 'pageUp' | 'pageDown';

/**
 * The new focused tile NUMBER (1-based) for a roving-focus move. Every
 * direction clamps into `[1, total]` rather than wrapping — Home/End already
 * cover "jump to an end", so a clamped Right at the last tile staying put reads
 * as "you're at the end", not a silent wrap back to tile 1.
 *
 * Total-safe: an empty deck (`total <= 0`) returns 0 — the caller's cue that
 * there is nothing to focus.
 */
export function moveFocus(
	current: number,
	total: number,
	columns: number,
	rowsPerPage: number,
	intent: GridNavIntent
): number {
	if (total <= 0) return 0;
	const cols = Math.max(1, columns);
	const rows = Math.max(1, rowsPerPage);
	switch (intent) {
		case 'left':
			return Math.min(total, Math.max(1, current - 1));
		case 'right':
			return Math.min(total, Math.max(1, current + 1));
		case 'up':
			return Math.min(total, Math.max(1, current - cols));
		case 'down':
			return Math.min(total, Math.max(1, current + cols));
		case 'pageUp':
			return Math.min(total, Math.max(1, current - cols * rows));
		case 'pageDown':
			return Math.min(total, Math.max(1, current + cols * rows));
		case 'first':
			return 1;
		case 'last':
			return total;
	}
}

export type OverviewGridKeyIntent = GridNavIntent | 'commit' | 'toCurrent' | 'ignore';

/**
 * What a key means to the grid's roving keyboard focus — the browsing half.
 * Deliberately keyboard-ONLY here (no mouse, no navigation side effects): every
 * intent but 'commit' just moves which tile is focused, so the audience/main
 * window never sees anything until the speaker actually presses Enter. See
 * OverviewPage's `jump()` for the one place 'commit' actually navigates.
 *
 * A modifier (Ctrl/Cmd/Alt) is left alone — a browser or OS chord, not ours —
 * and a typing target (the EDIT-deck add form) is left alone too, though in
 * practice that form lives outside the grid's DOM and never reaches this.
 */
export function overviewGridKeyIntent(e: KeyboardEvent): OverviewGridKeyIntent {
	if (e.ctrlKey || e.metaKey || e.altKey) return 'ignore';
	if (isTypingTarget(e.target)) return 'ignore';
	switch (e.key) {
		case 'ArrowLeft':
			return 'left';
		case 'ArrowRight':
			return 'right';
		case 'ArrowUp':
			return 'up';
		case 'ArrowDown':
			return 'down';
		case 'Home':
			return 'first';
		case 'End':
			return 'last';
		case 'PageUp':
			return 'pageUp';
		case 'PageDown':
			return 'pageDown';
		case 'Enter':
			return 'commit';
		case ' ':
		case 'Spacebar':
			return 'toCurrent';
		default:
			return 'ignore';
	}
}
