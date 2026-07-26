import { writable } from 'svelte/store';

// The <Block> currently "selected" in ADJUST mode.
//
// Selecting a Block brings it temporarily to the top so its body and resize grip
// stay grabbable even when Blocks overlap (Blocks otherwise paint in DOM order,
// so a lower one's grip can hide beneath a later one). This is a TRANSIENT editor
// concern — it is NOT written to source and NOT persisted across reloads. The
// PERSISTENT stacking order (an explicit `z` prop + bring-to-front / send-to-back)
// is the separate feature tracked in TODO.md.
//
// One selection at a time across the slide: because every Block reads this single
// store, selecting one clears the rest. `null` = nothing selected.
export const selectedBlock = writable<number | null>(null);

let counter = 0;
/** A stable per-instance id for one Block, used as its selection identity. */
export function nextBlockId(): number {
	return ++counter;
}
