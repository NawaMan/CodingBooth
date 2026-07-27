import { browser } from '$app/environment';
import { persisted } from './persisted';
import { booleanCodec } from '$lib/utils/stateCore';

// Chrome pin — keep a bar FULLY VISIBLE instead of auto-hiding to a peek strip until
// hover/focus.
//
// Both bars auto-tuck by default (tool bar up, control bar down) so they stay out of
// the audience's way while presenting. A speaker who is actively using one often wants
// *that* one to stay out rather than re-tuck every time the pointer leaves. These flags
// are those latches — one per bar, independent, so you can pin the pager open for a
// talk while leaving the top tools tucked (or the reverse).
//
// Default is auto-hide (false) on a first visit. Persisted so the choice survives a
// slide change and a reload. `sync: false` so the presenter console and an audience
// window each keep their own preference — the same bargain displayMode / adjustMode make.
//
// The old single-key `chromePinned` is the store's INITIAL value (not part of the codec):
// a Codec only ever sees its own key's string, and "what should this bar believe when it
// has no opinion of its own stored?" is exactly what an initial value answers. A live
// per-bar key always outranks the legacy one.

const TOOL_KEY = 'toolBarPinned';
const CTRL_KEY = 'controlBarPinned';
const LEGACY_KEY = 'chromePinned';

/** Pre-split single flag, read as a pin.

    This is each store's INITIAL value rather than part of its codec — same shape as
    displayMode's legacy `scaleMode` migration. A Codec is a pure translation of ONE
    key's string; the migration reads a DIFFERENT key. */
function legacySeed(): boolean {
	if (!browser) return false;
	try {
		return localStorage.getItem(LEGACY_KEY) === 'true';
	} catch {
		return false;
	}
}

/** Top tool bar (PRESENT / ANNOTATE / ADJUST / …) stays fully open when true. */
export const toolBarPinned = persisted<boolean>(TOOL_KEY, legacySeed(), {
	codec: booleanCodec(),
	sync: false
});

/** Bottom control bar (TOC / pager / ANIMATE) stays fully open when true. */
export const controlBarPinned = persisted<boolean>(CTRL_KEY, legacySeed(), {
	codec: booleanCodec(),
	sync: false
});
