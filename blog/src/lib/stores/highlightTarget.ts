import { writable } from 'svelte/store';

// The name of the <Block> the deck is currently SPOTLIGHTING, or `null` for none.
//
// This is the seam behind the note-driven highlight: a <Note> line carrying
// `data-highlight="db"` calls attention to the Block named "db" as the speaker
// covers it, and <Spotlight> (mounted once by SlideDeck) rings that Block's box —
// looked up in the SAME blockAnchors registry a <Connector> resolves against, so
// the spotlight tracks the box even as it is dragged in ADJUST mode.
//
// Module-level (not context) for the same reason `selectedBlock` / `blockAnchors`
// are: the trigger (a Note line) and the overlay (Spotlight) are far-apart siblings
// in the render tree with no common provider to hang a context on.
//
// This is a PER-WINDOW, transient store — the LOCAL highlight this window paints.
// The speaker drives it from the presenter console, whose window is a DIFFERENT
// one from the audience projector; the cross-window hop rides the same localStorage
// relay as `publishContinue` (see stores/presenter `publishHighlight`), which lands
// in the audience window and calls `setHighlight` there. So a slide can also drive
// this directly (a button, a Steps build) without any presenter at all — it is a
// general primitive, not presenter-only plumbing.
export const highlightTarget = writable<string | null>(null);

/** Spotlight the Block named `name`, or clear the spotlight with `null`/`''`. */
export function setHighlight(name: string | null): void {
	highlightTarget.set(name ? name : null);
}
