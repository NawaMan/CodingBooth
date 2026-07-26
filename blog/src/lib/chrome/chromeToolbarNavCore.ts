// Pure helpers for arrow-key roving focus on the top tool bar + ☰ drop.
//
// While chrome is Alt+.-armed (or ☰ is open), ←/→ walk the bar and ↑/↓ walk the
// more-menu rows. The DOM collection and focus() live in the caller; this file
// only answers "which index next" and "which arrow was pressed".
//
// Total: empty lists / garbage → safe zeros, never throw.

export type ArrowDir = 'up' | 'down' | 'left' | 'right';

/** Which arrow, or '' for none. */
export function arrowDir(e: { key?: string | null }): ArrowDir | '' {
	switch (e.key) {
		case 'ArrowUp':
			return 'up';
		case 'ArrowDown':
			return 'down';
		case 'ArrowLeft':
			return 'left';
		case 'ArrowRight':
			return 'right';
		default:
			return '';
	}
}

/** Wrap around a focusable list (↑ from first → last, etc.). */
export function stepWrap(index: number, delta: number, length: number): number {
	if (length <= 0) return 0;
	const i = Number.isFinite(index) ? Math.trunc(index) : 0;
	const d = Number.isFinite(delta) ? Math.trunc(delta) : 0;
	return ((i + d) % length + length) % length;
}

/**
 * Index of `el` in `list` (by reference). -1 if missing / null.
 * Also matches when `el` is *inside* a list item (e.g. focus in a span).
 */
export function focusIndexOf(list: readonly Element[], el: Element | null): number {
	if (!el || !list.length) return -1;
	const direct = list.indexOf(el);
	if (direct >= 0) return direct;
	for (let i = 0; i < list.length; i++) {
		if (list[i].contains(el)) return i;
	}
	return -1;
}

/**
 * Where arrow navigation should run.
 *
 * - `print` — PRINT flyout open and focus is in that flyout (or on PRINT)
 * - `more`  — ☰ drop open and focus is in the drop / on the hamburger
 * - `bar`   — chrome armed, focus on the top bar (or nowhere yet)
 * - `none`  — leave arrows alone (e.g. SizeMode zoom menu owns them)
 */
export type ToolbarNavZone = 'bar' | 'more' | 'print' | 'none';

export function toolbarNavZone(opts: {
	armed: boolean;
	moreOpen: boolean;
	printOpen: boolean;
	/** True when the DISPLAY zoom menu is expanded — it owns ↑/↓. */
	sizeMenuOpen: boolean;
	/** Focus is inside the PRINT flyout panel. */
	focusInPrint: boolean;
	/** Focus is inside the ☰ drop (not the hamburger). */
	focusInMoreDrop: boolean;
	/** Focus is on the hamburger button. */
	focusOnHamburger: boolean;
	/** Focus is on some top-bar control (incl. hamburger). */
	focusOnBar: boolean;
}): ToolbarNavZone {
	if (opts.sizeMenuOpen) return 'none';
	if (opts.printOpen && (opts.focusInPrint || opts.focusOnHamburger || opts.focusInMoreDrop)) {
		return 'print';
	}
	if (opts.moreOpen && (opts.focusInMoreDrop || opts.focusOnHamburger || opts.focusOnBar)) {
		return 'more';
	}
	// More open but focus nowhere useful — still allow walking the drop.
	if (opts.moreOpen) return 'more';
	if (opts.armed) return 'bar';
	return 'none';
}

/**
 * Next index for a zone + arrow. Returns null when the arrow is not used in
 * that zone (caller should fall through to other handlers).
 *
 * Bar: ←/→ only. More: ↑/↓ among rows; ↓ from hamburger (index -1) → 0;
 * ↑ from 0 → -1 means "back to hamburger". Print: ↑/↓ only.
 */
export function nextNavIndex(
	zone: ToolbarNavZone,
	dir: ArrowDir | '',
	current: number,
	length: number
): number | null {
	if (!dir || zone === 'none' || length < 0) return null;

	if (zone === 'bar') {
		if (dir === 'left') return stepWrap(current < 0 ? 0 : current, -1, length);
		if (dir === 'right') return stepWrap(current < 0 ? -1 : current, 1, length);
		// ↓ on bar is handled by the caller when current is the hamburger (open more).
		if (dir === 'down' || dir === 'up') return null;
		return null;
	}

	if (zone === 'more') {
		if (dir === 'down') {
			if (current < 0) return length > 0 ? 0 : null;
			return stepWrap(current, 1, length);
		}
		if (dir === 'up') {
			if (current <= 0) return -1; // back to hamburger
			return stepWrap(current, -1, length);
		}
		// ←/→ in the drop: caller may move to bar or open PRINT.
		return null;
	}

	if (zone === 'print') {
		if (dir === 'down') return stepWrap(current < 0 ? -1 : current, 1, length);
		if (dir === 'up') return stepWrap(current < 0 ? 0 : current, -1, length);
		if (dir === 'left') return -1; // signal: leave flyout
		return null;
	}

	return null;
}
