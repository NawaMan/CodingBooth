// Pure SVG-markup handling for SvgBlock. Browser-free, so it runs at prerender and
// unit-tests without a DOM (tests/svgCore.test.ts).
//
// SvgBlock puts an SVG file INLINE (an `import x from './x.svg?raw'` string), which
// is what lets the drawing take the slide's colours (`currentColor`, theme tokens)
// where an <img> could not. To fill its Block the root <svg> has to stop sizing
// itself: its own width/height go, a viewBox carries the drawing's proportions,
// and preserveAspectRatio says how those proportions meet the box.
//
// Total: markup with no <svg> root gives '' (an empty box), never a throw.

export type SvgFit = 'contain' | 'fill' | 'cover';

/** `fit` → the SVG's own `preserveAspectRatio`. Unknown → contain. */
export function preserveFor(fit: string | null | undefined): string {
	if (fit === 'fill') return 'none';
	if (fit === 'cover') return 'xMidYMid slice';
	return 'xMidYMid meet';
}

/** A plain length (`120`, `120px`, `12.5`) as a number; null for anything else
    (`50%`, `3em`, `auto`) — those cannot become a viewBox. */
function plainLength(v: string | null): number | null {
	if (v == null) return null;
	const m = /^\s*(\d+(?:\.\d+)?)\s*(px)?\s*$/.exec(v);
	if (!m) return null;
	const n = Number(m[1]);
	return Number.isFinite(n) && n > 0 ? n : null;
}

/** Index range of the root `<svg …>` opening tag, skipping an XML declaration,
    DOCTYPE and comments in front of it. Quote-aware, so a `>` inside an
    attribute value does not end the tag. */
function rootTag(markup: string): { start: number; end: number } | null {
	const start = markup.search(/<svg[\s>/]/i);
	if (start === -1) return null;
	let quote: string | null = null;
	for (let i = start + 4; i < markup.length; i++) {
		const c = markup[i];
		if (quote) {
			if (c === quote) quote = null;
		} else if (c === '"' || c === "'") quote = c;
		else if (c === '>') return { start, end: i + 1 };
	}
	return null;
}

/** One attribute's value from a tag's text, or null. */
function attr(tag: string, name: string): string | null {
	const m = new RegExp(`\\s${name}\\s*=\\s*("([^"]*)"|'([^']*)')`, 'i').exec(tag);
	return m ? (m[2] ?? m[3] ?? '') : null;
}

function dropAttr(tag: string, name: string): string {
	return tag.replace(new RegExp(`\\s${name}\\s*=\\s*("[^"]*"|'[^']*')`, 'gi'), '');
}

/**
 * Rewrite SVG markup to fill its container: the root <svg> loses its own
 * width/height, keeps its viewBox (or gets one derived from a plain-pixel
 * width/height), and takes the `fit` as preserveAspectRatio. Everything before
 * the root (XML declaration, DOCTYPE, comments) is dropped — it has no place
 * inside HTML. Returns '' when there is no <svg> root.
 */
export function inlineSvg(markup: string | null | undefined, fit: string = 'contain'): string {
	if (typeof markup !== 'string') return '';
	const root = rootTag(markup);
	if (!root) return '';

	let tag = markup.slice(root.start, root.end);
	const viewBox = attr(tag, 'viewBox');
	const w = plainLength(attr(tag, 'width'));
	const h = plainLength(attr(tag, 'height'));

	tag = dropAttr(tag, 'width');
	tag = dropAttr(tag, 'height');
	tag = dropAttr(tag, 'preserveAspectRatio');
	let extra = ` preserveAspectRatio="${preserveFor(fit)}"`;
	if (!viewBox && w != null && h != null) extra = ` viewBox="0 0 ${w} ${h}"` + extra;
	// Park the new attributes just before the tag's close (`>` or `/>`).
	tag = tag.replace(/\s*(\/?)>$/, (_, slash) => `${extra}${slash ? ' /' : ''}>`);

	return tag + markup.slice(root.end);
}
