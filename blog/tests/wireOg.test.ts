// Unit tests for the pages.ts OG-image patcher (utils/wire-og.mjs).
//
// This is a tool that EDITS SOURCE, so the tests are about what it refuses to do as much as
// what it does — the same bargain patchSource.ts makes for ADJUST's SAVE: anything it cannot
// confidently place is left alone and reported, never guessed.
import { describe, expect, it } from 'vitest';
// Plain .mjs build tooling, deliberately outside src/ so it never reaches the app bundle —
// but still typechecked (svelte-check runs with checkJs), hence the JSDoc types over there.
import { ogImagePath, wireOgImages } from '../utils/wire-og.mjs';

const PAGES = `export const pages = [
    { path: "title.html",             title: "Title" },
    { path: "intro.html",             title: "Intro" },
    { path: "custom.html",            title: "Custom", image: "og/hand-made.png" },
    { path: "hidden.html",            title: "Appendix", hidden: true },
];
`;

describe('ogImagePath', () => {
	it('is the site-relative path seo/config.resolveImage expects', () => {
		expect(ogImagePath('og/slides', 'title.html')).toBe('og/slides/title.png');
		expect(ogImagePath('/og/slides/', 'title.html')).toBe('og/slides/title.png');
	});
});

describe('wireOgImages', () => {
	it('adds image: to the slides we captured', () => {
		const { source, added } = wireOgImages(PAGES, 'og/slides', ['title.html', 'intro.html']);
		expect(added).toEqual(['title.html', 'intro.html']);
		expect(source).toContain('{ path: "title.html",             title: "Title", image: "og/slides/title.png" },');
		expect(source).toContain('image: "og/slides/intro.png"');
	});

	it('never overwrites an image the AUTHOR already set', () => {
		// A slide may point at a hand-made card. The tool does not outrank the person.
		const { source, added, kept } = wireOgImages(PAGES, 'og/slides', ['custom.html']);
		expect(added).toEqual([]);
		expect(kept).toEqual(['custom.html']);
		expect(source).toContain('image: "og/hand-made.png"');
		expect(source).not.toContain('og/slides/custom.png');
	});

	it('invents no URL for a PNG that does not exist', () => {
		// Only slides we actually captured get a card — otherwise the tag 404s on a timeline.
		const { source } = wireOgImages(PAGES, 'og/slides', ['title.html']);
		expect(source).toContain('og/slides/title.png');
		expect(source).not.toContain('og/slides/intro.png');
	});

	it('is idempotent — running twice changes nothing the second time', () => {
		const once = wireOgImages(PAGES, 'og/slides', ['title.html', 'intro.html']).source;
		const twice = wireOgImages(once, 'og/slides', ['title.html', 'intro.html']);
		expect(twice.source).toBe(once);
		expect(twice.added).toEqual([]);
	});

	it('carries the entry\'s other fields through untouched', () => {
		const { source } = wireOgImages(PAGES, 'og/slides', ['hidden.html']);
		expect(source).toContain('title: "Appendix", hidden: true, image: "og/slides/hidden.png"');
	});

	it('leaves comments, scaffolding and unrelated lines byte-for-byte', () => {
		const src = `// a comment { path: "fake.html" }\nexport const pages = [\n    { path: "title.html", title: "T" },\n];\n`;
		const { source } = wireOgImages(src, 'og/slides', ['title.html']);
		expect(source.split('\n')[0]).toBe('// a comment { path: "fake.html" }');
		expect(source.endsWith('];\n')).toBe(true);
	});

	it('REFUSES an entry it cannot place the field in, and says which', () => {
		// A nested object or an inline comment means we would be guessing where `image` goes.
		// Leaving it for a human beats a bad edit to someone's source file.
		const tricky = `export const pages = [
    { path: "a.html", title: "A", meta: { x: 1 } },
    { path: "b.html", title: "B" }, // note
];
`;
		const { source, added, skipped } = wireOgImages(tricky, 'og/slides', ['a.html', 'b.html']);
		expect(skipped).toEqual(['a.html']);
		expect(added).toEqual(['b.html']);
		expect(source).toContain('meta: { x: 1 } },'); // untouched
	});

	it('is total for junk', () => {
		expect(wireOgImages('', 'og', ['a.html']).source).toBe('');
		expect(wireOgImages(null as never, 'og', []).source).toBe('');
		expect(wireOgImages(PAGES, 'og', null as never).added).toEqual([]);
	});
});
