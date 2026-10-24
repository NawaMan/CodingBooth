/*
  The handout's build-time view of the site: every deck, its slide list, its canvas, and
  the actual slide COMPONENTS.

  This is the impure half of the handout — the part that reaches out to the tree — and it
  is deliberately the only part that does. The move is the one src/lib/seo/routes.ts already
  makes for the sitemap (glob every pages.ts), taken one level further down: past the slide's
  metadata, to the slide itself.

  Decks may nest (e.g. `references/shell`). Discovery uses `**` globs; id / fs / URL path
  mapping lives in deckPathCore.ts so sitemap and handout stay in step.

  `eager: true` on the components is load-bearing. A lazy glob hands back import() thunks,
  which resolve after the module is evaluated — so the slides would mount on the client and
  the prerendered page would be empty. The handout is a DOCUMENT: it must exist in the
  prerendered file, so it imports the components for real.

  The slide glob excludes `/src/routes/_handout/**` and other framework routes shaped like
  slides. Note what this exclusion is NOT: it is not a reserved slide NAME inside a deck.
*/

import type { ComponentType } from 'svelte';
import type { Page } from '$lib/utils/navigate';
import { deckSurface, type DeckMeta, type DeckSurface } from './handoutCore';
import {
	pathsFromPagesFile,
	slideModulePath,
	type DeckPaths
} from './deckPathCore';

/** Every deck's pages.ts. A deck MAY also export `deck` — its surface — and one that is not a
    1920x1080 dark-themed canvas must, or it will print as one (see handoutCore.DeckMeta). */
const pageModules = import.meta.glob<{ pages: Array<Page>; deck?: DeckMeta }>(
	'/src/routes/**/pages.ts',
	{ eager: true }
);

/** Every slide component in the site, keyed by module path — minus framework routes. */
const slideModules = import.meta.glob<{ default: ComponentType }>(
	[
		'/src/routes/**/*.html/+page.svelte',
		'!/src/routes/_handout/**',
		'!/src/routes/_source-edit/**'
	],
	{ eager: true }
);

type DeckEntry = DeckPaths & {
	pages: Array<Page>;
	deck?: DeckMeta;
};

function buildIndex(): Map<string, DeckEntry> {
	const map = new Map<string, DeckEntry>();
	for (const [file, mod] of Object.entries(pageModules)) {
		const paths = pathsFromPagesFile(file);
		if (!paths) continue;
		map.set(paths.id, {
			...paths,
			pages: Array.isArray(mod.pages) ? mod.pages : [],
			deck: mod.deck
		});
	}
	return map;
}

const index = buildIndex();

/** Every deck id, sorted so the prerendered set is stable across builds. */
export function deckNames(): string[] {
	return [...index.keys()].sort();
}

/** Whether this is a deck at all — the guard behind the handout route's 404. */
export function isDeck(name: string): boolean {
	return index.has(name);
}

/** Public URL path for a deck (no leading slash), for `<base href>` and links. */
export function deckUrlPath(name: string): string {
	return index.get(name)?.urlPath ?? name;
}

/** Filesystem path under `src/routes/` (may include route groups). */
export function deckFsPath(name: string): string {
	return index.get(name)?.fsPath ?? name;
}

/** A deck's slide list, straight from its pages.ts (empty for a name that is not a deck). */
export function deckPages(name: string): Array<Page> {
	return index.get(name)?.pages ?? [];
}

/** A deck's surface — its own `deck` export, or GeekPresent's defaults. */
export function deckCanvas(name: string): DeckSurface {
	return deckSurface(index.get(name)?.deck ?? null);
}

/** One slide's component, or null if the deck's pages.ts names a slide that has no route.

    Null rather than a throw: a stale pages.ts entry should cost the reader one missing sheet
    (named, on the page) and not the entire printed document. */
export function slideComponent(deck: string, path: string): ComponentType | null {
	const fs = deckFsPath(deck);
	const key = slideModulePath(fs, path);
	return slideModules[key]?.default ?? null;
}
