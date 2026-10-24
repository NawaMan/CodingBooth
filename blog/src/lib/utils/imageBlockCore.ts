// The markup behind <ImageBlock live>: turning an SVG file's text into an inline
// <svg> that fills its panel.
//
// Why inline at all: a browser renders an SVG loaded through <img> as a static
// picture, so an animated GIF embedded in it (Excalidraw puts images in as
// data: URIs) is stuck on its first frame. Inline, the SVG is part of the page
// and the GIF plays.
//
// Why rewrite the root: an exported SVG pins its root to its drawing size
// (`width="82.87"`), so inline it would sit at that size in a corner of the
// panel. The root gets `100%` instead, and the `fit` the author chose becomes
// its `preserveAspectRatio`.
//
// Kept pure and DOM-free so the bad inputs are testable without a browser. Total:
// anything that is not an SVG yields '', never a throw — the component then keeps
// showing its <img>.

/** How the picture maps onto the panel — the same three as ImageBlock's `fit`. */
export type Fit = 'fill' | 'cover' | 'contain';

const ASPECT: Record<Fit, string> = {
	fill: 'none',
	contain: 'xMidYMid meet',
	cover: 'xMidYMid slice'
};

// The root's own sizing; anything else on it (viewBox, xmlns, …) is kept.
const SIZING = /\s(?:width|height|preserveAspectRatio)\s*=\s*(?:"[^"]*"|'[^']*')/g;

/**
 * The SVG file's text, rewritten to fill its panel, or '' when `text` holds no
 * <svg> root. Whatever comes before the root (an XML prolog, a doctype, a
 * comment) is dropped: none of it is valid inside an HTML page.
 */
export function inlineSvg(text: string, fit: Fit = 'fill'): string {
	if (typeof text !== 'string') return '';
	const start = text.search(/<svg[\s>]/i);
	if (start < 0) return '';
	const open = text.indexOf('>', start);
	if (open < 0) return '';

	const tag = text.slice(start, open).replace(/\/$/, '').replace(SIZING, '');
	const aspect = ASPECT[fit] ?? ASPECT.fill;
	const selfClosed = text[open - 1] === '/';
	const root = `${tag} width="100%" height="100%" preserveAspectRatio="${aspect}" style="display:block"`;
	return selfClosed ? `${root}/>` : `${root}>${text.slice(open + 1)}`;
}

/**
 * ImageBlock's `live`: off, on (inline as soon as the slide is in the browser), or
 * 'after-transition' (inline once the view transition that brought the slide in has
 * finished — so an animated GIF starts on the landed slide, not mid-morph).
 */
export type Live = boolean | 'after-transition';

/** The `live` attribute as the copied tag spells it: '' when off. */
export function liveAttr(live: Live): string {
	if (live === 'after-transition') return ' live="after-transition"';
	return live ? ' live' : '';
}
