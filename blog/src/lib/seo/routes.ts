// Enumerate the site's prerendered content routes — the source for sitemap.xml.
//
// Derived at BUILD time from each presentation's pages.ts (one entry per slide)
// plus the standalone Text routes (the home page and text.html). Lives in $lib so
// the sitemap endpoint and any future consumer share one source of truth, and so
// the list always tracks pages.ts without a second place to keep in sync.
import type { Page } from '$lib/utils/navigate';

// Eagerly import every presentation's pages.ts. The glob key is the module path,
// e.g. '/src/routes/slides/pages.ts' — the second-to-last segment is the deck name.
const pageModules = import.meta.glob<{ pages: Array<Page> }>('/src/routes/*/pages.ts', {
	eager: true
});

// Standalone (non-deck) content routes: the landing page and the hand-authored
// Texts (each blog post is a Text article). trailingSlash is "never", so '/' is
// the only one that keeps a trailing slash. Add a new standalone Text route here
// so it lands in the sitemap.
const TEXT_ROUTES = [
	'/',
	'/2026-06-28.html',
	'/2026-06-18.html',
	'/2026-05-29.html'
];

/** All prerendered content routes as root-relative paths (e.g. '/slides/title.html'). */
export function siteRoutes(): string[] {
	const slideRoutes: string[] = [];
	for (const [file, mod] of Object.entries(pageModules)) {
		const deck = file.split('/').slice(-2, -1)[0]; // .../<deck>/pages.ts -> <deck>
		for (const p of mod.pages) slideRoutes.push(`/${deck}/${p.path}`);
	}
	return [...TEXT_ROUTES, ...slideRoutes];
}
