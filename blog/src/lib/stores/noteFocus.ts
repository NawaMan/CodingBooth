import { writable, type Writable } from 'svelte/store';
import type { NoteFocus } from '$lib/note/noteFocusCore';

// The line the presenter console's keyboard cursor is on (note/noteFocusCore.ts), or
// null. <Note> writes it; the console reads it to know whether Space means "check this
// line" or "continue the build". Live state of one slide in one window: not persisted,
// and reset when the note unmounts.
export const noteFocus: Writable<NoteFocus> = writable(null);
