// Client half of ViewSource EDIT save/load (dev only). Talks to the vite-dev
// endpoints in $lib/adjust/devSavePlugin.ts:
//
//   POST /__geekpresent/source-save  — overwrite +page.svelte
//   GET  /__geekpresent/source-load  — read +page.svelte (REFRESH)
//
// The editor popup must pass the *slide* route explicitly — its own pathname is
// `/_source-edit`.

const SAVE_ENDPOINT = '/__geekpresent/source-save';
const LOAD_ENDPOINT = '/__geekpresent/source-load';

export interface SourceSaveResult {
	ok: boolean;
	/** Relative path written, when the server accepted the write. */
	file?: string;
	error?: string;
}

export interface SourceLoadResult {
	ok: boolean;
	/** Relative path read. */
	file?: string;
	/** Full file contents. */
	content?: string;
	error?: string;
}

function resolveSlideRoute(route?: string): string | null {
	const slideRoute =
		(route && route.trim()) ||
		(typeof location !== 'undefined' ? location.pathname : '');
	if (!slideRoute || slideRoute === '/_source-edit' || slideRoute.endsWith('/_source-edit')) {
		return null;
	}
	return slideRoute;
}

/**
 * Write the given full-file content back to a slide's `+page.svelte`.
 * `route` is the slide pathname (e.g. `/slides/foo.html`).
 */
export async function savePageSource(
	content: string,
	route?: string
): Promise<SourceSaveResult> {
	if (typeof content !== 'string') {
		return { ok: false, error: 'content must be a string' };
	}
	// Empty wipes the slide; refuse rather than ship a zero-byte page.
	if (content.length === 0) {
		return { ok: false, error: 'refusing to write empty content' };
	}

	const slideRoute = resolveSlideRoute(route);
	if (!slideRoute) {
		return { ok: false, error: 'slide route is required (not the editor page)' };
	}

	try {
		const res = await fetch(SAVE_ENDPOINT, {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify({ route: slideRoute, content })
		});
		const data = await res.json().catch(() => ({}));
		if (!res.ok) {
			return { ok: false, error: data.error || `HTTP ${res.status}` };
		}
		return { ok: true, file: data.file };
	} catch (err) {
		return { ok: false, error: err instanceof Error ? err.message : String(err) };
	}
}

/**
 * Read the current on-disk `+page.svelte` for a slide route (REFRESH).
 * Used by the unscaled editor after ADJUST SAVE / external edits.
 */
export async function loadPageSource(route?: string): Promise<SourceLoadResult> {
	const slideRoute = resolveSlideRoute(route);
	if (!slideRoute) {
		return { ok: false, error: 'slide route is required (not the editor page)' };
	}

	try {
		const url = `${LOAD_ENDPOINT}?route=${encodeURIComponent(slideRoute)}`;
		const res = await fetch(url, { method: 'GET' });
		const data = await res.json().catch(() => ({}));
		if (!res.ok) {
			return { ok: false, error: data.error || `HTTP ${res.status}` };
		}
		if (typeof data.content !== 'string') {
			return { ok: false, error: 'server returned no content' };
		}
		return { ok: true, file: data.file, content: data.content };
	} catch (err) {
		return { ok: false, error: err instanceof Error ? err.message : String(err) };
	}
}
