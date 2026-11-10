import { browser } from '$app/environment';
import { derived, get, writable } from 'svelte/store';
import {
	POINTER_KEY,
	readPointerParam,
	readSticky,
	resolveLivePointer,
	type Choice
} from '$lib/pointer/livePointerCore';

// The live pointer — a glyph the page draws where the mouse is, for screen recorders that
// leave the OS cursor out (see pointer/livePointerCore).
//
// Two inputs: the speaker's sticky `?pointer` choice and the deck's `pointer` prop.
// SlideDeck feeds both; <LivePointer> reads `livePointer`.

function loadSticky(): Choice {
	if (!browser) return null;
	try {
		return readSticky(localStorage.getItem(POINTER_KEY));
	} catch {
		return null;
	}
}

const sticky = writable<Choice>(loadSticky());
const deckWide = writable(false);

/** True when the page draws its own pointer (and hides the real one). */
export const livePointer = derived([sticky, deckWide], ([$sticky, $deck]) =>
	resolveLivePointer($sticky, $deck)
);

/** Record the speaker's choice — what `?pointer` / `?pointer=off` and ☰ → POINTER write. */
export function setPointerChoice(choice: boolean): void {
	try {
		localStorage.setItem(POINTER_KEY, String(choice));
	} catch {
		// private mode / full quota: the choice still holds for this window
	}
	sticky.set(choice);
}

/** Show the live pointer now, or hide it — what ☰ → POINTER and Alt+. → I do. */
export function togglePointer(): void {
	setPointerChoice(!get(livePointer));
}

/** Declare whether the DECK shows the live pointer by default (SlideDeck's `pointer` prop). */
export function setLivePointerDeck(on: boolean): void {
	deckWide.set(on === true);
}

/** Opt in/out from a slide URL's `?pointer` flag and remember it across navigations (the
    nav links drop the flag). A URL with no flag changes nothing. */
export function applyPointerParam(url: URL): void {
	if (!browser) return;
	const choice = readPointerParam(url.searchParams);
	if (choice !== null) setPointerChoice(choice);
}

// Follow a choice made in another tab of this origin, so a second window of the deck agrees.
// `storage` never fires in the window that wrote, which is why setPointerChoice sets `sticky`.
if (browser) {
	window.addEventListener('storage', (e) => {
		if (e.key === POINTER_KEY || e.key === null) sticky.set(loadSticky());
	});
}
