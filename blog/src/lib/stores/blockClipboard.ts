import { get, writable } from 'svelte/store';
import { browser } from '$app/environment';
import { adjustMode, canAdjust } from './adjustMode';

// ADJUST-mode copy/paste of a <Block>.
//
// Copy remembers WHICH Block (by its host's per-instance id) and its current box.
// It does not touch the system clipboard: a Block's content is the slide's own
// markup, which only the source file knows, and SAVE is what copies it there (see
// patchSource's PASTE mode). Paste publishes a request; the HOST Block — the one
// that is in the source — renders the copy as a second, live instance of itself,
// pending until SAVE like every other ADJUST edit.
//
// Same-page only, and deliberately so: deck navigation is a full page load, which
// clears this module — and a Block's content may lean on the slide's imports and
// scoped CSS, which do not travel to another slide.

export interface BlockClip {
	/** blockId of the source-backed Block that will render the copy. */
	host: number;
	x: number;
	y: number;
	width: number;
	height: number;
	z: number;
	/** The name copies are numbered from (the source Block's own name). */
	baseName: string;
}

export interface PasteRequest extends BlockClip {
	/** Unique per request, so a host never applies the same paste twice. */
	id: number;
	/** 1-based count of pastes since the last copy — drives the cascade offset. */
	n: number;
}

let clip: BlockClip | null = null;
let pastes = 0;
let nextRequestId = 1;

export const pasteRequests = writable<PasteRequest | null>(null);

/** Remember a Block to paste. A new copy restarts the cascade. */
export function copyBlock(entry: BlockClip): void {
	clip = { ...entry };
	pastes = 0;
}

/** True when there is something to paste. */
export function hasClip(): boolean {
	return clip !== null;
}

/** Ask the host Block to render a copy. Returns false with nothing copied. */
export function pasteBlock(): boolean {
	if (!clip) return false;
	pastes++;
	pasteRequests.set({ ...clip, id: nextRequestId++, n: pastes });
	return true;
}

/** Forget the clip (tests). */
export function clearClip(): void {
	clip = null;
	pastes = 0;
	pasteRequests.set(null);
}

function isTyping(el: EventTarget | null): boolean {
	const node = el as HTMLElement | null;
	const tag = node?.tagName;
	return tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT' || !!node?.isContentEditable;
}

// Ctrl/Cmd+V pastes — with or without a selection, so you can copy, click away
// and paste. One window listener for the whole page (like adjustHistory's undo),
// so a press pastes exactly once however many Blocks are mounted. Copy lives on
// the selected Block itself, since it needs that Block's props.
if (browser) {
	window.addEventListener('keydown', (e) => {
		if (!(e.ctrlKey || e.metaKey) || e.shiftKey || e.altKey) return;
		if (e.key.toLowerCase() !== 'v' || isTyping(e.target)) return;
		if (!(get(canAdjust) && get(adjustMode))) return;
		if (pasteBlock()) e.preventDefault();
	});
}
