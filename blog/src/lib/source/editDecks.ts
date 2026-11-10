// Every deck's linear order, for the EDIT window's FIRST / PREV / NEXT / LAST.
//
// The EDIT window is its own route (`/_source-edit`), so no deck layout has run
// setPages() for it. It reads every pages.ts itself, the way the sitemap
// (seo/routes.ts) and the handout (handout/handoutDecks.ts) do.
import type { Page } from '$lib/utils/navigate';
import { visiblePages } from '$lib/utils/navigate';
import { pathsFromPagesFile } from '$lib/handout/deckPathCore';
import type { EditDeck } from './deckNavCore';

const pageModules = import.meta.glob<{ pages: Array<Page> }>('/src/routes/**/pages.ts', {
	eager: true
});

/** Every deck, its slides in →/Space order (appendices left out). */
export const EDIT_DECKS: EditDeck[] = Object.entries(pageModules).flatMap(([file, mod]) => {
	const paths = pathsFromPagesFile(file);
	if (!paths || !Array.isArray(mod.pages)) return [];
	const slides = visiblePages(mod.pages).map((p) => ({ path: p.path, title: p.title }));
	return slides.length ? [{ fsPath: paths.fsPath, urlPath: paths.urlPath, slides }] : [];
});
