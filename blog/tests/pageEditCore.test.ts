// Pure unit tests for deck structure editing (pages.ts insert/remove, paths, scaffolds).
// The interesting cases are the refusals — same bargain as wire-og / patchSource.
import { describe, expect, it } from 'vitest';
import {
	slugifyStem,
	normalizeSlidePath,
	isValidSlidePath,
	formatPagesEntry,
	listEntryPaths,
	insertPagesEntry,
	removePagesEntry,
	scaffoldPage,
	LAYOUT_JS,
	normalizeTemplate
} from '../src/lib/deckEdit/pageEditCore';

const PAGES = `export const pages = [
    { path: "title.html",             title: "Title" },
    { path: "intro.html",             title: "Intro" },
    { path: "outro.html",             title: "Outro" },
];
`;

describe('slugifyStem', () => {
	it('turns a title into a lowercase hyphenated stem', () => {
		expect(slugifyStem('My New Slide')).toBe('my-new-slide');
		expect(slugifyStem('  Hello, World!  ')).toBe('hello-world');
	});

	it('falls back to "slide" for empty / pure punctuation', () => {
		expect(slugifyStem('')).toBe('slide');
		expect(slugifyStem('!!!')).toBe('slide');
		expect(slugifyStem(null as unknown as string)).toBe('slide');
	});
});

describe('normalizeSlidePath', () => {
	it('accepts name.html and adds .html when missing', () => {
		expect(normalizeSlidePath('my-slide.html')).toBe('my-slide.html');
		expect(normalizeSlidePath('My-Slide')).toBe('my-slide.html');
	});

	it('refuses traversal, separators, and bad stems', () => {
		expect(normalizeSlidePath('../x.html')).toBeNull();
		expect(normalizeSlidePath('a/b.html')).toBeNull();
		expect(normalizeSlidePath('-bad.html')).toBeNull();
		expect(normalizeSlidePath('')).toBeNull();
		expect(normalizeSlidePath('has space.html')).toBeNull();
	});
});

describe('isValidSlidePath', () => {
	it('requires the canonical form', () => {
		expect(isValidSlidePath('ok.html')).toBe(true);
		expect(isValidSlidePath('OK.html')).toBe(false); // not normalized
	});
});

describe('listEntryPaths / formatPagesEntry', () => {
	it('lists one-line entries in order', () => {
		expect(listEntryPaths(PAGES)).toEqual(['title.html', 'intro.html', 'outro.html']);
	});

	it('formats a house-style entry line', () => {
		expect(formatPagesEntry('x.html', 'Hello')).toBe('{ path: "x.html", title: "Hello" },');
	});
});

describe('insertPagesEntry', () => {
	it('appends when after is null', () => {
		const r = insertPagesEntry(PAGES, 'new.html', 'New', null);
		expect(r.ok).toBe(true);
		if (!r.ok) return;
		expect(listEntryPaths(r.source)).toEqual([
			'title.html',
			'intro.html',
			'outro.html',
			'new.html'
		]);
		expect(r.source).toContain('{ path: "new.html", title: "New" },');
	});

	it('inserts after a named path', () => {
		const r = insertPagesEntry(PAGES, 'mid.html', 'Mid', 'title.html');
		expect(r.ok).toBe(true);
		if (!r.ok) return;
		expect(listEntryPaths(r.source)).toEqual([
			'title.html',
			'mid.html',
			'intro.html',
			'outro.html'
		]);
	});

	it('refuses a duplicate path', () => {
		const r = insertPagesEntry(PAGES, 'intro.html', 'Dup', null);
		expect(r.ok).toBe(false);
		if (r.ok) return;
		expect(r.error).toMatch(/already lists/);
	});

	it('refuses a missing after path', () => {
		const r = insertPagesEntry(PAGES, 'x.html', 'X', 'nope.html');
		expect(r.ok).toBe(false);
		if (r.ok) return;
		expect(r.error).toMatch(/no pages\.ts entry/);
	});

	it('refuses an empty title', () => {
		const r = insertPagesEntry(PAGES, 'x.html', '  ', null);
		expect(r.ok).toBe(false);
	});

	it('inserts into an empty pages array', () => {
		const empty = `export const pages = [\n];\n`;
		const r = insertPagesEntry(empty, 'only.html', 'Only', null);
		expect(r.ok).toBe(true);
		if (!r.ok) return;
		expect(listEntryPaths(r.source)).toEqual(['only.html']);
	});
});

describe('removePagesEntry', () => {
	it('drops the matching one-line entry', () => {
		const r = removePagesEntry(PAGES, 'intro.html');
		expect(r.ok).toBe(true);
		if (!r.ok) return;
		expect(listEntryPaths(r.source)).toEqual(['title.html', 'outro.html']);
		expect(r.source).not.toContain('intro.html');
	});

	it('refuses a missing path', () => {
		const r = removePagesEntry(PAGES, 'ghost.html');
		expect(r.ok).toBe(false);
	});

	it('leaves non-entry lines alone', () => {
		const r = removePagesEntry(PAGES, 'title.html');
		expect(r.ok).toBe(true);
		if (!r.ok) return;
		expect(r.source).toContain('export const pages');
	});
});

describe('scaffoldPage / LAYOUT_JS', () => {
	it('ships the two required layout lines', () => {
		expect(LAYOUT_JS).toContain('export const prerender = true');
		expect(LAYOUT_JS).toContain('export const trailingSlash = "never"');
	});

	it('scaffolds ContentPage by default with ViewSource (so ☰ EDIT works)', () => {
		const s = scaffoldPage('content', 'Hello', { deck: 'slides', path: 'hello.html' });
		expect(s).toContain('ContentPage');
		expect(s).toContain('title="Hello"');
		expect(s).not.toContain('TitlePage');
		expect(s).toContain('ViewSource');
		expect(s).toContain("from './+page.svelte?raw'");
		expect(s).toContain('src/routes/slides/hello.html/+page.svelte');
	});

	it('scaffolds TitlePage when asked, still with ViewSource', () => {
		const s = scaffoldPage('title', 'Deck', { deck: 'slides', path: 'deck.html' });
		expect(s).toContain('TitlePage');
		expect(s).toContain('Deck');
		expect(s).toContain('ViewSource');
	});

	it('normalizeTemplate defaults to content', () => {
		expect(normalizeTemplate('title')).toBe('title');
		expect(normalizeTemplate('nope')).toBe('content');
		expect(normalizeTemplate(null)).toBe('content');
	});
});
