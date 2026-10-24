import { writable } from 'svelte/store';
import { browser } from '$app/environment';
import { persisted } from './persisted';
import { booleanCodec } from '$lib/utils/stateCore';
import { readSticky, readAdjustParam, resolveCanAdjust } from '$lib/adjust/adjustAccessCore';

// ADJUST mode — an AUTHORING aid, not a viewer feature. When on, <Block> wrappers
// expose drag + resize handles so you can position elements by hand at exact canvas
// pixels, then Copy (or, under `vite dev`, SAVE) the resulting tag back into source.
//
// Three stores:
//   - adjustMode: is the mode currently ON? Session-persisted so it survives full
//     page navigations between slides *in this tab*, then fails closed when the tab
//     closes. (It used to be localStorage — a single flip while authoring left the
//     next day stuck in ADJUST on every deck until someone noticed. When in doubt:
//     off.) Every editor (Block, Draw, Columns) gates on `$canAdjust && $adjustMode`,
//     so a stale `true` here is inert wherever the control isn't offered.
//   - canAdjust:  is the ADJUST control OFFERED here? True in `vite dev` always; in
//     a built site it follows the sticky `?adjust` flag, and failing that whatever
//     the current SLIDE declares (`adjust: true` in its pages.ts entry). Precedence
//     lives in adjust/adjustAccessCore.
//   - canSave:    can SAVE actually write back to source here? See below.
//
// The per-slide declaration is the demo switch: a published deck is ADJUST-free by
// default, but the handful of slides that *teach* ADJUST can offer the control in the
// BUILD — so a talk demonstrates authoring without the speaker typing a URL flag on
// stage, and without arming the authoring chrome on every other slide.
//
// Offered is not active: the mode itself still starts OFF. The audience sees a normal
// slide until the speaker flips it.

const MODE_KEY = 'adjustMode';
const CAN_KEY = 'canAdjust';

// Drop the old localStorage stickiness so a prior session cannot re-arm ADJUST on
// every visit. Session storage (below) is the only home for the mode now.
if (browser) {
	try {
		localStorage.removeItem(MODE_KEY);
	} catch {
		/* private mode / blocked storage — nothing to clear */
	}
}

// Can SAVE reach a source tree? SAVE POSTs to /__geekpresent/adjust-save, an endpoint
// that exists ONLY inside the vite dev server (adjust/devSavePlugin), where it rewrites
// the slide's .svelte file. A static host has no source tree to rewrite, so this is a
// genuine boundary — not a lock to pick. The button is shown either way and refuses on
// click (see SlideDeck), which is the honest thing to put in front of an audience.
//
// It is a STORE, not a bare `const x = import.meta.env.DEV`: as a const it read as a
// compile-time branch guard, and Vite dead-code eliminated the refusal path out of every
// build — so a deployed ADJUST demo had a hole where its payoff should be. Being settable
// is also the only way a test can exercise the built-site case, since `import.meta.env.DEV`
// is true under vitest.
export const canSave = writable<boolean>(import.meta.env.DEV);

// What the current slide declares. Module scope (not context) because the stores it feeds
// are module-level too, and the only writer is the one SlideDeck that owns the chrome.
// Re-set on every slide change — this is per-slide state, not a one-shot deck setting.
let declared = false;

function sticky() {
	return browser ? readSticky(localStorage.getItem(CAN_KEY)) : null;
}

function recompute(): void {
	canAdjust.set(resolveCanAdjust(import.meta.env.DEV, sticky(), declared));
}

// Is the mode currently ON? Session storage — survives slide-to-slide full reloads in
// this tab (GeekPresent navigates with location.href), cleared when the tab closes.
// Default false: fail closed. `booleanCodec` and not `jsonCodec<boolean>` so a corrupt
// key cannot arm the chrome (JSON would hand back a truthy object for `{"x":1}`).
//
// `sync: false` is redundant for session (per-tab already) but documents the intent:
// two windows each hold their own ADJUST state.
export const adjustMode = persisted<boolean>(MODE_KEY, false, {
	codec: booleanCodec(),
	sync: false,
	storage: 'session'
});

// NOT persisted stores, and deliberately left hand-rolled:
//   - canAdjust is DERIVED (DEV + the sticky ?adjust flag + the slide's own declaration),
//     recomputed on every slide change. It reads CAN_KEY but never mirrors itself to it.
//   - canSave is a capability of the environment, not a remembered preference.
export const canAdjust = writable<boolean>(resolveCanAdjust(import.meta.env.DEV, sticky(), declared));

/** Declare whether the CURRENT slide offers the ADJUST control — its `adjust` flag in
    pages.ts (or, deck-wide, SlideDeck's `adjust` prop). SlideDeck calls this on every
    slide change, so paging from a ADJUST demo onto an ordinary slide takes the control
    away again. A speaker's sticky `?adjust=off` still outranks it. */
export function setAdjustOffered(on: boolean): void {
	declared = on === true;
	recompute();
}

/** Opt the ADJUST control in/out from a slide URL's `?adjust` flag, then remember it
    across navigations (the flag is dropped by the nav links, so we persist it).
    `?adjust` / `?adjust=on` enables; `?adjust=off` disables and exits the mode. A URL
    with no flag changes nothing — it just re-resolves, so the current slide's own
    declaration still lands. */
export function applyAdjustParam(url: URL): void {
	if (!browser) return;
	const choice = readAdjustParam(url.searchParams);
	if (choice !== null) {
		localStorage.setItem(CAN_KEY, String(choice));
		if (!choice) adjustMode.set(false);
	}
	recompute();
}
