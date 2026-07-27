/*
  captureSlide — the impure half of the screenshot (the pure half is captureCore.ts).

  Rasterise the live slide into a PNG at TRUE canvas resolution (1920x1080), not at whatever
  size the window happens to be showing it. Nothing is added to the page and nothing is asked
  of the user: we clone the canvas, fold everything it depends on into one self-contained SVG,
  and let the browser draw it.

  The one thing to understand before touching this file: an SVG loaded as a `data:` URL is a
  SEPARATE DOCUMENT. It cannot see this page's stylesheets, fonts, or images — anything not
  physically carried into it is absent, and the failure is SILENT. A missing font does not
  throw; it renders in Times New Roman and the layout shifts. So the work here is almost
  entirely "carry it across": stylesheets, @font-face payloads, <img> bytes, and the pixels of
  <canvas>/<video>, which `cloneNode` does not copy because it clones the element, not its
  bitmap.

  No new dependencies — this is fetch, cloneNode and a 2D context.
*/

import {
	CHROME_SELECTOR,
	LIVE_SELECTOR,
	findBlockers,
	svgDocument,
	type Blocker
} from './captureCore';

export interface CaptureResult {
	blob: Blob | null;
	/** Non-empty → we refused. The slide holds something no re-render can draw. */
	blockers: Blocker[];
}

/** Fetched bytes, keyed by URL. A deck's fonts are the same on every slide, and they are the
    bulk of the payload — re-fetching and re-base64-ing them on each capture would make the
    second screenshot as slow as the first for no reason. Lives for the page's lifetime. */
const assetCache = new Map<string, string>();

/** Fetch a URL and return it as a `data:` URI. Returns null rather than throwing: an asset we
    cannot inline is a degraded PNG, not a failed one, and one unreachable background image
    must not cost the speaker their screenshot. */
async function asDataUri(url: string): Promise<string | null> {
	const cached = assetCache.get(url);
	if (cached) return cached;
	try {
		const res = await fetch(url, { credentials: 'omit' });
		if (!res.ok) return null;
		const blob = await res.blob();
		const uri = await new Promise<string | null>((resolve) => {
			const fr = new FileReader();
			fr.onload = () => resolve(typeof fr.result === 'string' ? fr.result : null);
			fr.onerror = () => resolve(null);
			fr.readAsDataURL(blob);
		});
		if (uri) assetCache.set(url, uri);
		return uri;
	} catch {
		return null;
	}
}

/** Every stylesheet the page uses, flattened into one string.

    Three obstacles, and each one silently drops fonts if you miss it:

    1. A CROSS-ORIGIN sheet throws on `cssRules` — the CSSOM is walled off. The deck has real
       ones (Google Fonts, Monaco's CDN), so those are re-FETCHED by href instead. The bytes
       are readable even when the object model is not.
    2. An `@import`ed sheet is NOT in `document.styleSheets` at all. It hangs off its parent as
       a `CSSImportRule`, so a naive walk of the top level misses it entirely — and the deck
       imports Amatic SC, Cormorant Garamond and Fira Code exactly that way. We recurse into
       the rule's own `styleSheet` (and fall back to fetching its href when that is cross-origin
       and closed to us).
    3. The `@import` RULE itself must never be emitted: an SVG rendered as an image may not
       fetch external resources, so it would do nothing but break the XML (see xmlSafeCss).
       We take the imported sheet's contents and drop the rule that pointed at it. */
async function collectCss(): Promise<string> {
	const parts = await Promise.all(
		Array.from(document.styleSheets).map((s) => serializeSheet(s as CSSStyleSheet, 0))
	);
	return inlineCssUrls(parts.join('\n'));
}

async function fetchCss(href: string): Promise<string> {
	try {
		const res = await fetch(href, { credentials: 'omit' });
		return res.ok ? await res.text() : '';
	} catch {
		return ''; // unreachable — drop this sheet rather than the whole capture
	}
}

