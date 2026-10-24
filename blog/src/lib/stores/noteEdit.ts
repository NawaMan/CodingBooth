// Client half of the presenter console's NOTE EDIT (dev only). Talks to the
// vite-dev endpoints in $lib/adjust/devSavePlugin.ts:
//
//   GET  /__geekpresent/note-load  — the slide's <Note> inner source + a fingerprint
//   POST /__geekpresent/note-save  — splice the edit back, refused if the file moved
//
// The server does the locating, re-indenting and refusing (note/noteSourceCore);
// this file only carries the request and turns any failure into `{ ok: false, error }`.

const LOAD_ENDPOINT = '/__geekpresent/note-load';
const SAVE_ENDPOINT = '/__geekpresent/note-save';

export interface NoteLoadResult {
	ok: boolean;
	text?: string;
	fingerprint?: string;
	/** Relative path of the slide file. */
	file?: string;
	error?: string;
}

export interface NoteSaveResult {
	ok: boolean;
	file?: string;
	fingerprint?: string;
	error?: string;
}

/** Read the current slide's note. `route` is the slide pathname (`/slides/foo.html`). */
export async function loadNote(route: string): Promise<NoteLoadResult> {
	try {
		const res = await fetch(`${LOAD_ENDPOINT}?route=${encodeURIComponent(route)}`);
		const data = await res.json().catch(() => ({}));
		if (!res.ok) return { ok: false, error: data.error || `HTTP ${res.status}` };
		if (typeof data.text !== 'string') return { ok: false, error: 'server returned no note' };
		return { ok: true, text: data.text, fingerprint: data.fingerprint, file: data.file };
	} catch (err) {
		return { ok: false, error: err instanceof Error ? err.message : String(err) };
	}
}

/** Write the edited note back. `fingerprint` is what loadNote returned. */
export async function saveNote(route: string, text: string, fingerprint: string): Promise<NoteSaveResult> {
	try {
		const res = await fetch(SAVE_ENDPOINT, {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify({ route, text, fingerprint })
		});
		const data = await res.json().catch(() => ({}));
		if (!res.ok) return { ok: false, error: data.error || `HTTP ${res.status}` };
		return { ok: true, file: data.file, fingerprint: data.fingerprint };
	} catch (err) {
		return { ok: false, error: err instanceof Error ? err.message : String(err) };
	}
}
