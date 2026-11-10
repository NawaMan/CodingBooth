// The project's settings — the things a site that USES GeekPresent changes, so that it
// never has to edit a framework file to change them.
//
// Every edit the adopting projects had made to a framework file was one of these: the
// brand name in the SEO tags and the copyright, the default description, which Text
// routes reach the sitemap. Once they live here, a project's copy of the framework can be
// a package it does not touch.
//
// A project writes them in `geekpresent.config.ts` and hands them to the Vite plugin
// (`geekpresent(site)`, see ../vite.ts). The plugin resolves them ONCE, at config time, and
// injects the result as a string literal (Vite `define`, `__GEEKPRESENT_CONFIG__`) — the
// same route GEEKPRESENT_SITE_URL always took, so the prerendered HTML and the client
// bundle read identical values with no runtime lookup. Read them through ./site.ts.
//
// Pure: no Vite, no Node, no `define` — the plugin, the tests and ./site.ts all share it.

/** What a project may set. Every field is optional; what is left out takes DEFAULTS. */
export interface GeekPresentConfig {
	/** Absolute base URL of the deployed site, no trailing slash — used ONLY for the
	    metadata that must be absolute (og:url, og:image, canonical, sitemap). '' omits
	    those tags. The GEEKPRESENT_SITE_URL env var, when set, wins over this. */
	siteUrl?: string;
	/** Brand name: og:site_name. */
	siteName?: string;
	/** The browser-tab title of a page or deck that sets none (and a Text's default title).
	    Left out, it is siteName. */
	siteTitle?: string;
	/** Default description for a page or deck that has none (keep it under ~160 chars). */
	siteDescription?: string;
	/** Alt text of the default social card (static/og-default.png). */
	ogImageAlt?: string;
	/** The corner notice on every slide: `© name year`, linking to `url` on hover. */
	copyright?: { name?: string; url?: string };
	/** Standalone (non-deck) routes for the sitemap. Decks are found by their pages.ts;
	    a Text is not, so each one is listed here. */
	textRoutes?: string[];
	/** The module specifier that reaches the framework from a SLIDE's source: '$lib' in
	    this repo, '@geekpresent/core' in a project that installs the package. Used when
	    the framework writes an import INTO a slide (ADJUST/ANNOTATE adding a <Draw>).
	    Left out, the plugin picks it from where it was loaded. */
	libImport?: string;
}

/** The settings with every field filled in. */
export interface SiteConfig {
	siteUrl: string;
	siteName: string;
	siteTitle: string;
	siteDescription: string;
	ogImageAlt: string;
	copyright: { name: string; url: string };
	textRoutes: string[];
	libImport: string;
}

/** What a project gets for each setting it leaves out. Deliberately plain: the
    GeekPresent showcase sets its own values in geekpresent.config.ts like anyone else. */
export const DEFAULTS: SiteConfig = {
	siteUrl: '',
	siteName: 'GeekPresent',
	siteTitle: 'GeekPresent',
	siteDescription: 'Presentation slides and long-form texts, built with GeekPresent.',
	ogImageAlt: 'Presentation slides and long-form texts, built with GeekPresent.',
	copyright: { name: 'GeekPresent', url: 'https://github.com/NawaMan/GeekPresent' },
	textRoutes: ['/'],
	libImport: '$lib'
};

/** Trim a URL and drop trailing slashes, so joins with '/path' stay clean. */
export function normalizeSiteUrl(url: string): string {
	return url.trim().replace(/\/+$/, '');
}

/** Fill in a project's settings. `envSiteUrl` is GEEKPRESENT_SITE_URL as read from the
    environment: `undefined` when unset (the config decides), any string — including ''
    — when set (it wins, so a deploy can retarget the URL without editing a file).
    Non-string junk in a field falls back to the default rather than leaking through. */
export function resolveConfig(
	user: GeekPresentConfig = {},
	envSiteUrl?: string,
	fallbackLibImport: string = DEFAULTS.libImport
): SiteConfig {
	const str = (v: unknown, d: string) => (typeof v === 'string' ? v : d);
	const siteUrl = normalizeSiteUrl(
		envSiteUrl !== undefined ? envSiteUrl : str(user.siteUrl, DEFAULTS.siteUrl)
	);
	const routes = Array.isArray(user.textRoutes)
		? user.textRoutes.filter((r): r is string => typeof r === 'string')
		: DEFAULTS.textRoutes;
	const siteName = str(user.siteName, DEFAULTS.siteName);
	return {
		siteUrl,
		siteName,
		siteTitle: str(user.siteTitle, siteName),
		siteDescription: str(user.siteDescription, DEFAULTS.siteDescription),
		ogImageAlt: str(user.ogImageAlt, DEFAULTS.ogImageAlt),
		copyright: {
			name: str(user.copyright?.name, DEFAULTS.copyright.name),
			url: str(user.copyright?.url, DEFAULTS.copyright.url)
		},
		textRoutes: [...routes],
		libImport: str(user.libImport, fallbackLibImport).replace(/\/+$/, '')
	};
}

/** The specifier a slide imports the Draw family from. */
export function drawModule(config: Pick<SiteConfig, 'libImport'>): string {
	return `${config.libImport}/draw`;
}