async function serializeSheet(sheet: CSSStyleSheet, depth: number): Promise<string> {
	// Imports can nest, and a malformed pair could cycle. Bound it rather than trust the web.
	if (depth > 4) return '';

	let rules: CSSRuleList | null = null;
	try {
		rules = sheet.cssRules;
	} catch {
		rules = null; // cross-origin: closed CSSOM
	}
	if (!rules) return sheet.href ? fetchCss(sheet.href) : '';

	const parts: string[] = [];
	for (const rule of Array.from(rules)) {
		// CSSRule.IMPORT_RULE === 3. Compared by number because the CSSImportRule constructor is
		// not reliably on the global in every environment we run in (jsdom included).
		if (rule.type === 3) {
			const imp = rule as CSSImportRule;
			if (imp.styleSheet) {
				parts.push(await serializeSheet(imp.styleSheet, depth + 1));
			} else if (imp.href) {
				try {
					parts.push(await fetchCss(new URL(imp.href, sheet.href ?? document.baseURI).href));
				} catch {
					/* skip */
				}
			}
			continue; // the rule itself never ships — see xmlSafeCss
		}
		parts.push(rule.cssText);
	}
	return parts.join('\n');
}

/** Rewrite every `url(...)` in the CSS to a `data:` URI — fonts above all.

    The deck's own faces are same-origin (`/fonts/*.woff`) and Google's are on `fonts.gstatic.com`
    (which serves CORS headers), so both are fetchable. This is the step that decides whether
    the PNG is typeset in the deck's fonts or in the browser's default serif. */
async function inlineCssUrls(css: string): Promise<string> {
	const urls = new Set<string>();
	const pattern = /url\(\s*['"]?([^'")]+)['"]?\s*\)/g;
	for (const m of css.matchAll(pattern)) {
		const raw = m[1].trim();
		if (raw && !raw.startsWith('data:')) urls.add(raw);
	}

	const resolved = new Map<string, string>();
	await Promise.all(
		Array.from(urls).map(async (raw) => {
			let abs = raw;
			try {
				abs = new URL(raw, document.baseURI).href;
			} catch {
				return;
			}
			const uri = await asDataUri(abs);
			if (uri) resolved.set(raw, uri);
		})
	);

	return css.replace(pattern, (whole, raw: string) => {
		const uri = resolved.get(raw.trim());
		return uri ? `url("${uri}")` : whole;
	});
}

/** Carry the pixels `cloneNode` left behind.

    A cloned `<canvas>` is blank and a cloned `<video>` is an empty box, because the clone
    copies the ELEMENT, not the bitmap it is currently showing. Both are readable from this
    document, though (unlike an iframe), so each is replaced with an `<img>` of its current
    frame — which means the Canvas component's drawing and the frame a Video is paused on both
    land in the PNG, rather than becoming holes in it.

    Originals and clones are walked in parallel: `querySelectorAll` returns document order, and
    a clone preserves order, so index i in one is index i in the other. */
function snapshotLive(original: Element, clone: Element): void {
	const live = Array.from(original.querySelectorAll(LIVE_SELECTOR));
	const copies = Array.from(clone.querySelectorAll(LIVE_SELECTOR));

	live.forEach((el, i) => {
		const target = copies[i];
		if (!target) return;
		let uri: string | null = null;
		try {
			if (el instanceof HTMLCanvasElement) {
				uri = el.toDataURL('image/png');
			} else if (el instanceof HTMLVideoElement && el.videoWidth > 0) {
				const c = document.createElement('canvas');
				c.width = el.videoWidth;
				c.height = el.videoHeight;
				c.getContext('2d')?.drawImage(el, 0, 0);
				uri = c.toDataURL('image/png');
			}
		} catch {
			// A canvas tainted by a cross-origin draw refuses toDataURL. Leave the element as it
			// is rather than losing the capture — a blank box beats no PNG.
			uri = null;
		}
		if (!uri) return;

		const img = document.createElement('img');
		img.src = uri;
		const rect = (el as HTMLElement).getBoundingClientRect();
		img.style.cssText = (target as HTMLElement).style.cssText;
		img.style.width = `${(el as HTMLElement).offsetWidth || rect.width}px`;
		img.style.height = `${(el as HTMLElement).offsetHeight || rect.height}px`;
		target.replaceWith(img);
	});
}

