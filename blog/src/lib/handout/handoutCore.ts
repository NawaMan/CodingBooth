/*
  Handout — the pure decision layer behind the whole deck as one printable document
  (see routes/_handout/[deck].html, which owns the impure half: the globs, the DOM scan and
  window.print()).

  The premise is that the browser is already a PDF engine, so a handout needs no
  dependency and no export pipeline — it needs a page that stacks every slide and the
  three CSS rules that tell the printer where one slide ends and the next begins. What
  is genuinely hard is none of that: it is the ARITHMETIC of putting a 1920x1080 canvas
  onto a sheet of paper, and that is what lives here.

  Two facts make the arithmetic tractable:

  - A CSS pixel is an ABSOLUTE unit when printing: 96px is one inch, on every printer.
    So a slide authored at 1920x1080 has a true printed size, and the only question is
    what to scale it by.
  - `@page { size: … }` lets the SHEET take the slide's shape rather than the slide
    being letterboxed onto A4. A 16:9 deck prints edge-to-edge on a 16:9 page — which
    is what a conference asking for "the deck as a PDF" actually means — and a portrait
    deck (routes/portrait is 1080x1920) prints on a portrait page, from the same maths,
    with no special case.

  Total and side-effect free, in the drawCore/captureCore tradition. A deck that reports
  a zero, negative or NaN canvas yields the 1920x1080 default rather than a `NaNin` page
  size, because a malformed @page rule is not ignored by the printer — it takes the whole
  print job down to some browser default, which looks like the feature is broken.
*/

import type { Page } from '$lib/utils/navigate';
import type { Blocker } from '$lib/capture/captureCore';

/** CSS's own definition, not an approximation: `1in == 96px` in the spec. It is what
    makes a printed slide's size knowable at all. */
export const CSS_PX_PER_IN = 96;

/** The longest side of a printed SHEET. 13.333in is the long side of the standard 16:9
    slide page (what PowerPoint and Keynote export), so a landscape deck prints at the size
    a conference expects, and a portrait deck prints on its transpose. */
export const MAX_SIDE_IN = 13.333;

/** The white border around the printed slide, on every side.

    Not decoration, and it earns its half-inch three times over.

    A real printer cannot reach the edge of the paper: given a full-bleed sheet it either crops
    the slide or shrinks it by some amount of its own choosing, and either way the deck comes
    out subtly wrong on someone else's printer. A declared margin is the deck deciding, rather
    than the hardware deciding for it.

    It is what makes a browser that IGNORES the page size below degrade gracefully. Not every
    engine honours `@page { size }` (Chrome and Edge do); one that prints on A4 instead scales
    the sheet to fit, and with the slide centred inside a margin that reads as a slide on a page
    rather than as a slide shoved into a corner.

    And — the reason it is 0.5in rather than the 0.25in it started at — THE MARGIN IS WHERE THE
    BROWSER PUTS ITS OWN HEADER AND FOOTER. Every engine prints the document title at the top of
    the sheet and the page number at the bottom (unless the reader turns them off), and it draws
    them INSIDE the page margin at a fixed inset from the paper's edge. Give it a quarter inch
    and it has nowhere to put them, so they land on top of the slide. Half an inch is the room
    they need: the title sits above the slide, the page number below it, and the slide is clear
    of both. */
export const MARGIN_IN = 0.5;

/** The band added below the slide when notes are printed. Three inches is about
    fifteen lines at the note's own font size — enough for a real note, and it keeps the
    slide the dominant thing on the page. */
export const NOTES_IN = 3;

/** A deck's authoring canvas. */
export interface DeckGeometry {
	width: number;
	height: number;
}

/** What a deck is unless it says otherwise. A deck whose canvas is NOT this must export
    `deck` from its own pages.ts — see routes/portrait/pages.ts, which does, and whose
    +layout.svelte reads the same export, so the two cannot drift apart. */
export const DEFAULT_DECK: DeckGeometry = { width: 1920, height: 1080 };

