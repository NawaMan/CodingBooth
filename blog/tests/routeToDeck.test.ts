import { describe, expect, it } from 'vitest';
import * as path from 'node:path';
import {
	isValidDeckName,
	deckToPagesFile,
	deckToSlideDir
} from '../src/lib/deckEdit/routeToDeck';

describe('isValidDeckName', () => {
	it('accepts ordinary deck folder names', () => {
		expect(isValidDeckName('slides')).toBe(true);
		expect(isValidDeckName('geeklight')).toBe(true);
		expect(isValidDeckName('my_deck-2')).toBe(true);
	});

	it('refuses empty, traversal, and separators', () => {
		expect(isValidDeckName('')).toBe(false);
		expect(isValidDeckName('.')).toBe(false);
		expect(isValidDeckName('..')).toBe(false);
		expect(isValidDeckName('a/b')).toBe(false);
		expect(isValidDeckName('../slides')).toBe(false);
	});
});

describe('deckToPagesFile', () => {
	const root = '/proj';

	it('resolves to src/routes/<deck>/pages.ts', () => {
		expect(deckToPagesFile('slides', root)).toBe(
			path.resolve(root, 'src/routes/slides/pages.ts')
		);
	});

	it('returns null for a bad deck name', () => {
		expect(deckToPagesFile('../x', root)).toBeNull();
		expect(deckToPagesFile('', root)).toBeNull();
	});
});

describe('deckToSlideDir', () => {
	const root = '/proj';

	it('resolves the slide folder under the deck', () => {
		expect(deckToSlideDir('slides', 'title.html', root)).toBe(
			path.resolve(root, 'src/routes/slides/title.html')
		);
	});

	it('refuses path segments in the slide name', () => {
		expect(deckToSlideDir('slides', '../x.html', root)).toBeNull();
		expect(deckToSlideDir('slides', 'a/b.html', root)).toBeNull();
	});
});
