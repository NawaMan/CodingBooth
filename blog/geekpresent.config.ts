// The blog's settings — read by the Vite plugin (vite.config.ts). Every field is
// optional; see src/lib/config/siteConfigCore.ts for what each one does.
// These used to be local edits to src/lib (seo/config.ts, seo/routes.ts,
// utils/navigate.ts); upstream GeekPresent now reads them from here, so a sync
// can mirror src/lib untouched.
import type { GeekPresentConfig } from './src/lib/config/siteConfigCore';

const site: GeekPresentConfig = {
	// Served at codingbooth.io/blog/ (CodingBooth's site/blog). An env
	// GEEKPRESENT_SITE_URL still overrides it per build ('' omits absolute tags).
	siteUrl: 'https://codingbooth.io/blog',
	siteName: 'CodingBooth Blog',
	siteTitle: 'The CodingBooth Blog',
	siteDescription:
		'The CodingBooth blog — feature deep-dives, hands-on examples, and project news for CodingBooth: reproducible, isolated development environments in a Docker container that runs as you.',
	ogImageAlt: 'The CodingBooth Blog — deep dives into reproducible, isolated development environments.',
	copyright: { name: 'GeekPresent', url: 'https://nawaman.net/projects#geekpresent' },
	// Each blog post is a Text article. trailingSlash is "never", so '/' is the
	// only one that keeps a trailing slash. Add a published post here so it lands
	// in the sitemap.
	textRoutes: ['/', '/2026-06-28.html', '/2026-06-18.html', '/2026-05-29.html']
};

export default site;
