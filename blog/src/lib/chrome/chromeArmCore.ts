// Pure decisions for chrome keyboard arming (Alt+.) and the short mnemonic
// alphabet that only fires while bars are armed.
//
// Global letters fight typing and deck paging; so the model is:
//   1. Alt+. raises both bars (arm)
//   2. While armed, a/j/z/p/m/t/u pick a bar control (u = pause/resume a live kiosk)
//   3. ☰ rows (o/k/c/r/s/e) fire while armed OR while the more menu is open —
//      so Alt+. → m → c runs CAPTURE, and a bare Alt+. → c does too. K is dual-purpose:
//      opens the Kiosk dialog while off, toggles the panel's forced-visible pin while live.
//   4. Esc (or timeout) disarms
//
// Total: garbage input → ignore, never throw.

/** Is this key press the user TYPING in a field? Same bargain as overviewPageCore. */
export function isChromeTypingTarget(t: EventTarget | null): boolean {
	const el = t as HTMLElement | null;
	if (!el) return false;
	if (el.isContentEditable) return true;
	return /^(INPUT|TEXTAREA|SELECT)$/.test(el.tagName ?? '');
}

/**
 * Is this the browser Save chord (Ctrl+S / Cmd+S) that ADJUST should claim for its
 * own SAVE, instead of letting the browser pop its "save this webpage" dialog?
 *
 * True ONLY when the chord is pressed AND ADJUST is currently active — so on a
 * normal slide the answer is false and the browser keeps its shortcut untouched.
 * `adjustActive` is the caller's `$canAdjust && $adjustMode`: offered AND on.
 *
 * Unlike the letter mnemonics, this deliberately does NOT bail while a text field
 * has focus: Ctrl+S means "save my work" everywhere, and popping the browser dialog
 * because the caret sits in an editable Block is the exact misfire we're removing.
 * Plain Ctrl/Cmd+S only — Shift/Alt carry other browser chords (Save As, …) and are
 * left to the browser. `e.code` is a fallback so a non-Latin layout still saves.
 * Total: no throw on garbage, and never true off a real Ctrl/Cmd+S.
 */
export function isAdjustSaveChord(e: KeyboardEvent, adjustActive: boolean): boolean {
	if (!adjustActive) return false;
	if (e.altKey || e.shiftKey) return false;
	if (!(e.ctrlKey || e.metaKey)) return false;
	return e.key === 's' || e.key === 'S' || e.code === 'KeyS';
}

export type ChromeKeyIntent =
	| 'arm'
	| 'disarm'
	| 'annotate'
	| 'adjust'
	| 'display'
	| 'present'
	| 'more'
	| 'toc'
	| 'kiosk-pause'
	| 'ignore';

/** ☰ dropdown row letters (underlined on the rows). Collision-free with the bar alphabet. */
export type MoreMenuKeyIntent =
	| 'overview'
	| 'kiosk'
	| 'capture'
	| 'print'
	| 'source'
	| 'edit'
	| 'ignore';

/**
 * Which mnemonic letter a press means, '' for none.
 *
 * `e.key` first, so a remapped-but-Latin layout (Dvorak, Colemak) gives the letter the
 * user actually SEES on the cap. A non-Latin layout reports its own script there, so fall
 * back to the PHYSICAL key (`e.code === 'KeyM'`) — the same bargain Alt+. and Ctrl+S make.
 * Total: garbage or absent key/code → '' → 'ignore'.
 */
function mnemonicLetter(e: KeyboardEvent): string {
	const key = (e.key ?? '').toLowerCase();
	if (/^[a-z]$/.test(key)) return key;
	const code = e.code ?? '';
	return /^Key[A-Z]$/.test(code) ? code.slice(3).toLowerCase() : '';
}

/**
 * ☰ row mnemonic while the more menu is open, or while chrome is armed (so the
 * letter both opens the drop and runs the row — the underline is not a lie).
 *
 * Alphabet: O OVERVIEW · K KIOSK · C CAPTURE · R PRINT · S SOURCE · E EDIT.
 * PRINT uses R because P is PRESENT on the bar. Case-insensitive; print flyout
 * case-sensitive keys (cCwWtT) are handled separately once PRINT is open.
 */
export function moreMenuKeyIntent(
	e: KeyboardEvent,
	moreOpen: boolean,
	armed: boolean
): MoreMenuKeyIntent {
	if (!moreOpen && !armed) return 'ignore';
	if (isChromeTypingTarget(e.target)) return 'ignore';
	if (e.ctrlKey || e.metaKey || e.altKey) return 'ignore';
	if (e.defaultPrevented) return 'ignore';

	switch (mnemonicLetter(e)) {
		case 'o':
			return 'overview';
		case 'k':
			return 'kiosk';
		case 'c':
			return 'capture';
		case 'r':
			return 'print';
		case 's':
			return 'source';
		case 'e':
			return 'edit';
		default:
			return 'ignore';
	}
}

/**
 * What a key means for chrome arming / bar-level mnemonics.
 *
 * @param armed  are the bars currently raised for keyboard use?
 */
export function chromeKeyIntent(e: KeyboardEvent, armed: boolean): ChromeKeyIntent {
	if (isChromeTypingTarget(e.target)) return 'ignore';

	// Alt+. (Period) — raise both bars. Prefer e.code so layouts that remap
	// Alt+letter still hit the physical period key.
	if (e.altKey && !e.ctrlKey && !e.metaKey && (e.code === 'Period' || e.key === '.')) {
		return 'arm';
	}

	// Esc closes ☰ / disarms chrome even if bars were only hover-opened (not Alt+.-armed),
	// so Escape always has a way to dismiss the more menu.
	if (
		e.key === 'Escape' &&
		!e.ctrlKey &&
		!e.metaKey &&
		!e.altKey &&
		!e.defaultPrevented
	) {
		return 'disarm';
	}

	// Letter mnemonics only while armed, and never with modifiers (browser chords win).
	if (!armed) return 'ignore';
	if (e.ctrlKey || e.metaKey || e.altKey) return 'ignore';
	if (e.defaultPrevented) return 'ignore';

	switch (mnemonicLetter(e)) {
		case 'a':
			return 'annotate';
		case 'j':
			return 'adjust';
		case 'z':
			// Zoom / display mode.
			return 'display';
		case 'p':
			// PRESENT — console. PRINT in ☰ uses (R) so the two do not share P.
			return 'present';
		case 'm':
			return 'more';
		case 't':
			return 'toc';
		case 'u':
			// Pause/resume a live kiosk run — the one free letter shared by "paUse"
			// and "resUme". Caller no-ops it when no kiosk is running.
			return 'kiosk-pause';
		default:
			return 'ignore';
	}
}