/** SlideDeck's own default (SlideDeck.svelte: `export let baseFontSize`). It is the lever every
    em-sized component scales from, so a handout that forgot it would print the whole deck at a
    different size to the one it is presented at — legible, and wrong.

    It must therefore be kept EQUAL to SlideDeck's default, and there is no way to make the
    compiler say so: the handout never mounts SlideDeck, so it cannot read the prop's default and
    has to restate it. `tests/handoutCore.test.ts` pins the two together instead. */
export const DEFAULT_BASE_FONT = '1.5em';

/** A deck's SURFACE: everything a slide is drawn on, and every one of these is a prop the
    deck's +layout.svelte hands to <SlideDeck>.

    They live in pages.ts (`export const deck = {...}`) rather than in the layout because two
    things need them and only one of them is the deck. The handout never mounts the layout —
    that is the whole trick, since the layout's shell would gate the slides away — so the
    layout's props are invisible to it. Declared once in pages.ts and READ BY BOTH, they
    cannot drift; declared in the layout, the handout would have to guess, and a guess here
    prints a light deck on a black page. */
export interface DeckMeta {
	width?: number;
	height?: number;
	/** SlideDeck's `baseFontSize` — the em lever. */
	baseFontSize?: string;
	/** SlideDeck's `deckClass` — the theme class ('gp-deck theme-light'). */
	deckClass?: string;
	/** SlideDeck's `contentBackground`. */
	background?: string;
	/** SlideDeck's `contentFont`. */
	font?: string;
}

export interface DeckSurface extends DeckGeometry {
	baseFontSize: string;
	deckClass: string;
	background: string;
	font: string;
}

/** A positive, finite number, or the fallback. Anything else — a missing export, a
    hand-edited `0`, a `width: undefined` — is not a canvas. */
function positive(n: unknown, fallback: number): number {
	return typeof n === 'number' && Number.isFinite(n) && n > 0 ? n : fallback;
}

/** Round to a printable precision. `13.333333333333334in` is legal CSS but noise in a
    <style> block a human may well read. */
function round(n: number, places: number): number {
	const f = 10 ** places;
	return Math.round(n * f) / f;
}

/** A deck's canvas, from whatever its pages.ts exported (possibly nothing). */
export function deckGeometry(meta: Partial<DeckGeometry> | null | undefined): DeckGeometry {
	return {
		width: positive(meta?.width, DEFAULT_DECK.width),
		height: positive(meta?.height, DEFAULT_DECK.height)
	};
}

/** A string a deck actually declared, or ''. */
function declared(s: unknown): string {
	return typeof s === 'string' && s.trim().length > 0 ? s : '';
}

/** A deck's surface, from whatever its pages.ts exported (possibly nothing). */
export function deckSurface(meta: DeckMeta | null | undefined): DeckSurface {
	return {
		...deckGeometry(meta),
		baseFontSize: declared(meta?.baseFontSize) || DEFAULT_BASE_FONT,
		deckClass: declared(meta?.deckClass),
		background: declared(meta?.background),
		font: declared(meta?.font)
	};
}

/** The surface as CSS custom properties — the same ones, in the same order, that SlideDeck
    sets on its own container (SlideDeck.svelte, the `--canvas-w: …` style attribute).

    An UNDECLARED background or font is left OUT rather than emitted empty, and that is the
    load-bearing detail: the CSS below falls back through `var(--content-bg, var(--surface-bg,
    #181818))`, so a var set to the empty string is not "no opinion" — it is an opinion of
    nothing, and it paints the slide transparent. Same reason SlideDeck writes them
    conditionally. */
export function surfaceStyle(s: DeckSurface): string {
	let css = `--canvas-w:${s.width}px; --canvas-h:${s.height}px; --base-font:${s.baseFontSize};`;
	if (s.background) css += ` --content-bg:${s.background};`;
	if (s.font) css += ` --content-font:${s.font};`;
	return css;
}

