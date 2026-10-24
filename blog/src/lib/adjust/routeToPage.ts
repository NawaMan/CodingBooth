import * as path from 'node:path';
import { existsSync, readdirSync, statSync } from 'node:fs';

// Shared route → `src/routes/<…>/+page.svelte` mapping for the dev-only write
// endpoints (ADJUST SAVE and ViewSource SAVE). Kept pure so tests can pin the
// safety rules without spinning up a Vite server.
//
// Rules:
//   - strip query/hash and an optional kit `base`
//   - no empty / `.` / `..` segments (path traversal)
//   - resolved file must stay inside `src/routes`
//   - SvelteKit route groups `(name)` do not appear in the URL; when the literal
//     path has no +page.svelte, walk the tree allowing those folders to be skipped
//     (e.g. `/references/how-to.html` → `references/(hub)/how-to.html/+page.svelte`).

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

/** True when `name` is a SvelteKit route group folder (`(hub)`, not `(a/b)`). */
export function isRouteGroupSegment(name: string): boolean {
	return (
		typeof name === 'string' &&
		name.length >= 3 &&
		name.startsWith('(') &&
		name.endsWith(')') &&
		!name.includes('/') &&
		!name.includes('\\') &&
		name !== '(..)' &&
		name !== '(.)'
	);
}

/**
 * Walk `routesDir` matching URL `segments`, optionally stepping into `(group)`
 * folders without consuming a segment. Returns the slide folder that holds
 * `+page.svelte`, or null.
 */
export function resolveSlideDir(
	routesDir: string,
	segments: string[],
	// Injectable for tests — defaults to real fs.
	io: {
		readdir: (dir: string) => string[];
		isDir: (p: string) => boolean;
		hasPage: (dir: string) => boolean;
	} = {
		readdir: (dir) => {
			try {
				return readdirSync(dir);
			} catch {
				return [];
			}
		},
		isDir: (p) => {
			try {
				return statSync(p).isDirectory();
			} catch {
				return false;
			}
		},
		hasPage: (dir) => existsSync(path.join(dir, '+page.svelte'))
	}
): string | null {
	if (!routesDir || !Array.isArray(segments)) return null;

	function walk(current: string, segs: string[]): string | null {
		// Stay inside routesDir (path traversal via weird links).
		const cur = path.resolve(current);
		const root = path.resolve(routesDir);
		if (cur !== root && !cur.startsWith(root + path.sep)) return null;

		if (segs.length === 0) {
			return io.hasPage(cur) ? cur : null;
		}

		const entries = io.readdir(cur);
		const [head, ...rest] = segs;
		if (!head || head === '.' || head === '..') return null;

		// Exact segment first (stable, preferred over ambiguous group walks).
		if (entries.includes(head)) {
			const next = path.join(cur, head);
			if (io.isDir(next)) {
				const hit = walk(next, rest);
				if (hit) return hit;
			}
		}

		// Then any route group at this level — groups do not consume a URL segment.
		for (const e of entries) {
			if (!isRouteGroupSegment(e)) continue;
			const next = path.join(cur, e);
			if (!io.isDir(next)) continue;
			const hit = walk(next, segs);
			if (hit) return hit;
		}
		return null;
	}

	return walk(routesDir, segments);
}

/**
 * Absolute path of the slide's `+page.svelte`, or null if the route is unusable
 * or would resolve outside `src/routes`.
 *
 * Prefers a filesystem match that understands `(route groups)`. Falls back to the
 * literal `src/routes/<url-path>/+page.svelte` when nothing is on disk yet (so SAVE
 * targets for brand-new folders stay predictable).
 */
export function routeToPageFile(route: string, base: string, root: string): string | null {
	const dir = routeToDir(route, base);
	if (!dir) return null;
	const routesDir = path.resolve(root, 'src/routes');
	const segments = dir.split('/');

	const slideDir = resolveSlideDir(routesDir, segments);
	if (slideDir) {
		const file = path.resolve(slideDir, '+page.svelte');
		if (file !== routesDir && !file.startsWith(routesDir + path.sep)) return null;
		return file;
	}

	// Literal path — may not exist yet (caller reports 404 on read).
	const file = path.resolve(routesDir, dir, '+page.svelte');
	if (file !== routesDir && !file.startsWith(routesDir + path.sep)) return null;
	return file;
}
