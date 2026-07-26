// Temporary "chrome is up for keyboard" state — not a pin preference.
//
// Alt+. arms both window-edge bars for a few seconds so letter mnemonics
// (a/j/z/p/m/t) can reach controls without global letter shortcuts fighting
// typing and paging. Esc or the timer disarms. Distinct from toolBarPinned /
// controlBarPinned, which are sticky user latches.

import { get, writable } from 'svelte/store';

/** Bars are fully seated for keyboard use (CSS class `armed`, same seat as pin). */
export const chromeArmed = writable(false);

/**
 * Is the ☰ drop held open?
 *
 * This is a REAL open latch, like printMenuOpen and the DISPLAY menu — not the
 * old "held closed" suppressor. Openness used to be pure CSS (`:hover` /
 * `:focus-within`), so the keyboard had nothing to toggle and Esc could only
 * fight it with a sticky force-closed flag that hover alone could clear; once
 * set, the M mnemonic was dead until the pointer visited the menu. Hover and
 * focus still open the drop for mouse users — this store is simply the OR'd-in
 * third way in, and the only one the keyboard needs.
 */
export const moreMenuOpen = writable(false);

/**
 * Bump to ask TableOfContent to open (TOC state is local to the component;
 * this is the one-way request channel for the t mnemonic).
 */
export const tocOpenRequest = writable(0);

/**
 * Bump to ask SizeMode to toggle its zoom menu (open state is local to SizeMode;
 * this is the one-way request channel for the z mnemonic).
 */
export const displayMenuRequest = writable(0);

let armTimer: ReturnType<typeof setTimeout> | undefined;

/** How long bars stay raised after Alt+. or a mnemonic that re-arms (ms). */
export const CHROME_ARM_MS = 5000;

/** Raise both bars and (re)start the auto-disarm timer. */
export function armChrome(ms: number = CHROME_ARM_MS): void {
	chromeArmed.set(true);
	if (armTimer) clearTimeout(armTimer);
	armTimer = setTimeout(() => {
		chromeArmed.set(false);
		armTimer = undefined;
	}, ms);
}

/** Drop the temporary raise immediately. Does not change pin preferences. */
export function disarmChrome(): void {
	chromeArmed.set(false);
	moreMenuOpen.set(false);
	if (armTimer) {
		clearTimeout(armTimer);
		armTimer = undefined;
	}
}

/** Open the ☰ drop and keep it open (M, or a click on the hamburger). */
export function openMoreMenu(): void {
	moreMenuOpen.set(true);
}

/** Shut the ☰ drop: Esc, OVERVIEW opening, or a click outside the menu. */
export function closeMoreMenu(): void {
	moreMenuOpen.set(false);
}

/** M is a toggle, so a second press puts the drop away again. Returns the new state. */
export function toggleMoreMenu(): boolean {
	const next = !get(moreMenuOpen);
	moreMenuOpen.set(next);
	return next;
}

/** If already armed, refresh the timer so a chain of mnemonics does not expire mid-use. */
export function keepChromeArmed(ms: number = CHROME_ARM_MS): void {
	if (get(chromeArmed)) armChrome(ms);
}

/** Ask the TOC to open (and keep chrome raised). */
export function requestTocOpen(): void {
	tocOpenRequest.update((n) => n + 1);
	armChrome();
}

/** Ask DISPLAY (SizeMode) to toggle its zoom menu (and keep chrome raised). */
export function requestDisplayMenu(): void {
	displayMenuRequest.update((n) => n + 1);
	armChrome();
}
