// Pure decisions for the presenter CONSOLE's keyboard mnemonics — the twin of
// chromeArmCore, but for the ?present window rather than the audience deck.
//
// On stage the speaker drives from the keyboard; the console's TOC / reset-checks /
// reset-ink controls were pointer-only, so reaching for the mouse to open the jump
// menu or clear last run's ink is exactly the fumble the console exists to spare.
// Each of the three gets a letter:
//
//   T — table of contents (jump menu)
//   C — reset check-offs   (opens the menu; the destructive step stays a click)
//   A — reset annotations  (ink; opens the menu — same softness)
//
// A key TOGGLES its menu open, it never resets on its own: opening the menu is the
// soft confirm the RESET menus already lean on, so no key destroys with one press.
// Esc closes whatever is open — even from the timer field, so it always has an out.
//
// The console also PAGES: →/← walk the deck, Space advances. But the console window
// is blind to the audience slide's build state (`activeSteps` lives in the window
// that mounts the slide, not here), so the split mirrors NavigationBar's rule that
// arrows always page and never step:
//
//   →      page next            ←      page prev
//   Space  advance the build    Shift+Space  page prev (walk back)
//
// Space returns 'continue' — the view relays the same CONTINUE pulse the button
// fires, which steps an armed <Steps>/Video build in the audience window and pages
// NOTHING. So a blind Space can never skip past an unfinished build (the "no skip-
// past" the arrows deliberately don't promise): it defers to the build every time.
//
// Once the TOC jump menu is open, ↑/↓/Enter browse it (tocDown/tocUp/tocSelect) —
// the console's own twin of an audience TOC's arrow browsing, so the menu is not
// mouse-only. The menu's own search box claims those keys itself once focused
// (stopPropagation); this is the fallback for browsing without the caret there.
//
// Total: garbage input → 'ignore', never throws.

import { isChromeTypingTarget } from './chromeArmCore';
import { isSpaceKey } from '$lib/utils/stepKeys';

export type PresenterKeyIntent =
	| 'toc'
	| 'checks'
	| 'ink'
	| 'close'
	| 'next'
	| 'prev'
	| 'continue'
	| 'tocUp'
	| 'tocDown'
	| 'tocSelect'
	| 'ignore';

/**
 * What a key means in the presenter console window.
 *
 * @param inkOffered  is the ink-reset control shown at all? (`$canAnnotate` in the
 *   view) — when the pen was never offered, A is inert rather than toggling a menu
 *   that isn't there.
 * @param tocOpen  is the TOC jump menu currently open? While it is, ↑/↓/Enter walk
 *   its rows instead of doing nothing — the fallback for browsing it without the
 *   caret in its search box, which claims those keys itself (stopPropagation)
 *   once focused.
 */
export function presenterKeyIntent(
	e: KeyboardEvent,
	inkOffered: boolean = false,
	tocOpen: boolean = false
): PresenterKeyIntent {
	const k = (e?.key ?? '').toLowerCase();

	// Escape closes any open menu FIRST — before the typing guard — so it still
	// dismisses the timer popover while the caret sits in its input.
	if (k === 'escape' && !e.ctrlKey && !e.metaKey && !e.altKey) return 'close';

	// The letters must never fire while the speaker is typing (the timer field).
	if (isChromeTypingTarget(e?.target)) return 'ignore';

	// A modifier means a browser/OS chord (Ctrl+A, Cmd+T…) — leave those alone.
	// (Shift is NOT a chord here — Shift+Space is a real console gesture.)
	if (e.ctrlKey || e.metaKey || e.altKey) return 'ignore';
	if (e.defaultPrevented) return 'ignore';

	// TOC browsing takes ↑/↓/Enter before anything else claims them, but only
	// while the menu is actually open — a closed menu has no rows to walk.
	if (tocOpen) {
		if (k === 'arrowdown') return 'tocDown';
		if (k === 'arrowup') return 'tocUp';
		if (k === 'enter') return 'tocSelect';
	}

	// Paging. Space defers to the build via a CONTINUE relay ('continue'); Shift+Space
	// walks the deck back; the arrows page outright, never stepping (stepKeys' rule).
	if (isSpaceKey(e)) return e.shiftKey ? 'prev' : 'continue';
	if (k === 'arrowright') return 'next';
	if (k === 'arrowleft') return 'prev';

	switch (k) {
		case 't':
			return 'toc';
		case 'c':
			return 'checks';
		case 'a':
			// Inert unless the pen (and so the reset-ink control) is actually offered.
			return inkOffered ? 'ink' : 'ignore';
		default:
			return 'ignore';
	}
}
