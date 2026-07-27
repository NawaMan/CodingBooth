import { writable } from 'svelte/store';

// The most recent NAMED trigger pulse this window has seen — the seam behind
// a note-driven "start this animation": a <Note> line carrying
// `data-trigger="save-cursor"` fires that name when the speaker checks it
// off, and any slide element (a <Cursor startOn="save-cursor">, today) that
// cares about that name reacts.
//
// Mirrors highlightTarget.ts's role exactly: LOCAL to this window; the
// console→audience hop rides stores/presenter's publishTrigger/
// subscribeTrigger (the same localStorage relay publishHighlight uses),
// which SlideDeck bridges into this store, exactly like setHighlight. A
// slide can also fireTrigger() directly (a button) with no presenter
// involved — general primitive, not presenter-only plumbing.
//
// A DISCRETE pulse, unlike highlightTarget's persistent state: consumers
// compare `ts`, not just `name`, so the SAME trigger firing twice in a row
// (re-checking a note line) is observed as two distinct events rather than
// an unchanged value nobody re-reacts to.
export interface TriggerPulse {
	name: string;
	ts: number;
}

export const lastTrigger = writable<TriggerPulse | null>(null);

/** Fire a named trigger pulse in THIS window. */
export function fireTrigger(name: string): void {
	if (!name) return;
	lastTrigger.set({ name, ts: Date.now() });
}
