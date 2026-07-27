import * as path from 'node:path';

// Shared route → `src/routes/<…>/+page.svelte` mapping for the dev-only write
// endpoints (ADJUST SAVE and ViewSource SAVE). Kept pure so tests can pin the
// safety rules without spinning up a Vite server.
//
// Rules:
//   - strip query/hash and an optional kit `base`
//   - no empty / `.` / `..` segments (path traversal)
//   - resolved file must stay inside `src/routes`

/** Turn `/slides/title.html` (minus the dev `base`) into a route folder path,
    or null if it escapes the routes tree. */
export function routeToDir(route: string, base: string): string | null {
	let r = route.split('?')[0].split('#')[0];
	if (base && base !== '/' && r.startsWith(base)) r = r.slice(base.length);
	r = r.replace(/^\/+/, '').replace(/\/+$/, '');
	if (!r) return null;
	if (r.split('/').some((seg) => seg === '..' || seg === '.' || seg === '')) return null;
	return r;
}

/**
 * Absolute path of the slide's `+page.svelte`, or null if the route is unusable
 * or would resolve outside `src/routes`.
 */
export function routeToPageFile(route: string, base: string, root: string): string | null {
	const dir = routeToDir(route, base);
	if (!dir) return null;
	const routesDir = path.resolve(root, 'src/routes');
	const file = path.resolve(routesDir, dir, '+page.svelte');
	if (file !== routesDir && !file.startsWith(routesDir + path.sep)) return null;
	return file;
}
