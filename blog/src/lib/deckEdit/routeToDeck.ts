import * as path from 'node:path';

// Map a deck folder name (e.g. "slides") to paths under src/routes.
// Pure + path-safe: no `.` / `..` / empty segments; resolved paths must stay
// inside src/routes. Shared by the dev-only page-add / page-remove endpoints.

/** True when `deck` is a single safe path segment (a routes subfolder name). */
export function isValidDeckName(deck: string): boolean {
	const d = String(deck ?? '');
	if (!d || d.includes('/') || d.includes('\\')) return false;
	if (d === '.' || d === '..') return false;
	// Allow typical folder names: alnum, hyphen, underscore.
	return /^[a-zA-Z0-9][a-zA-Z0-9_-]*$/.test(d);
}

/**
 * Absolute path of `src/routes/<deck>/pages.ts`, or null if the deck name is
 * unusable or would escape the routes tree.
 */
export function deckToPagesFile(deck: string, root: string): string | null {
	if (!isValidDeckName(deck)) return null;
	const routesDir = path.resolve(root, 'src/routes');
	const file = path.resolve(routesDir, deck, 'pages.ts');
	if (file !== routesDir && !file.startsWith(routesDir + path.sep)) return null;
	// Must be exactly one level under routes: …/routes/<deck>/pages.ts
	const rel = path.relative(routesDir, file);
	const parts = rel.split(path.sep);
	if (parts.length !== 2 || parts[1] !== 'pages.ts') return null;
	return file;
}

/**
 * Absolute path of the slide folder `src/routes/<deck>/<slidePath>/`, or null.
 * `slidePath` must already be a validated `name.html` segment.
 */
export function deckToSlideDir(deck: string, slidePath: string, root: string): string | null {
	if (!isValidDeckName(deck)) return null;
	const seg = String(slidePath ?? '');
	if (!seg || seg.includes('/') || seg.includes('\\') || seg === '.' || seg === '..') return null;
	const routesDir = path.resolve(root, 'src/routes');
	const dir = path.resolve(routesDir, deck, seg);
	if (dir !== routesDir && !dir.startsWith(routesDir + path.sep)) return null;
	const rel = path.relative(routesDir, dir);
	const parts = rel.split(path.sep);
	if (parts.length !== 2) return null;
	return dir;
}
