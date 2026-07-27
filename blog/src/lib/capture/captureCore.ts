/*
  Capture — the pure decision layer behind the slide screenshot (see capture/captureSlide.ts,
  which owns the impure half: fetching, rasterising, downloading).

  The whole point of capturing a GeekPresent slide rather than screenshotting the window is
  that the slide has a TRUE size. The deck is authored on a fixed 1920x1080 canvas and merely
  *displayed* at whatever scale the window allows, so a screen grab hands you 1147x645 of
  someone's laptop, while re-rendering the DOM hands you exactly the canvas, identical on
  every machine. That is what this does: clone the canvas, inline everything it depends on,
  and rasterise it through an SVG <foreignObject> at canvas resolution.

  Side-effect free and total, in the drawCore/annotateCore tradition. The DOM-reading helpers
  here take an Element and return data — they never mutate, so they stay directly testable.
*/

import { readSticky, type Choice } from '$lib/adjust/adjustAccessCore';

export { readSticky };
export type { Choice };

/** What a capture cannot draw. There is exactly one kind that is genuinely impossible rather
    than merely fiddly, and it is worth being precise about why: an `<iframe>` is a separate
    document. Its pixels live in another browsing context that we may not read (that is the
    same-origin policy doing its job, not a gap in the implementation), and cloning the
    `<iframe>` element clones an empty frame. So a slide built on `WebSite`, `WebPage` or a
    `YouTube` embed cannot be rasterised, and no amount of care changes that.

    `<canvas>` and `<video>` LOOK like the same problem and are not — their pixels are readable
    from this document, so captureSlide snapshots them into `<img>`s rather than refusing. */
export interface Blocker {
	kind: 'embed';
	label: string;
}

/** Elements that are CHROME, not slide content — stripped from the clone before rasterising.

    `.no-print` is the existing convention for exactly this distinction (the deck already uses
    it to keep the nav bar out of a printout), so capture reuses it rather than inventing a
    second list that would drift. That includes the pen's own bar, toggle and stale-ink prompt
    — but NOT `.annot-surface`, which is the ink itself. The annotations are the whole reason a
    speaker wants a screenshot: they circled the thing, and the circle has to be in the PNG.

    `.gp-chrome` is the fadeChrome marker, which catches the same controls from the other side. */
export const CHROME_SELECTOR = '.no-print, .gp-chrome';

/** Live elements whose pixels the clone will not carry: a `<canvas>` clones as a blank canvas
    and a `<video>` as a black box, because `cloneNode` copies the element, not its bitmap.
    captureSlide replaces each with an `<img>` of the frame it is showing right now. */
export const LIVE_SELECTOR = 'canvas, video';

/** Find what this slide cannot honestly be drawn from.

    Named rather than counted: "1 EMBED" tells the speaker nothing, while "the YouTube embed"
    tells them which box will be missing. Falls back to the tag name only when the element
    offers no title, no src and no name to go on. */
export function findBlockers(root: Element | null | undefined): Blocker[] {
	if (!root || typeof root.querySelectorAll !== 'function') return [];
	const out: Blocker[] = [];
	for (const frame of Array.from(root.querySelectorAll('iframe'))) {
		out.push({ kind: 'embed', label: frameLabel(frame) });
	}
	return out;
}

function frameLabel(frame: Element): string {
	const title = frame.getAttribute('title')?.trim();
	if (title) return title;
	const src = frame.getAttribute('src')?.trim();
	if (src) {
		try {
			return new URL(src, 'https://x.invalid').hostname || src;
		} catch {
			return src;
		}
	}
	return 'an embed';
}

/** What the button says when it refuses.

    Modelled on SAVE, which is shown in both worlds and answers NOT ALLOWED when pressed rather
    than sitting greyed out from the start — a disabled button reads as "this feature is broken
    or missing", whereas a button that refuses on click teaches you WHY capture cannot work
    here. Same reasoning, same shape. */
export function refusalText(blockers: Blocker[]): string {
	if (!Array.isArray(blockers) || blockers.length === 0) return '';
	if (blockers.length === 1) return `Can't capture ${blockers[0].label} — it's a live embed`;
	return `Can't capture ${blockers.length} live embeds on this slide`;
}

