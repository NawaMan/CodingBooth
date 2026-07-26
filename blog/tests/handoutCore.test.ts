import { describe, expect, it } from 'vitest';
import {
	CSS_PX_PER_IN,
	DEFAULT_BASE_FONT,
	DEFAULT_DECK,
	GRID_TILE_W,
	MARGIN_IN,
	MAX_SIDE_IN,
	NOTES_IN,
	NOTES_THUMB_W,
	deckGeometry,
	deckSurface,
	gridPageRule,
	handoutRefusalText,
	handoutSheets,
	notesGridPageRule,
	pageRule,
	refusedSummary,
	sheetMetrics,
	surfaceStyle,
	thumb
} from '$lib/handout/handoutCore';
import type { Page } from '$lib/utils/navigate';
import type { Blocker } from '$lib/capture/captureCore';

// The pure layer behind "the whole deck as one printable document". Everything here is
// arithmetic that ends up inside a CSS declaration, which is what makes it worth testing
// in isolation: a printer given `@page { size: NaNin NaNin }` does not ignore the rule and
// carry on — it falls back to some default paper, and the handout silently prints at the
// wrong size. So the interesting cases are the malformed ones.

const deck: Array<Page> = [
	{ path: 'title.html', title: 'Title' },
	{ path: 'intro.html', title: 'Intro' },
	{ path: 'appendix-gc.html', title: 'Appendix — GC', hidden: true },
	{ path: 'outro.html', title: 'Outro' }
];

describe('deckGeometry', () => {
	it('defaults to the 1920x1080 canvas when a deck says nothing', () => {
		expect(deckGeometry(undefined)).toEqual(DEFAULT_DECK);
		expect(deckGeometry(null)).toEqual(DEFAULT_DECK);
		expect(deckGeometry({})).toEqual(DEFAULT_DECK);
	});

	it('takes a deck at its word when it declares a canvas', () => {
		expect(deckGeometry({ width: 1080, height: 1920 })).toEqual({ width: 1080, height: 1920 });
	});

	it('rejects a canvas that is not one, dimension by dimension', () => {
		// Zero, negative, NaN, Infinity and the wrong type are all "no canvas", not a canvas
		// of size zero — and each is replaced only where it is wrong.
		expect(deckGeometry({ width: 0, height: 1080 })).toEqual(DEFAULT_DECK);
		expect(deckGeometry({ width: -1920, height: 1080 })).toEqual(DEFAULT_DECK);
		expect(deckGeometry({ width: NaN, height: 1080 })).toEqual(DEFAULT_DECK);
		expect(deckGeometry({ width: Infinity, height: 1080 })).toEqual(DEFAULT_DECK);
		expect(deckGeometry({ width: '1920' as unknown as number, height: 1080 })).toEqual(
			DEFAULT_DECK
		);
		// The good half survives the bad half.
		expect(deckGeometry({ width: 1080, height: 0 })).toEqual({ width: 1080, height: 1080 });
	});
});

describe('deckSurface / surfaceStyle', () => {
	it('gives a silent deck GeekPresent’s own defaults', () => {
		expect(deckSurface(undefined)).toEqual({
			width: 1920,
			height: 1080,
			baseFontSize: DEFAULT_BASE_FONT,
			deckClass: '',
			background: '',
			font: ''
		});
	});

	it('carries the whole surface a deck declares, not just its size', () => {
		// Everything here is a prop the deck's +layout.svelte hands to <SlideDeck>. The handout
		// never mounts that layout, so pages.ts is the only place both can read.
		const s = deckSurface({
			width: 1080,
			height: 1920,
			baseFontSize: '1.8em',
			deckClass: 'gp-deck theme-light',
			background: 'url(bg.png)',
			font: 'Merriweather, serif'
		});
		expect(s.baseFontSize).toBe('1.8em');
		expect(s.deckClass).toBe('gp-deck theme-light');
		expect(surfaceStyle(s)).toBe(
			'--canvas-w:1080px; --canvas-h:1920px; --base-font:1.8em; --content-bg:url(bg.png); --content-font:Merriweather, serif;'
		);
	});

	it('OMITS an undeclared background rather than emitting an empty one', () => {
		// The distinction is the whole point. The CSS falls back through
		// `var(--content-bg, var(--surface-bg, #181818))`, and a var set to '' is not "no
		// opinion" — it is an opinion of nothing, which paints the slide transparent. So a deck
		// that says nothing about its background must have the property ABSENT, not blank.
		const style = surfaceStyle(deckSurface({ width: 1920, height: 1080 }));
		expect(style).toBe('--canvas-w:1920px; --canvas-h:1080px; --base-font:1.5em;');
		expect(style).not.toContain('--content-bg');
		expect(style).not.toContain('--content-font');
		// A whitespace-only declaration is not a declaration either.
		expect(surfaceStyle(deckSurface({ background: '   ' }))).not.toContain('--content-bg');
	});

	it('never emits NaN into the canvas variables', () => {
		expect(surfaceStyle(deckSurface({ width: NaN, height: -1 }))).toBe(
			'--canvas-w:1920px; --canvas-h:1080px; --base-font:1.5em;'
		);
	});
});