/** The printed geometry of one sheet. */
export interface SheetMetrics {
	/** `@page` width, inches — the slide, plus a margin on each side. */
	pageWidthIn: number;
	/** `@page` height, inches — the slide, the notes band if any, plus a margin each side. */
	pageHeightIn: number;
	/** `@page` margin, inches. The browser lays it out; we only have to not fill it. */
	marginIn: number;
	/** The printed SLIDE, inches — inside the margin. */
	slideWidthIn: number;
	slideHeightIn: number;
	/** CSS px per canvas px — what the slide is `transform: scale()`d by. */
	scale: number;
	/** The printed slide's box in CSS px — exactly `slide*In * 96`, which is exactly what the
	    canvas comes to when scaled. The two must agree to the pixel; see below. */
	slideWidthPx: number;
	slideHeightPx: number;
	/** The notes band below the slide, CSS px (0 when notes are off). */
	notesHeightPx: number;
	notes: boolean;
}

/** Fit a deck's canvas onto a sheet: longest side to MAX_SIDE_IN less its margins, aspect
    preserved, and the paper sized to the result.

    Two details are load-bearing.

    The scale comes off the LONGEST side, not the width, and that one line is what makes a
    portrait deck work with no branch: 1920x1080 is bound by its width and 1080x1920 by its
    height, and both come out the same physical size.

    And the scale is derived FROM the printed pixel size rather than the printed size being
    derived from the scale. It reads backwards and it is the whole difference between a slide
    that fits the paper and one that does not: rounding the scale first (0.666650 -> 0.6667)
    made the canvas 1280.064px against 1279.968px of paper — an overhang of a tenth of a
    pixel, invisible on screen, and enough for a printer to decide the sheet overflows and
    shrink the entire deck to fit. So the printed box is rounded once, and the scale is
    whatever lands the canvas on exactly that box. */
export function sheetMetrics(
	deck: Partial<DeckGeometry> | null | undefined,
	notes: boolean = false
): SheetMetrics {
	const { width, height } = deckGeometry(deck);

	// The slide's own long side: the sheet's, less the margin it must leave at both ends.
	const slideMaxIn = MAX_SIDE_IN - 2 * MARGIN_IN;
	const inPerPx = slideMaxIn / Math.max(width, height);
	const slideWidthIn = round(width * inPerPx, 3);
	const slideHeightIn = round(height * inPerPx, 3);

	const slideWidthPx = round(slideWidthIn * CSS_PX_PER_IN, 2);
	const slideHeightPx = round(slideHeightIn * CSS_PX_PER_IN, 2);
	const scale = round(slideWidthPx / width, 6); // lands the canvas ON the box, not near it

	const withNotes = notes === true;
	const notesHeightPx = withNotes ? NOTES_IN * CSS_PX_PER_IN : 0;

	return {
		pageWidthIn: round(slideWidthIn + 2 * MARGIN_IN, 3),
		pageHeightIn: round(slideHeightIn + (withNotes ? NOTES_IN : 0) + 2 * MARGIN_IN, 3),
		marginIn: MARGIN_IN,
		slideWidthIn,
		slideHeightIn,
		scale,
		slideWidthPx,
		slideHeightPx,
		notesHeightPx,
		notes: withNotes
	};
}

/** The `@page` rule for these metrics.

    Emitted into <svelte:head> rather than written in the component's <style>, because it
    depends on the deck (which varies per route) and on the notes toggle (which varies at
    runtime) — and `@page` takes no class, so it cannot be selected for. A string is the
    honest shape of the thing, and being a string it is directly testable. */
export function pageRule(m: SheetMetrics): string {
	return `@page { size: ${m.pageWidthIn}in ${m.pageHeightIn}in; margin: ${m.marginIn}in; }`;
}

/* ── The two OVERVIEW layouts ─────────────────────────────────────────────────────────
   Beside the one-slide-per-page handout above there are two compact ones, both on a standard
   Letter page (they are DOCUMENTS, not slide-shaped like the full handout):

   - the GRID: a contact-sheet of thumbnails, landscape, no notes.
   - the NOTES GRID: one row per slide, thumbnail LEFT and the note RIGHT, portrait.

   Both scale the real slide down to a fixed thumbnail width and let the browser paginate — as
   many tiles/rows as fit, a page break between. The tile width is fixed (not derived from the
   page) so a thumbnail is a knowable size regardless of the deck's canvas; the SCALE is then
   whatever lands the deck's width on that width. */
export const LETTER_LONG_IN = 11;
export const LETTER_SHORT_IN = 8.5;

