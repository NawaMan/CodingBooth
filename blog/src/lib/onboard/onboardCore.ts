// The first-visit hint's rules — pure, total, DOM-free (tested in onboardCore.test.ts).
//
// A new viewer lands on a deck's first slide and does not know it pages with →/Space or
// that the two bars hide at the window's edges. So they press Enter, click, scroll — or
// nothing at all. <OnboardHint> watches for exactly that, and these are its rules:
//
//   • WHO is new: nobody who has ever left the first slide, opened a bar, pressed a
//     paging key, or dismissed the hint. One flag per ORIGIN (stores/onboard.ts), not per
//     deck — a viewer who learned → on one deck knows it on every deck.
//   • WHERE: only on the deck's first VISIBLE slide (the linear march, appendices out),
//     and only when there is a second slide to go to.
//   • WHEN: after `delayMs` of nothing useful — or at once, on a STRAY input: the Enter,
//     the click on the slide, the scroll that a stuck viewer tries first. Those do not
//     teach the viewer anything, so they bring the hint forward instead of cancelling it.

import { visiblePages, type Page } from '$lib/utils/navigate';

/** How long a viewer may sit on the first slide before the hint offers itself. */
export const DEFAULT_ONBOARD_DELAY_MS = 8000;

/** A usable delay: a finite, non-negative number of ms, else the default. Junk must not
    become `setTimeout(NaN)`, which fires at once and greets every visitor with the hint. */
export function onboardDelayMs(value: unknown): number {
	return typeof value === 'number' && Number.isFinite(value) && value >= 0
		? value
		: DEFAULT_ONBOARD_DELAY_MS;
}

/** Position of `current` in the deck's linear march, or -1 (unknown, or a hidden slide). */
function visibleIndex(pages: Array<Page>, current: string): number {
	return visiblePages(pages).findIndex((p) => p.path === current);
}

/** Is this the deck's first visible slide, with somewhere to go from it? */
export function isFirstSlide(pages: Array<Page>, current: string): boolean {
	return visibleIndex(pages, current) === 0 && visiblePages(pages).length > 1;
}

/** Has the viewer reached a slide past the first? That is the proof they found the way
    on — read on arrival, so every route counts (keys, pager, TOC, a link, a typed URL). */
export function isBeyondFirst(pages: Array<Page>, current: string): boolean {
	return visibleIndex(pages, current) > 0;
}

/** Everything that decides whether the hint may be shown on this page view. */
export interface OnboardGate {
	/** The deck offers the hint (`<SlideDeck onboardHint>`). */
	offered: boolean;
	/** This viewer has already explored (or dismissed the hint). */
	done: boolean;
	/** We stand on the first visible slide. */
	firstSlide: boolean;
	/** Something owns the screen: a console is live, a kiosk runs, a recording rolls, an
	    embedded tile, `?clean`… The hint must never reach an audience. */
	suppressed: boolean;
	/** `?onboard`: show it anyway — on any slide, to a viewer who already knows, even on a
	    deck that opted out. Only `suppressed` still wins: a forced hint must not reach an
	    audience either. */
	force?: boolean;
}

/** May this page view watch for a stuck viewer at all? */
export function shouldWatch(gate: OnboardGate): boolean {
	if (gate.suppressed) return false;
	return !!gate.force || (gate.offered && !gate.done && gate.firstSlide);
}

/** What one input says about the viewer.
    - `explore` — they know the way: a paging key. Done; never show the hint again.
    - `stray`   — what a stuck viewer tries: show the hint now.
    - `none`    — says nothing either way. */
export type OnboardSignal = 'explore' | 'stray' | 'none';

const EXPLORE_KEYS = new Set([' ', 'Spacebar', 'ArrowRight', 'ArrowLeft', 'PageDown', 'PageUp']);
const STRAY_KEYS = new Set(['Enter', 'ArrowDown', 'ArrowUp']);

/** Classify a keydown. A chord (Ctrl/Cmd/Alt) is somebody using a shortcut, not paging —
    Alt+. raises the bars, and the bars' own listener is what counts that. */
export function classifyKey(
	key: string,
	mods: { ctrl?: boolean; meta?: boolean; alt?: boolean } = {}
): OnboardSignal {
	if (mods.ctrl || mods.meta || mods.alt) return 'none';
	if (EXPLORE_KEYS.has(key)) return 'explore';
	if (STRAY_KEYS.has(key)) return 'stray';
	return 'none';
}
