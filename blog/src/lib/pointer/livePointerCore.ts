/*
  LIVE POINTER — the pure decision layer behind stores/livePointer.ts.

  A screen recorder that leaves the OS cursor out of the video (GNOME's built-in
  screencast, a tab captured through getDisplayMedia) shows the slides with nobody
  pointing at them. The live pointer is a glyph the PAGE draws where the mouse is,
  so whatever records the screen records the pointer too.

  Not to be confused with draw/Cursor.svelte: that one is SCRIPTED — an author writes
  its path and it plays on the animation timeline. This one has no script at all; it
  follows the real mouse, and only the speaker decides whether it is shown.

  So it resolves like bare chrome, not like ADJUST — there is no "offered" tier, since
  drawing a pointer can harm nothing:

    the speaker's sticky ?pointer / ?pointer=off > a deck-wide prop on SlideDeck > off

  Side-effect free and total: junk in, plain value out.
*/

import { readSticky, type Choice } from '$lib/adjust/adjustAccessCore';

export { readSticky };
export type { Choice };

/** The localStorage key the speaker's choice is remembered under. */
export const POINTER_KEY = 'livePointer';

/** The glyph presets — the same three `Cursor` offers, so the two pointers can match. */
export type PointerShape = 'arrow' | 'dot' | 'ring';

/** Interpret a slide URL's `?pointer` flag.

    `?pointer`, `?pointer=on`, `?pointer=1` show it; `?pointer=off`, `?pointer=false`,
    `?pointer=0` hide it. An absent flag is `null`, NOT `false` — the nav links carry no
    query, so a URL that says nothing must not revoke what the speaker turned on. */
export function readPointerParam(search: URLSearchParams | null | undefined): Choice {
	if (!search || !search.has('pointer')) return null;
	const v = (search.get('pointer') ?? '').trim().toLowerCase();
	return v !== 'off' && v !== 'false' && v !== '0';
}

/** Is the live pointer shown? The speaker's own choice wins; without one, the deck's prop. */
export function resolveLivePointer(sticky: Choice, deckWide: boolean): boolean {
	if (sticky !== null) return sticky;
	return deckWide === true;
}

/** A known shape, or `arrow` for anything else. */
export function normalizeShape(shape: unknown): PointerShape {
	return shape === 'dot' || shape === 'ring' ? shape : 'arrow';
}

/** The glyph's default size in screen px — large enough to read in a video scaled down to a
    phone, which is where a recording is often watched. */
export const DEFAULT_POINTER_SIZE = 40;

/** A usable glyph size in px: finite and positive, else DEFAULT_POINTER_SIZE. Clamped to
    8..200 so a typo cannot hide the pointer or cover the slide. */
export function normalizeSize(size: unknown): number {
	const n = Number(size);
	if (!Number.isFinite(n) || n <= 0) return DEFAULT_POINTER_SIZE;
	return Math.min(200, Math.max(8, n));
}

/** Where the glyph's top-left corner goes, relative to the mouse, so its HOTSPOT sits on
    the mouse. The arrow's tip is at (3, 3) in its 24-unit viewBox (the same path `Cursor`
    draws); a dot or a ring points with its centre. */
export function pointerOffset(shape: PointerShape, size: number): [number, number] {
	if (shape === 'arrow') {
		const d = -(3 / 24) * size;
		return [d, d];
	}
	return [-size / 2, -size / 2];
}
