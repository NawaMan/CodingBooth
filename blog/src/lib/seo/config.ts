// SEO / social-metadata config.
//
// The site-specific values — base URL, brand name, default description, card alt text —
// come from the project's settings (geekpresent.config.ts, resolved by the Vite plugin and
// injected as a string literal; see $lib/config/site.ts). GEEKPRESENT_SITE_URL, when set,
// still overrides the base URL per build. Nothing here is edited per project.
//
// Why absolute at all, when every in-page asset here is deliberately RELATIVE?
// Because social scrapers and search engines cannot resolve relative URLs: og:url,
// og:image, twitter:image, <link rel="canonical"> and sitemap entries MUST be
// absolute. So those — and ONLY those — are built from SITE_URL. When SITE_URL is
// empty (the var was set to ""), every absolute-only tag is omitted rather than
// emitted broken/relative. In-page asset references stay relative regardless.

import { SITE } from '$lib/config/site';

/** Absolute site base URL (no trailing slash), or '' when none is configured. */
export const SITE_URL: string = SITE.siteUrl;

/** Site / brand name — used for og:site_name and as the title fallback. */
export const SITE_NAME: string = SITE.siteName;

/** Default description for pages/decks that don't supply their own. Kept under
    ~160 chars so search engines don't truncate it in results. */
export const SITE_DESCRIPTION: string = SITE.siteDescription;

/** Path (under the site root) of the default social/OG image. */
export const OG_IMAGE_PATH = 'og-default.png';

/** Intrinsic size of the DEFAULT OG image (static/og-default.png), emitted as
    og:image:width/height. Only valid for the default card — a custom image has an
    unknown size, so those tags are skipped for it rather than asserting a wrong one. */
export const OG_IMAGE_WIDTH = 1200;
export const OG_IMAGE_HEIGHT = 630;

/** Alt text describing the default OG image (an a11y + scraper hint). */
export const OG_IMAGE_ALT: string = SITE.ogImageAlt;

/** Join the site base URL with a root-relative path into an absolute URL. Returns
    undefined when no base URL is configured, so the caller omits the tag. */
export function absoluteUrl(pathname: string): string | undefined {
	if (!SITE_URL) return undefined;
	const path = pathname.startsWith('/') ? pathname : `/${pathname}`;
	return SITE_URL + path;
}

/** A page's pathname with the site's base path taken off, so it can be joined to SITE_URL
    (which already ends in that path). `/GeekPresent/slides/a.html` under `/GeekPresent` is
    `/slides/a.html`; a pathname outside the base is returned as it is. */
export function stripBase(pathname: string, base: string): string {
	if (!base) return pathname;
	if (pathname === base) return '/';
	return pathname.startsWith(base + '/') ? pathname.slice(base.length) : pathname;
}

/** Resolve an image prop to an ABSOLUTE URL for OG/Twitter tags: pass through an
    already-absolute URL, make a site-relative path absolute, or fall back to the
    default OG image. Returns undefined when nothing resolves absolutely (no base
    URL), so the image tags are omitted rather than emitted relative/broken. */
export function resolveImage(image?: string): string | undefined {
	if (image && /^https?:\/\//.test(image)) return image;
	return absoluteUrl(image ?? OG_IMAGE_PATH);
}
