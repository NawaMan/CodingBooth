import { describe, expect, it } from 'vitest';
import * as path from 'node:path';
import { routeToDir, routeToPageFile } from '../src/lib/adjust/routeToPage';

// Pure mapping for the dev write endpoints — ADJUST SAVE and ViewSource SAVE.
// The interesting cases are the ones that must REFUSE (traversal, empty, escape).

describe('routeToDir', () => {
	it('maps a slide pathname to its route folder', () => {
		expect(routeToDir('/slides/title.html', '/')).toBe('slides/title.html');
		expect(routeToDir('/slides/title.html/', '/')).toBe('slides/title.html');
	});

	it('strips query and hash', () => {
		expect(routeToDir('/slides/title.html?adjust', '/')).toBe('slides/title.html');
		expect(routeToDir('/slides/title.html#x', '/')).toBe('slides/title.html');
	});

	it('strips kit base when present', () => {
		expect(routeToDir('/talks/slides/title.html', '/talks')).toBe('slides/title.html');
	});

	it('refuses empty, traversal, and empty segments', () => {
		expect(routeToDir('/', '/')).toBeNull();
		expect(routeToDir('/../secret', '/')).toBeNull();
		expect(routeToDir('/slides/../etc', '/')).toBeNull();
		expect(routeToDir('/slides//title.html', '/')).toBeNull();
		expect(routeToDir('/slides/./title.html', '/')).toBeNull();
	});
});

describe('routeToPageFile', () => {
	const root = '/proj';

	it('resolves to src/routes/<dir>/+page.svelte', () => {
		const file = routeToPageFile('/slides/title.html', '/', root);
		expect(file).toBe(path.resolve(root, 'src/routes/slides/title.html/+page.svelte'));
	});

	it('returns null for an unmappable route', () => {
		expect(routeToPageFile('/../x', '/', root)).toBeNull();
		expect(routeToPageFile('/', '/', root)).toBeNull();
	});
});
