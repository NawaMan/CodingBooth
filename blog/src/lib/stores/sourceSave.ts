// Client half of the dev-only `source-load` endpoint ($lib/adjust/devSavePlugin.ts):
// a slide route → its +page.svelte path and bytes. The EDIT window uses it to
// find a slide's page file; it saves through source/sourceFiles.ts (file-save).
//
// The editor popup must pass the *slide* route explicitly — its own pathname is
// `/_source-edit`.

const LOAD_ENDPOINT = '/__geekpresent/source-load';

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
