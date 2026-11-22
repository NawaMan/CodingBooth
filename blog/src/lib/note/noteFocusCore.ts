// The keyboard cursor on the presenter console's note lines: which line it is on, and
// where a key moves it. The lines themselves, their check states and the highlight a
// line lights belong to <Note> (its `checklist` action); the keys are the console's
// (chrome/presenterKeyCore.ts). This is only the arithmetic between them.
//
//   ↓ / ↑        move the cursor (the first ↓ lands on the first line not yet checked)
//   Space        check the line under the cursor and move on to the next
//   Shift+Space  take that back: uncheck the line under the cursor, or — when it is
//                not checked — step up and uncheck the one above
//   Esc          put the cursor away
//
// The cursor acts as the pointer does: resting on a `data-highlight` line lights its
// target on the audience slide.
//
// Pure and total: a line count of 0 or a junk index yields `null` (no cursor).

/** The cursor: a line index, or null when it is put away. */
export type NoteFocus = number | null;

function valid(focus: unknown, count: number): focus is number {
	return typeof focus === 'number' && Number.isInteger(focus) && focus >= 0 && focus < count;
}

/**
 * Where ↓ (`dir` 1) or ↑ (`dir` -1) takes the cursor. With no cursor yet, ↓ starts at
 * the first unchecked line (the last line when all are checked) and ↑ at the last
 * line. At either end it stays where it is.
 */
export function stepNoteFocus(
	focus: NoteFocus | undefined,
	checked: readonly boolean[] | null | undefined,
	dir: 1 | -1
): NoteFocus {
	const count = checked?.length ?? 0;
	if (count === 0) return null;
	if (!valid(focus, count)) {
		if (dir === -1) return count - 1;
		const open = checked!.findIndex((c) => !c);
		return open === -1 ? count - 1 : open;
	}
	return Math.max(0, Math.min(count - 1, focus + (dir === -1 ? -1 : 1)));
}

/** Where the cursor goes after Space checked `focus`: the next line, or it stays on the last. */
export function afterNoteCheck(focus: NoteFocus | undefined, count: number): NoteFocus {
	if (!valid(focus, count)) return null;
	return Math.min(count - 1, focus + 1);
}

/**
 * Which line Shift+Space unchecks (and where the cursor ends up): the line under the
 * cursor when it is checked, else the one above it. `null` = nothing to take back.
 */
export function noteUncheckTarget(
	focus: NoteFocus | undefined,
	checked: readonly boolean[] | null | undefined
): NoteFocus {
	const count = checked?.length ?? 0;
	if (!valid(focus, count)) return null;
	if (checked![focus]) return focus;
	return focus > 0 ? focus - 1 : null;
}

/** What the console asks the note to do, sent as a `gp:note-key` window event. */
export type NoteKeyAction = 'down' | 'up' | 'check' | 'uncheck' | 'blur';
export const NOTE_KEY_EVENT = 'gp:note-key';