describe('sheetMetrics', () => {
	it('prints a 16:9 deck inside a margin, on a sheet sized to fit it', () => {
		const m = sheetMetrics({ width: 1920, height: 1080 });
		// The sheet's long side is still the standard 13.333in; the SLIDE is that less a margin
		// at each end, and the sheet's short side is whatever the slide then needs. So the
		// margin comes out the same on all four sides.
		expect(m.pageWidthIn).toBe(MAX_SIDE_IN);
		expect(m.marginIn).toBe(MARGIN_IN);
		expect(m.slideWidthIn).toBeCloseTo(MAX_SIDE_IN - 2 * MARGIN_IN, 3);
		expect(m.pageWidthIn).toBeCloseTo(m.slideWidthIn + 2 * MARGIN_IN, 3);
		expect(m.pageHeightIn).toBeCloseTo(m.slideHeightIn + 2 * MARGIN_IN, 3);
		// The slide keeps the deck's aspect — the margin does not squash it.
		expect(m.slideWidthIn / m.slideHeightIn).toBeCloseTo(1920 / 1080, 2);
	});

	it('lands the canvas EXACTLY on its printed box — the overhang bug', () => {
		// The one that matters, and the one that is invisible until a PDF is measured. Round the
		// scale first and multiply back, and 1920 canvas px come to 1280.064px against 1279.968px
		// of paper: a tenth of a pixel of overhang, which a printer reads as "the sheet overflows"
		// and answers by shrinking the whole deck. So the box is rounded once and the scale is
		// derived from it, and this is the assertion that says so.
		for (const [w, h] of [
			[1920, 1080],
			[1080, 1920],
			[1600, 900]
		]) {
			const m = sheetMetrics({ width: w, height: h });
			expect(w * m.scale).toBeCloseTo(m.slideWidthPx, 2);
			expect(m.slideWidthPx).toBeLessThanOrEqual((m.pageWidthIn - 2 * MARGIN_IN) * CSS_PX_PER_IN + 0.01);
		}
	});

	it('transposes a portrait deck onto a portrait page — the same maths, no special case', () => {
		const landscape = sheetMetrics({ width: 1920, height: 1080 });
		const portrait = sheetMetrics({ width: 1080, height: 1920 });
		// Scaling from the LONGEST side is what does this: swap the canvas, swap the page,
		// and the physical size of the printed slide is unchanged.
		expect(portrait.pageWidthIn).toBeCloseTo(landscape.pageHeightIn, 3);
		expect(portrait.pageHeightIn).toBeCloseTo(landscape.pageWidthIn, 3);
		expect(portrait.scale).toBeCloseTo(landscape.scale, 4);
	});

	it('grows the PAGE for the notes band, not the slide', () => {
		const plain = sheetMetrics({ width: 1920, height: 1080 }, false);
		const noted = sheetMetrics({ width: 1920, height: 1080 }, true);
		expect(noted.pageHeightIn).toBeCloseTo(plain.pageHeightIn + NOTES_IN, 3);
		// The slide is the same slide: same width, same band, same scale. Notes are added
		// below it — they never shrink it.
		expect(noted.pageWidthIn).toBe(plain.pageWidthIn);
		expect(noted.slideHeightIn).toBe(plain.slideHeightIn);
		expect(noted.scale).toBe(plain.scale);
		expect(noted.notesHeightPx).toBe(NOTES_IN * CSS_PX_PER_IN);
		expect(plain.notesHeightPx).toBe(0);
		expect(noted.notes).toBe(true);
		expect(plain.notes).toBe(false);
	});

	it('never yields NaN, whatever it is handed', () => {
		// The one failure mode that matters: every number here reaches a CSS declaration.
		for (const bad of [null, undefined, {}, { width: 0, height: 0 }, { width: NaN, height: NaN }]) {
			const m = sheetMetrics(bad as never, true);
			for (const n of [
				m.pageWidthIn,
				m.pageHeightIn,
				m.slideWidthIn,
				m.slideHeightIn,
				m.scale,
				m.slideWidthPx,
				m.slideHeightPx
			]) {
				expect(Number.isFinite(n)).toBe(true);
				expect(n).toBeGreaterThan(0);
			}
		}
	});
});

