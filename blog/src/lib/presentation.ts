// Multi-presentation support.
//
// `slides/` is just one presentation; a project can hold several, each in its
// own route folder with its own `pages.ts`. A presentation's +layout.svelte
// publishes its slide list with setPages(), and the templates (TitlePage /
// ContentPage) read it with getPages() — so navigation and the Table of
// Contents are scoped to whichever presentation the slide belongs to.
import { getContext, setContext } from 'svelte';
import type { Page } from '$lib/utils/navigate';

const PAGES_KEY = Symbol('geekpresent.pages');

/** Publish this presentation's slide list. Call from its +layout.svelte. */
export function setPages(pages: Array<Page>): void {
	setContext(PAGES_KEY, pages);
}

/** Read the current presentation's slide list (empty if none was published). */
export function getPages(): Array<Page> {
	return getContext<Array<Page>>(PAGES_KEY) ?? [];
}

// Artifact mode.
//
// There are two kinds of artifact, both built from the same components:
//   - 'presentation' — many discrete 1920x1080 slide pages (the default).
//   - 'text'         — one long page, fluid width (capped 1080px), grows down.
// A reused component reads this to decide how to render in each context (e.g.
// hide the slide nav bar, anchor to the document instead of the slide). An
// artifact's +layout.svelte publishes its mode with setMode(); anything that
// doesn't is treated as a presentation.
export type Mode = 'presentation' | 'text';

const MODE_KEY = Symbol('geekpresent.mode');

/** Publish this artifact's mode. Call from its +layout.svelte. */
export function setMode(mode: Mode): void {
	setContext(MODE_KEY, mode);
}

/** Read the current artifact's mode ('presentation' if none was published). */
export function getMode(): Mode {
	return getContext<Mode>(MODE_KEY) ?? 'presentation';
}

// View-transition navigation.
//
// By default a deck pages between slides with a full-page load (window.location)
// — route-per-slide, honest reload. A deck may instead opt into client-side
// navigation (SvelteKit goto) wrapped in the View Transitions API, so pressing
// next/prev animates one slide into the next WITHIN a single document (both
// slides are live, so there is no blank-snapshot problem the JS-mounted canvas
// would otherwise cause). The NavigationBar reads this to pick its strategy; a
// deck turns it on from its +layout.svelte with setViewTransitions(true).
const VIEW_TRANSITIONS_KEY = Symbol('geekpresent.viewTransitions');

/** Opt this deck into client-side, View-Transition-animated paging. */
export function setViewTransitions(on: boolean): void {
	setContext(VIEW_TRANSITIONS_KEY, on);
}

/** Whether this deck uses client-side View-Transition paging (default false). */
export function getViewTransitions(): boolean {
	return getContext<boolean>(VIEW_TRANSITIONS_KEY) ?? false;
}
