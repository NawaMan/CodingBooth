// The build-time search index: every slide's source, stripped to prose, keyed by
// deck and path. This is the ONE impure module in the search feature — it owns the
// `?raw` glob; all the logic lives in the pure searchCore.ts beside it.
//
// Eager + `?raw` means each slide's real source is inlined as a string at build
// time, so the index survives prerender (a static site has no server to ask) and
// cannot drift from what is on screen — the same reason ViewSource imports `?raw`.
// The glob matches `<deck>/<slide>/+page.svelte` (two directories under routes),
// so a deck's own `+page.svelte` redirect (one directory) is not swept in.
import { buildDeckIndex, type SearchDoc } from './searchCore';
import type { Page } from './navigate';

const slideSources = import.meta.glob<string>('/src/routes/*/*/+page.svelte', {
	query: '?raw',
	import: 'default',
	eager: true
});

const INDEX = buildDeckIndex(slideSources);

/** The searchable body text for one slide, or '' if the deck/path is unknown. */
export function slideText(deck: string, path: string): string {
	return INDEX[deck]?.[path] ?? '';
}

/** Pair a deck's `pages` with their indexed body text, ready for searchDocs.
    Titles come from pages.ts (what the TOC shows); text comes from the index;
    `number` is the 1-based position in the array as PASSED — a caller filters
    first (e.g. `visiblePages`) if hidden appendices should not get a number, or
    passes the raw list to number by the same reckoning it renders. */
export function deckSearchDocs(deck: string, pages: Array<Page>): SearchDoc[] {
	return (pages ?? []).map((p, i) => ({
		path: p.path,
		title: p.title,
		text: slideText(deck, p.path),
		number: i + 1
	}));
}
