// The classification behind <Link>: deciding, from an href alone, whether a link
// keeps the reader inside this site or hands them off it — and what `target` and
// `rel` that implies.
//
// Kept pure and DOM-free (kbdCore / columnsCore / connectorCore discipline) so the
// component is left with nothing but markup, and so the interesting cases — a
// protocol-relative `//host`, a bare `mailto:`, an href someone typed by hand — are
// testable without a browser.
//
// Every function is total, and bad input yields the SAFE answer rather than a throw:
// an unrecognised href is INTERNAL (same tab, no rel), because the failure mode of
// guessing "internal" is a link that looks plain, while the failure mode of guessing
// "external" is a surprise new tab and a wrong promise about where the reader ends
// up. An href can come from a slide, a URL param, or an older deck; a slide must not
// collapse because someone wrote href={undefined}.

/** Where a link lands: still on this site, or off it. */
export type LinkKind = 'internal' | 'external';

/** What an author may write for `kind`. `auto` classifies from the href. */
export type KindProp = 'auto' | LinkKind;

/**
 * The three kinds of journey a link offers, as far as the READER is concerned.
 *
 * Deliberately a wider type than `LinkKind`: it follows where the reader ends up,
 * not what the URL says. An internal destination opened in a new window reads as
 * "leaving" (see `linkTone`), and `appendix` is contributed by AppendixLink rather
 * than by Link — the two components share this vocabulary so one glyph table
 * serves both.
 */
export type LinkTone = 'internal' | 'appendix' | 'external';

/** A scheme — `https:`, `mailto:`, `tel:` — at the very start of an href. */
const SCHEME = /^[a-zA-Z][a-zA-Z0-9+.\-]*:/;

/**
 * Is `url` on the same origin as `origin`?
 *
 * Both sides are parsed, so a malformed either-half answers `false` — an href we
 * cannot parse is not one we can vouch for as internal. `origin` is optional and
 * usually absent: a prerendered deck has no meaningful origin at build time (it is
 * `http://sveltekit-prerender`), so guessing one would misclassify a real absolute
 * link to the deployed site. With no origin, every absolute http(s) URL is external.
 */
function sameOrigin(url: string, origin?: string | null): boolean {
	if (!origin) return false;
	try {
		return new URL(url).origin === new URL(origin).origin;
	} catch {
		return false;
	}
}

/**
 * Where an href lands.
 *
 * The order of the tests is the whole subtlety. `//host/path` is protocol-relative
 * — the one absolute form with no scheme — so it must be caught BEFORE the plain
 * root-relative `/path`, which is internal. After those, anything carrying a scheme
 * leaves the site (`mailto:`, `tel:`, `ftp:` all hand the reader to another app),
 * except an http(s) URL that `origin` proves is ours. Everything left is relative
 * (`./x.html`, `../`, `x.html`, `#anchor`, `?q=1`) and therefore internal.
 */
export function classifyLink(href: unknown, origin?: string | null): LinkKind {
	if (typeof href !== 'string') return 'internal';
	const text = href.trim();
	if (!text) return 'internal';

	if (text.startsWith('//')) return sameOrigin(`https:${text}`, origin) ? 'internal' : 'external';
	if (/^[#?/]/.test(text)) return 'internal';

	const scheme = SCHEME.exec(text);
	if (!scheme) return 'internal';

	const s = scheme[0].toLowerCase();
	if (s === 'http:' || s === 'https:') return sameOrigin(text, origin) ? 'internal' : 'external';
	return 'external';
}

/**
 * Resolve the author's `kind` prop against the href.
 *
 * An explicit `internal` / `external` always wins — the author knows things the URL
 * does not (a redirect, a docs site that is really "ours"). Anything else, including
 * `auto`, a typo, or `undefined`, falls through to classification.
 */
export function resolveKind(kind: unknown, href: unknown, origin?: string | null): LinkKind {
	if (kind === 'internal' || kind === 'external') return kind;
	return classifyLink(href, origin);
}

/**
 * Does this link hand the reader to a new window/tab?
 *
 * `newTab` is a three-state override: `true` / `false` force it, and anything else
 * (`null`, `undefined`) means "follow the kind" — external links open away by
 * default, internal ones do not.
 */
export function opensNewWindow(kind: LinkKind, newTab?: boolean | null): boolean {
	return typeof newTab === 'boolean' ? newTab : kind === 'external';
}

/** `target` for the anchor, or `undefined` so the attribute is omitted entirely. */
export function linkTarget(kind: LinkKind, newTab?: boolean | null): string | undefined {
	return opensNewWindow(kind, newTab) ? '_blank' : undefined;
}

/**
 * `rel` for the anchor, or `undefined` when neither part applies.
 *
 * Anything opening a new window gets `noopener` — without it the opened page holds a
 * live `window.opener` handle on ours. An external destination also gets
 * `noreferrer`, so a site off ours is not told which slide sent the reader. An
 * external link forced to stay in the SAME tab still gets both: the referrer leak is
 * about the destination, not the window.
 */
export function linkRel(kind: LinkKind, newTab?: boolean | null): string | undefined {
	if (kind === 'external') return 'noopener noreferrer';
	return opensNewWindow(kind, newTab) ? 'noopener' : undefined;
}

/**
 * Which journey the link offers.
 *
 * An INTERNAL page the author deliberately opens in a new window reads as
 * "leaving" too: the promise is about where the reader ends up, not about the shape
 * of the URL. `appendix` never comes from here — AppendixLink names its own tone.
 */
export function linkTone(kind: LinkKind, newTab?: boolean | null): LinkTone {
	return kind === 'external' || opensNewWindow(kind, newTab) ? 'external' : 'internal';
}

/**
 * The trailing glyph that says which KIND of link this is.
 *
 * Every link in the deck wears one colour and one dashed underline, so the glyph is
 * the whole distinction — it is the meaning, not decoration. Hence:
 *
 *   internal  ''   an ordinary move inside the site: the unmarked, most common case,
 *                  left bare so prose is not littered with a glyph per link
 *   appendix  '↩'  a detour you will be brought back from
 *   external  '↗'  this leaves the site (the web's own convention)
 *
 * Total, like everything here: an unrecognised tone is unmarked rather than a throw.
 */
const GLYPHS: Record<LinkTone, string> = {
	internal: '',
	appendix: '↩',
	external: '↗'
};

export function linkGlyph(tone: unknown): string {
	return GLYPHS[tone as LinkTone] ?? '';
}