/** Grid tile width and notes-grid thumbnail width, in CSS px. Chosen so ~4 tiles fit across a
    landscape page, and a portrait notes row leaves room for the note beside the thumbnail. */
export const GRID_TILE_W = 236;
export const NOTES_THUMB_W = 300;

/** `@page` for the landscape thumbnail grid. */
export function gridPageRule(): string {
	return `@page { size: ${LETTER_LONG_IN}in ${LETTER_SHORT_IN}in; margin: ${MARGIN_IN}in; }`;
}

/** `@page` for the portrait notes grid. */
export function notesGridPageRule(): string {
	return `@page { size: ${LETTER_SHORT_IN}in ${LETTER_LONG_IN}in; margin: ${MARGIN_IN}in; }`;
}

/** A thumbnail's geometry: the scale that lands the deck's canvas on `targetWidthPx`, and the
    box that scaled canvas then occupies. Total and NaN-safe, like sheetMetrics. */
export interface Thumb {
	scale: number;
	widthPx: number;
	heightPx: number;
}
export function thumb(
	deck: Partial<DeckGeometry> | null | undefined,
	targetWidthPx: number
): Thumb {
	const { width, height } = deckGeometry(deck);
	const w = positive(targetWidthPx, GRID_TILE_W);
	const scale = round(w / width, 6);
	return { scale, widthPx: round(w, 2), heightPx: round(height * scale, 2) };
}

/** One slide, as a printed sheet. */
export interface Sheet {
	/** Sequential position in the printed DOCUMENT, counting from 1. */
	number: number;
	path: string;
	title: string;
	/** A `hidden` slide — an appendix. Printed (it is a real slide and a reader holding
	    the paper cannot follow an <AppendixLink>), but labelled, because it is NOT in the
	    deck's linear order and a reader should not think they missed a turn. */
	appendix: boolean;
}

/** Every slide of a deck, in document order.

    Unlike the deck's own navigation this does NOT drop `hidden` slides. Paging skips an
    appendix because the speaker will jump to it if they need it; a printed document has
    no jumps, so leaving it out would silently lose content the deck contains. It is
    labelled instead. A junk entry (no path) is dropped rather than printed as a blank
    sheet with a blank title. */
export function handoutSheets(pages: Array<Page> | null | undefined): Sheet[] {
	if (!Array.isArray(pages)) return [];
	const out: Sheet[] = [];
	for (const p of pages) {
		if (!p || typeof p.path !== 'string' || p.path.length === 0) continue;
		out.push({
			number: out.length + 1,
			path: p.path,
			title: typeof p.title === 'string' && p.title.length > 0 ? p.title : p.path,
			appendix: p.hidden === true
		});
	}
	return out;
}

/** What a sheet says when it cannot honestly be printed.

    Same bargain as CAPTURE (captureCore.refusalText), for the same reason and against the
    same `Blocker`: an `<iframe>` is a separate document, and a printer given one prints a
    blank rectangle or nothing at all. So the handout does not pretend. It NAMES the embed
    on the sheet, in ink, so the reader of the paper knows a live thing stood there rather
    than wondering whether the slide was empty. The wording differs from capture's because
    the failure differs — capture refuses to produce a file at all, while the handout still
    prints the rest of the slide. */
export function handoutRefusalText(blockers: Blocker[] | null | undefined): string {
	if (!Array.isArray(blockers) || blockers.length === 0) return '';
	if (blockers.length === 1) return `${blockers[0].label} is a live embed — it cannot print`;
	return `${blockers.length} live embeds on this slide — they cannot print`;
}

/** The one-line summary above the document, so the speaker knows before they print.

    Counted AND named, up to a point: past three, the names stop being a list a person reads
    and start being a wall, so it says how many. */
export function refusedSummary(titles: string[] | null | undefined): string {
	const named = Array.isArray(titles) ? titles.filter((t) => typeof t === 'string' && t) : [];
	if (named.length === 0) return '';
	const slides = named.length === 1 ? 'slide has' : 'slides have';
	const which = named.length <= 3 ? `: ${named.join(', ')}` : '';
	return `${named.length} ${slides} a live embed that will not print${which}`;
}
