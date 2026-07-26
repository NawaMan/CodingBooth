/*
  The handout's build-time view of the site: every deck, its slide list, its canvas, and
  the actual slide COMPONENTS.

  This is the impure half of the handout — the part that reaches out to the tree — and it
  is deliberately the only part that does. The move is the one src/lib/seo/routes.ts already
  makes for the sitemap (glob every pages.ts, the second-to-last path segment is the deck
  name), taken one level further down: past the slide's metadata, to the slide itself.

  Why a glob and not a list: a hand-kept list of slides would be a second source of truth
  next to pages.ts, and the first slide anyone added without touching it would be silently
  missing from the printed deck — the exact failure a handout must not have. Globbing the
  real routes means the handout cannot drift from the deck. Same reasoning ViewSource gives
  for importing its own file with `?raw`.

  `eager: true` on the components is load-bearing. A lazy glob hands back import() thunks,
  which resolve after the module is evaluated — so the slides would mount on the client and
  the prerendered page would be empty, which is the very failure that keeps the deck's own
  slides out of the built HTML (SlideDeck gates its slot on `initialized`). The handout is a
  DOCUMENT: it must exist in the prerendered file, so it imports the components for real.

  The slide glob below excludes `/src/routes/_handout/**` — the handout's own route, which is
  shaped like a slide folder (`[deck].html/`) and would otherwise be handed to the handout to
  render, once per deck, as a module importing itself. Note what this exclusion is NOT: it is
  not a reserved slide NAME. The handout deliberately lives outside the decks so that no name
  inside one is spoken for; a deck is a folder of slides its author owns.
*/

import type { ComponentType } from 'svelte';
import type { Page } from '$lib/utils/navigate';
import { deckSurface, type DeckMeta, type DeckSurface } from './handoutCore';

/** Every deck's pages.ts. A deck MAY also export `deck` — its surface — and one that is not a
    1920x1080 dark-themed canvas must, or it will print as one (see handoutCore.DeckMeta). */
const pageModules = import.meta.glob<{ pages: Array<Page>; deck?: DeckMeta }>(
	'/src/routes/*/pages.ts',
	{ eager: true }
);

/** Every slide component in the site, keyed by module path — minus the handout's own route. */
const slideModules = import.meta.glob<{ default: ComponentType }>(
	['/src/routes/*/*.html/+page.svelte', '!/src/routes/_handout/**'],
	{ eager: true }
);

/** `/src/routes/<deck>/pages.ts` -> `<deck>` */
function deckOf(file: string): string {
	return file.split('/').slice(-2, -1)[0] ?? '';
}

/** Every deck that has a slide list, sorted so the prerendered set is stable across builds. */
export function deckNames(): string[] {
	return Object.keys(pageModules).map(deckOf).filter(Boolean).sort();
}

/** Whether this is a deck at all — the guard behind the handout route's 404. */
export function isDeck(name: string): boolean {
	return deckNames().includes(name);
}

/** A deck's slide list, straight from its pages.ts (empty for a name that is not a deck). */
export function deckPages(name: string): Array<Page> {
	for (const [file, mod] of Object.entries(pageModules)) {
		if (deckOf(file) === name) return Array.isArray(mod.pages) ? mod.pages : [];
	}
	return [];
}

/** A deck's surface — its own `deck` export, or GeekPresent's defaults. */
export function deckCanvas(name: string): DeckSurface {
	for (const [file, mod] of Object.entries(pageModules)) {
		if (deckOf(file) === name) return deckSurface(mod.deck);
	}
	return deckSurface(null);
}

/** One slide's component, or null if the deck's pages.ts names a slide that has no route.

    Null rather than a throw: a stale pages.ts entry should cost the reader one missing sheet
    (named, on the page) and not the entire printed document. */
export function slideComponent(deck: string, path: string): ComponentType | null {
	return slideModules[`/src/routes/${deck}/${path}/+page.svelte`]?.default ?? null;
}
