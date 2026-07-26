// Multi-presentation support.
//
// `slides/` is just one presentation; a project can hold several, each in its
// own route folder with its own `pages.ts`. A presentation's +layout.svelte
// publishes its slide list with setPages(), and the templates (TitlePage /
// ContentPage) read it with getPages() — so navigation and the Table of
// Contents are scoped to whichever presentation the slide belongs to.
import { getContext, setContext } from 'svelte';
import { derived, type Readable } from 'svelte/store';
import { page } from '$app/stores';
import type { Page } from '$lib/utils/navigate';
import { currentSlidePath, progressOf, type Progress } from '$lib/utils/progressCore';

export type { Progress } from '$lib/utils/progressCore';

const PAGES_KEY = Symbol('geekpresent.pages');

/** Publish this presentation's slide list. Call from its +layout.svelte. */
export function setPages(pages: Array<Page>): void {
	setContext(PAGES_KEY, pages);
}

/** Read the current presentation's slide list (empty if none was published). */
export function getPages(): Array<Page> {
	return getContext<Array<Page>>(PAGES_KEY) ?? [];
}

/** Where THIS slide sits in its deck, as a reactive store — index, 1-based position,
    the visible-slide total, and a 0..1 fraction — for a page or component that wants to
    draw its own progress (a bar along the bottom, a "3 / 7" chip) without re-deriving it
    from the DOM. It combines the slide list getPages() already publishes with the live
    route, so it updates as the deck pages; the arithmetic (and its NaN-safety) lives in
    progressCore. Call during component init — it reads context — then subscribe:

      <script>
        import { getProgress } from '$lib/presentation';
        const progress = getProgress();
      </script>
      <p>Slide {$progress.position} of {$progress.total}</p>
*/
export function getProgress(): Readable<Progress> {
	const pages = getPages();
	return derived(page, ($page) => progressOf(pages, currentSlidePath($page.url.pathname)));
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

// Handout mode.
//
// A third context a slide can find itself in, after the deck window and the presenter
// console: the HANDOUT (routes/_handout/[deck].html), where every slide of a deck is stacked
// into one printable document. A slide does not change for it — the handout renders the
// very same +page.svelte — but a component may need to know, because the rules of paper
// are not the rules of a screen.
//
// <Note> is the one that does, and it is worth saying why it cannot simply read the
// display mode instead. A note is shown in SCALED display and in the presenter window,
// and hidden otherwise; but `displayMode` is PERSISTED, so a speaker who once zoomed
// into a slide would carry SCALED into the handout and get notes they never asked for.
// In the handout the question "print the notes?" has exactly one answer — the one the
// reader asked for — so the handout states it, and Note obeys it instead of guessing
// from a store that is about something else.
export interface Handout {
	/** Render <Note>s into the document. (Whether they are SHOWN is then CSS's business —
	    the handout's notes toggle flips a class, so the DOM is the same either way and a
	    prerendered handout hydrates without a mismatch.) */
	notes: boolean;
}

const HANDOUT_KEY = Symbol('geekpresent.handout');

/** Declare that these slides are being rendered into a printable handout. */
export function setHandout(handout: Handout): void {
	setContext(HANDOUT_KEY, handout);
}

/** The handout this slide is being printed into, or null in a normal deck. */
export function getHandout(): Handout | null {
	return getContext<Handout>(HANDOUT_KEY) ?? null;
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
