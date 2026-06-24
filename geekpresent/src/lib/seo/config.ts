// SEO / social-metadata config.
//
// The ONE build-time knob is the site's absolute base URL, injected here from the
// GEEKPRESENT_SITE_URL env var via Vite `define` (see vite.config.ts) so the value
// is a plain string literal in BOTH the SSR/prerender output and the client bundle
// — no process.env at runtime, consistent with the other GEEKPRESENT_* vars.
//
// Why absolute at all, when every in-page asset here is deliberately RELATIVE?
// Because social scrapers and search engines cannot resolve relative URLs: og:url,
// og:image, twitter:image, <link rel="canonical"> and sitemap entries MUST be
// absolute. So those — and ONLY those — are built from SITE_URL. When SITE_URL is
// empty (the var was set to ""), every absolute-only tag is omitted rather than
// emitted broken/relative. In-page asset references stay relative regardless.

// Replaced at build time by Vite `define`; declared so TypeScript is happy.
declare const __GEEKPRESENT_SITE_URL__: string;

/** Absolute site base URL (no trailing slash), or '' when none is configured. */
export const SITE_URL: string = __GEEKPRESENT_SITE_URL__;

/** Site / brand name — used for og:site_name and as the title fallback. */
export const SITE_NAME = 'GeekPresent';

/** Default description for pages/decks that don't supply their own. Kept under
    ~160 chars so search engines don't truncate it in results. */
export const SITE_DESCRIPTION =
	'Build presentation slides and long-form texts in HTML, CSS and Svelte — each slide a route, each component yours, all in a portable static site.';

/** Path (under the site root) of the default social/OG image. */
export const OG_IMAGE_PATH = 'og-default.png';

/** Intrinsic size of the DEFAULT OG image (static/og-default.png), emitted as
    og:image:width/height. Only valid for the default card — a custom image has an
    unknown size, so those tags are skipped for it rather than asserting a wrong one. */
export const OG_IMAGE_WIDTH = 1200;
export const OG_IMAGE_HEIGHT = 630;

/** Alt text describing the default OG image (an a11y + scraper hint). */
export const OG_IMAGE_ALT =
	'GeekPresent — presentation slides and long-form texts in HTML, CSS and Svelte.';

/** Join the site base URL with a root-relative path into an absolute URL. Returns
    undefined when no base URL is configured, so the caller omits the tag. */
export function absoluteUrl(pathname: string): string | undefined {
	if (!SITE_URL) return undefined;
	const path = pathname.startsWith('/') ? pathname : `/${pathname}`;
	return SITE_URL + path;
}

/** Resolve an image prop to an ABSOLUTE URL for OG/Twitter tags: pass through an
    already-absolute URL, make a site-relative path absolute, or fall back to the
    default OG image. Returns undefined when nothing resolves absolutely (no base
    URL), so the image tags are omitted rather than emitted relative/broken. */
export function resolveImage(image?: string): string | undefined {
	if (image && /^https?:\/\//.test(image)) return image;
	return absoluteUrl(image ?? OG_IMAGE_PATH);
}
