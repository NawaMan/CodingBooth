/**
 * Pure path helpers for deck discovery.
 *
 * A deck is any folder under `src/routes/` that owns a `pages.ts`. Historically every
 * deck was a single segment (`slides`, `animation`). Component references nest under
 * `/references/<group>`, so a deck's *filesystem* path, *URL* path, and *handout id*
 * are three related but not identical strings:
 *
 *   fsPath   — under `src/routes/`, may include SvelteKit route groups: `references/(hub)`
 *   urlPath  — groups stripped: `references` or `references/shell`
 *   id       — single URL segment for `/_handout/<id>.html`: `references` / `references-shell`
 *
 * This module is pure and total: junk inputs yield null / empty, never throw.
 */

export type DeckPaths = {
	/** Single-segment id for `/_handout/<id>.html` and handout `entries()`. */
	id: string;
	/** Path under `src/routes/` (may include `(routeGroups)`). */
	fsPath: string;
	/** Public URL path under the site root (no leading slash, no route groups). */
	urlPath: string;
};

/** Strip SvelteKit `(group)` segments from a path. */
export function stripRouteGroups(path: string): string {
	if (typeof path !== 'string' || !path) return '';
	return path
		.replace(/\/\([^/]+\)/g, '')
		.replace(/^\([^/]+\)\//, '')
		.replace(/^\([^/]+\)$/, '')
		.replace(/\/{2,}/g, '/')
		.replace(/^\/+|\/+$/g, '');
}

/**
 * Parse a Vite glob key like `/src/routes/slides/pages.ts` or
 * `/src/routes/references/(hub)/pages.ts` into deck path parts.
 * Returns null when the path is not a pages.ts under routes.
 */
export function pathsFromPagesFile(file: string): DeckPaths | null {
	if (typeof file !== 'string' || !file) return null;
	const m = file.match(/\/src\/routes\/(.+)\/pages\.ts$/);
	if (!m) return null;
	const fsPath = m[1];
	if (!fsPath || fsPath.startsWith('_')) return null;
	// Skip nested junk: a pages.ts inside a slide folder would be wrong.
	// Valid: one or more path segments; slide folders end in `.html`.
	const segments = fsPath.split('/');
	if (segments.some((s) => s.endsWith('.html'))) return null;

	const urlPath = stripRouteGroups(fsPath);
	if (!urlPath) return null;
	const id = urlPath.replace(/\//g, '-');
	if (!id) return null;
	return { id, fsPath, urlPath };
}

/** Absolute module path for a slide's `+page.svelte` given deck fsPath + slide path. */
export function slideModulePath(fsPath: string, slidePath: string): string {
	const fs = typeof fsPath === 'string' ? fsPath.replace(/^\/+|\/+$/g, '') : '';
	const slide = typeof slidePath === 'string' ? slidePath.replace(/^\/+|\/+$/g, '') : '';
	if (!fs || !slide) return '';
	return `/src/routes/${fs}/${slide}/+page.svelte`;
}

/** Public site path for one slide (leading slash), e.g. `/references/shell/block.html`. */
export function slideSitePath(urlPath: string, slidePath: string): string {
	const base = typeof urlPath === 'string' ? urlPath.replace(/^\/+|\/+$/g, '') : '';
	const slide = typeof slidePath === 'string' ? slidePath.replace(/^\/+|\/+$/g, '') : '';
	if (!base || !slide) return '';
	return `/${base}/${slide}`;
}