describe('the two overview layouts', () => {
	it('prints the thumbnail grid on a landscape Letter page, the notes grid on a portrait one', () => {
		expect(gridPageRule()).toBe('@page { size: 11in 8.5in; margin: 0.5in; }');
		expect(notesGridPageRule()).toBe('@page { size: 8.5in 11in; margin: 0.5in; }');
	});

	it('scales a thumbnail to a fixed width, aspect kept — a true miniature', () => {
		const t = thumb({ width: 1920, height: 1080 }, GRID_TILE_W);
		expect(t.widthPx).toBe(GRID_TILE_W);
		expect(t.scale).toBeCloseTo(GRID_TILE_W / 1920, 5);
		// Height follows the deck's aspect, not the page's.
		expect(t.heightPx / t.widthPx).toBeCloseTo(1080 / 1920, 3);
	});

	it('transposes for a portrait deck, and never yields NaN', () => {
		const portrait = thumb({ width: 1080, height: 1920 }, NOTES_THUMB_W);
		expect(portrait.heightPx / portrait.widthPx).toBeCloseTo(1920 / 1080, 3);
		const junk = thumb(null, NaN);
		expect(Number.isFinite(junk.scale)).toBe(true);
		expect(junk.widthPx).toBeGreaterThan(0);
		expect(junk.heightPx).toBeGreaterThan(0);
	});
});

describe('pageRule', () => {
	it('is a complete @page rule: the sheet, and the margin the slide sits inside', () => {
		const rule = pageRule(sheetMetrics({ width: 1920, height: 1080 }));
		expect(rule).toBe('@page { size: 13.333in 7.937in; margin: 0.5in; }');
	});

	it('emits no NaN into the stylesheet even from a junk deck', () => {
		expect(pageRule(sheetMetrics({ width: NaN, height: NaN }))).not.toContain('NaN');
	});
});

describe('handoutSheets', () => {
	it('numbers every slide in document order, counting from one', () => {
		const sheets = handoutSheets(deck);
		expect(sheets.map((s) => s.number)).toEqual([1, 2, 3, 4]);
		expect(sheets.map((s) => s.path)).toEqual([
			'title.html',
			'intro.html',
			'appendix-gc.html',
			'outro.html'
		]);
	});

	it('PRINTS a hidden appendix, and labels it', () => {
		// The deck's own navigation skips a `hidden` slide, because the speaker will jump to
		// it if they need it. A printed document has no jumps — dropping it would silently
		// lose content the deck contains. So it is printed, and flagged.
		const sheets = handoutSheets(deck);
		expect(sheets).toHaveLength(4);
		const appendix = sheets.find((s) => s.path === 'appendix-gc.html');
		expect(appendix?.appendix).toBe(true);
		expect(sheets.filter((s) => s.appendix)).toHaveLength(1);
	});

	it('falls back to the path when an entry has no title, and drops one with no path', () => {
		const sheets = handoutSheets([
			{ path: 'untitled.html' } as Page,
			{ title: 'Nowhere' } as Page,
			null as unknown as Page
		]);
		expect(sheets).toHaveLength(1);
		expect(sheets[0]).toMatchObject({ number: 1, path: 'untitled.html', title: 'untitled.html' });
	});

	it('survives a deck that is not a list', () => {
		expect(handoutSheets(null)).toEqual([]);
		expect(handoutSheets(undefined)).toEqual([]);
		expect(handoutSheets('slides' as unknown as Array<Page>)).toEqual([]);
	});
});

describe('the refusal — what will not print', () => {
	const embed = (label: string): Blocker => ({ kind: 'embed', label });

	it('names a single embed rather than counting it', () => {
		expect(handoutRefusalText([embed('www.youtube.com')])).toBe(
			'www.youtube.com is a live embed — it cannot print'
		);
	});

	it('counts, once naming them stops being a sentence', () => {
		expect(handoutRefusalText([embed('a'), embed('b')])).toBe(
			'2 live embeds on this slide — they cannot print'
		);
	});

	it('says nothing when there is nothing to refuse', () => {
		expect(handoutRefusalText([])).toBe('');
		expect(handoutRefusalText(null)).toBe('');
	});

	it('summarises the document: named while a reader would read them, counted after', () => {
		expect(refusedSummary([])).toBe('');
		expect(refusedSummary(['Website'])).toBe(
			'1 slide has a live embed that will not print: Website'
		);
		expect(refusedSummary(['Website', 'YouTube'])).toBe(
			'2 slides have a live embed that will not print: Website, YouTube'
		);
		expect(refusedSummary(['a', 'b', 'c', 'd'])).toBe(
			'4 slides have a live embed that will not print'
		);
	});
});
