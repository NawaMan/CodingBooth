// Payload handed from a slide's ViewSource to the unscaled `_source-edit` popup.
//
// The editor lives in a SEPARATE browser window so Monaco is not under the slide
// canvas `transform: scale(…)`. That scale is what made the caret drift from the
// glyphs (Monaco measures fonts in untransformed CSS px; the canvas draws them
// scaled). sessionStorage + postMessage carry the buffer across; the popup never
// reads the slide DOM.

export const SOURCE_EDIT_STORAGE_KEY = 'gp-source-edit';
export const SOURCE_EDIT_WINDOW_NAME = 'geekpresent-source-edit';
export const SOURCE_EDIT_MSG = 'gp-source-edit';

export interface SourceEditPayload {
	/** Slide pathname used for SAVE, e.g. `/slides/viewsource-edit.html`. */
	route: string;
	/** Path shown in the title bar (display only). */
	path: string;
	/** File bytes from the slide's `?raw` import. */
	source: string;
	/** Monaco language id (svelte → html). */
	language: string;
	/** Whether SAVE can write (vite dev). */
	canSave: boolean;
	/** Bumped on every open so the popup notices a re-push of the same slide. */
	ts: number;
}

/** Serialize a payload for sessionStorage (total: bad input → null). */
export function encodeSourceEditPayload(p: SourceEditPayload): string {
	return JSON.stringify(p);
}

/** Parse a payload from sessionStorage or a postMessage body. Junk → null. */
export function parseSourceEditPayload(raw: unknown): SourceEditPayload | null {
	let obj: unknown = raw;
	if (typeof raw === 'string') {
		try {
			obj = JSON.parse(raw);
		} catch {
			return null;
		}
	}
	if (!obj || typeof obj !== 'object') return null;
	const o = obj as Record<string, unknown>;
	if (typeof o.route !== 'string' || !o.route) return null;
	if (typeof o.source !== 'string') return null;
	if (typeof o.path !== 'string') return null;
	if (typeof o.language !== 'string') return null;
	if (typeof o.canSave !== 'boolean') return null;
	const ts = typeof o.ts === 'number' && Number.isFinite(o.ts) ? o.ts : Date.now();
	return {
		route: o.route,
		path: o.path,
		source: o.source,
		language: o.language || 'html',
		canSave: o.canSave,
		ts
	};
}

/** postMessage envelope the opener sends into an already-open editor window. */
export function isSourceEditMessage(data: unknown): data is { type: typeof SOURCE_EDIT_MSG } & SourceEditPayload {
	if (!data || typeof data !== 'object') return false;
	const d = data as Record<string, unknown>;
	if (d.type !== SOURCE_EDIT_MSG) return false;
	return parseSourceEditPayload(d) !== null;
}
