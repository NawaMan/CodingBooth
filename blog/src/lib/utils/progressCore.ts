// Where a slide sits in its deck — the pure arithmetic behind a progress bar or a
// "3 / 7" chip. It answers the one question the deck shell knows but a slide's own
// JS/TS could not ask before: which page am I, of how many?
//
// Pure, total and NaN-safe (the drawCore / captureCore discipline): a junk page list
// or a non-string path degrades to an empty, `present: false` result — never a throw,
// never `NaN%`. The reactive wrapper that feeds it the live route is getProgress() in
// $lib/presentation; this module is just the maths, so it unit-tests directly.
import { visiblePages, type Page } from '$lib/utils/navigate';

export interface Progress {
	/** 0-based position among the deck's VISIBLE slides; -1 when the current path is
	    not a visible slide (a hidden appendix, or a route missing from pages.ts). */
	index: number;
	/** 1-based position (index + 1); 0 when not a visible slide. */
	position: number;
	/** Count of VISIBLE slides — the denominator. Hidden appendices don't inflate it. */
	total: number;
	/** How far through the deck, 0..1: position / total, clamped. 0 when the current
	    path is not a visible slide, or the deck is empty. */
	fraction: number;
	/** Is the current path one of the visible slides? A bar hides itself when false,
	    so an appendix or an off-list route shows nothing rather than a broken bar. */
	present: boolean;
}

/** The bare slide filename a deck route ends in: "/geeklight/title.html/" -> "title.html".
    The same derivation SlideDeck uses for `currentSlide`, factored out so it's testable.
    Total: a non-string (or empty) yields "", which matches no slide. */
export function currentSlidePath(pathname: unknown): string {
	if (typeof pathname !== 'string') return '';
	const seg = pathname.replace(/\/+$/, '').split('/').pop();
	return seg ?? '';
}

const clamp01 = (n: number): number => (!Number.isFinite(n) || n <= 0 ? 0 : n >= 1 ? 1 : n);

/** Locate `currentPath` in `pages`' linear (visible-only) order and report the progress.
    Guards every input: `pages` that isn't an array, elements that aren't objects, and a
    `currentPath` that isn't a string all fall through to a present:false result rather
    than throwing — so a slide that annotates progress degrades gracefully on a deck that
    doesn't, and never renders `NaN`. */
export function progressOf(pages: unknown, currentPath: unknown): Progress {
	const list = Array.isArray(pages)
		? pages.filter((p): p is Page => !!p && typeof p === 'object')
		: [];
	const deck = visiblePages(list);
	const total = deck.length;
	const path = typeof currentPath === 'string' ? currentPath : '';
	const index = path ? deck.findIndex((p) => p.path === path) : -1;
	if (index < 0) return { index: -1, position: 0, total, fraction: 0, present: false };
	const position = index + 1;
	return { index, position, total, fraction: clamp01(position / total), present: true };
}
