import { base } from '$app/paths';
import {
	SOURCE_EDIT_MSG,
	SOURCE_EDIT_STORAGE_KEY,
	SOURCE_EDIT_WINDOW_NAME,
	encodeSourceEditPayload,
	type SourceEditPayload
} from '$lib/source/sourceEditSession';

// Open (or focus) the unscaled source-editor popup. The slide canvas scales with
// CSS transform; Monaco's caret metrics do not follow that scale, so editing
// lives in a window of its own. SAVE stays in that window and does not close it
// (HMR on the slide is free to reload the opener).

let editorWin: Window | null = null;

export type OpenSourceEditorInput = Omit<SourceEditPayload, 'ts'>;

/** Push a payload and open/focus the `_source-edit` window. */
export function openSourceEditor(input: OpenSourceEditorInput): Window | null {
	if (typeof window === 'undefined') return null;

	const payload: SourceEditPayload = { ...input, ts: Date.now() };
	try {
		sessionStorage.setItem(SOURCE_EDIT_STORAGE_KEY, encodeSourceEditPayload(payload));
	} catch {
		// private mode / quota — still try the window; it may get postMessage only
	}

	const url = `${base}/_source-edit`;
	const features = 'popup=yes,width=1280,height=900,menubar=no,toolbar=no,location=no,status=no';

	// Reuse one named window so a second ☰ → SOURCE focuses rather than spawning.
	if (!editorWin || editorWin.closed) {
		editorWin = window.open(url, SOURCE_EDIT_WINDOW_NAME, features);
	} else {
		editorWin.focus();
		// Already on the editor URL — push the new buffer in.
		try {
			editorWin.postMessage({ type: SOURCE_EDIT_MSG, ...payload }, window.location.origin);
		} catch {
			/* cross-origin or gone */
		}
	}

	// Fresh open: the page reads sessionStorage on mount. Also postMessage once
	// it is ready (same-origin load is fast; a second message after a tick covers
	// a window that was mid-navigation).
	if (editorWin && !editorWin.closed) {
		const target = editorWin;
		const send = () => {
			try {
				target.postMessage({ type: SOURCE_EDIT_MSG, ...payload }, window.location.origin);
			} catch {
				/* ignore */
			}
		};
		setTimeout(send, 50);
		setTimeout(send, 300);
	}

	return editorWin;
}