/** The downloaded file's name: the slide's own path, so a folder of captures reads like the
    deck. `/slides/intro.html` → `intro.png`. Junk in yields `slide.png` rather than `.png` or
    an empty name the browser would refuse to save. */
export function captureFileName(pathname: string | null | undefined, ext = 'png'): string {
	const raw = typeof pathname === 'string' ? pathname : '';
	const last = raw.replace(/\/+$/, '').split('/').pop() ?? '';
	const stem = last
		.replace(/\.html?$/i, '')
		.replace(/[^a-zA-Z0-9._-]/g, '-')
		// A stem of "." or ".." survives the character filter and yields "...png" — a name the
		// browser will not save, and one that reads as a path traversal besides.
		.replace(/^\.+$/, '');
	return `${stem || 'slide'}.${ext}`;
}

/** Make a stylesheet safe to embed in the SVG, which is XML and not HTML.

    This is the bug that made the first version refuse to draw ANY slide, and it is worth
    stating plainly because nothing about it is obvious. The deck's compiled CSS contains

        @import url("https://fonts.googleapis.com/css2?family=Amatic+SC:wght@400;700&display=swap");

    In HTML a bare `&` is tolerated. In XML it is the start of an entity reference, so the
    document is MALFORMED — and a malformed SVG is not partially drawn, it is rejected whole.
    The browser then fires `onerror` with no explanation, which reads as "the browser refused
    to draw this slide" and gives you nothing to go on. One ampersand, in a font import, kills
    the entire screenshot.

    So: escape `&` and `<` (the XML parser decodes them back before the CSS parser ever sees
    them, so the CSS is unchanged), and DROP `@import` outright. The drop is not belt-and-braces
    — an SVG rendered as an image may not fetch external resources at all, so an `@import` in
    there is dead weight at best. The imported sheet's *content* is pulled in separately and
    inlined (see captureSlide.collectCss), which is the only way those fonts can arrive. */
export function xmlSafeCss(css: string): string {
	if (typeof css !== 'string') return '';
	return css
		.replace(/@import\s+[^;]+;/g, '')
		.replace(/&/g, '&amp;')
		.replace(/</g, '&lt;');
}

/** The SVG that does the rasterising.

    A `<foreignObject>` sized to the canvas, holding the cloned slide as XHTML, with every
    stylesheet the deck uses folded into one `<style>`. That inlining is not an optimisation —
    an SVG loaded as a `data:` URL is a DOCUMENT OF ITS OWN, with no access to the page's
    stylesheets, its fonts or its images. Anything not carried across simply is not there, and
    the failure is silent: the text renders in Times New Roman and the layout quietly shifts.
    So everything comes with it, or the PNG is a lie. */
export function svgDocument(html: string, css: string, width: number, height: number): string {
	const w = Math.max(1, Math.round(Number(width) || 1920));
	const h = Math.max(1, Math.round(Number(height) || 1080));
	return (
		`<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}">` +
		`<foreignObject x="0" y="0" width="${w}" height="${h}">` +
		`<div xmlns="http://www.w3.org/1999/xhtml" style="width:${w}px;height:${h}px;">` +
		// xmlSafeCss, not `css` — and it is applied HERE rather than at the call site so it is
		// impossible to forget. One unescaped `&` in a font @import rejects the whole document.
		`<style>${xmlSafeCss(css)}</style>` +
		html +
		`</div>` +
		`</foreignObject>` +
		`</svg>`
	);
}

/** Interpret a slide URL's `?capture` flag. Absent is `null` — "nothing was said" — not
    `false`, for the reason every other sticky flag here does it: the nav links carry no query,
    so paging must not revoke what the speaker turned on three slides ago. */
export function readCaptureParam(search: URLSearchParams | null | undefined): Choice {
	if (!search || !search.has('capture')) return null;
	const v = (search.get('capture') ?? '').trim().toLowerCase();
	return v !== 'off' && v !== 'false' && v !== '0';
}

/** Is CAPTURE offered here? The annotation precedence, for the same reason: taking a
    screenshot is something the SPEAKER (or author) decides to do, and the slide they happen to
    be standing on has no opinion about it. dev > sticky `?capture` > the deck's prop > off. */
export function resolveCanCapture(dev: boolean, sticky: Choice, deckWide: boolean): boolean {
	if (dev === true) return true;
	if (sticky !== null) return sticky;
	return deckWide === true;
}