/** Inline every `<img>` in the clone. Two reasons, and the second is the one that bites: a
    remote `src` would not be fetched by the data:-URL document at all, AND drawing a
    cross-origin image onto the capture canvas would TAINT it, so `toBlob` would throw and the
    whole screenshot would fail on one decorative logo. Inlined bytes taint nothing. */
async function inlineImages(clone: Element): Promise<void> {
	const imgs = Array.from(clone.querySelectorAll('img'));
	await Promise.all(
		imgs.map(async (img) => {
			const src = img.getAttribute('src') ?? '';
			if (!src || src.startsWith('data:')) return;
			try {
				const uri = await asDataUri(new URL(src, document.baseURI).href);
				if (uri) img.setAttribute('src', uri);
				else img.remove(); // unreachable: drop it rather than draw a broken-image glyph
			} catch {
				img.remove();
			}
		})
	);
}

/** Rasterise `container` (the deck's `.container` — the canvas-sized frame) to a PNG.

    Refuses, without drawing anything, if the slide holds an `<iframe>`: that is a separate
    document whose pixels we may not read, so a PNG of it would be a lie with a hole in it. The
    caller shows the refusal the way SAVE does. */
export async function captureSlide(
	container: HTMLElement,
	width = 1920,
	height = 1080,
	scale = 1
): Promise<CaptureResult> {
	const blockers = findBlockers(container);
	if (blockers.length > 0) return { blob: null, blockers };

	const clone = container.cloneNode(true) as HTMLElement;

	// The live deck is SCALED to fit the window (a transform on .content, and a container sized
	// to match). The capture is not: it is the canvas at 1:1, which is the entire point — so
	// every trace of the display transform is undone here.
	clone.style.width = `${width}px`;
	clone.style.height = `${height}px`;
	clone.style.transform = 'none';
	clone.style.margin = '0';
	const inner = clone.querySelector('.content') as HTMLElement | null;
	if (inner) {
		inner.style.transform = 'none';
		inner.style.transformOrigin = 'top left';
	}

	// Chrome out, ink IN. The pen's bar and toggle wear `.no-print`; the ink surface does not,
	// so the strokes survive — which is the whole reason a speaker wants the screenshot.
	clone.querySelectorAll(CHROME_SELECTOR).forEach((el) => el.remove());

	snapshotLive(container, clone);
	await inlineImages(clone);

	const css = await collectCss();
	const svg = svgDocument(new XMLSerializer().serializeToString(clone), css, width, height);

	const blob = await rasterise(svg, width, height, scale);
	return { blob, blockers: [] };
}

/** SVG string → PNG blob, via an <img> and a 2D context. `encodeURIComponent` rather than
    `btoa`: the slide's text is arbitrary Unicode (the deck's own slides carry — and ⠿ and
    ✎), and `btoa` throws outright on anything above Latin-1. */
function rasterise(svg: string, width: number, height: number, scale: number): Promise<Blob | null> {
	return new Promise((resolve) => {
		const img = new Image();
		img.onload = () => {
			const canvas = document.createElement('canvas');
			const s = Math.max(1, Number(scale) || 1);
			canvas.width = Math.round(width * s);
			canvas.height = Math.round(height * s);
			const ctx = canvas.getContext('2d');
			if (!ctx) return resolve(null);
			ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
			try {
				canvas.toBlob((b) => resolve(b), 'image/png');
			} catch {
				resolve(null); // tainted canvas — should not happen now images are inlined
			}
		};
		img.onerror = () => resolve(null);
		img.src = `data:image/svg+xml;charset=utf-8,${encodeURIComponent(svg)}`;
	});
}

/** Hand the PNG to the browser's downloads. */
export function downloadBlob(blob: Blob, filename: string): void {
	const url = URL.createObjectURL(blob);
	const a = document.createElement('a');
	a.href = url;
	a.download = filename;
	a.click();
	// Revoke on the next tick: revoking synchronously can beat the click in some browsers and
	// the download lands empty.
	setTimeout(() => URL.revokeObjectURL(url), 0);
}
