// Enumerate the site's prerendered content routes — the source for sitemap.xml.
//
// Derived at BUILD time from each presentation's pages.ts (one entry per slide)
// plus the standalone Text routes (the home page and text.html). Lives in $lib so
// the sitemap endpoint and any future consumer share one source of truth, and so
// the list always tracks pages.ts without a second place to keep in sync.
//
// Decks may nest under a prefix (e.g. `references/shell`); path id mapping is
// shared with the handout via deckPathCore.
import type { Page } from '$lib/utils/navigate';
import { pathsFromPagesFile, slideSitePath } from '$lib/handout/deckPathCore';
import { SITE } from '$lib/config/site';

// Eagerly import every presentation's pages.ts (any depth under routes/).
const pageModules = import.meta.glob<{ pages: Array<Page> }>('/src/routes/**/pages.ts', {
	eager: true
});

// Standalone (non-deck) content routes: the landing page and the hand-authored
// Texts. They are the project's to list — `textRoutes` in geekpresent.config.ts — so a
// new Text reaches the sitemap without editing this file.
const TEXT_ROUTES = SITE.textRoutes;

/** All prerendered content routes as root-relative paths (e.g. '/slides/title.html'). */
export function siteRoutes(): string[] {
	const slideRoutes: string[] = [];
	for (const [file, mod] of Object.entries(pageModules)) {
		const paths = pathsFromPagesFile(file);
		if (!paths) continue;
		for (const p of mod.pages) {
			const site = slideSitePath(paths.urlPath, p.path);
			if (site) slideRoutes.push(site);
		}
	}
	return [...TEXT_ROUTES, ...slideRoutes];
}
