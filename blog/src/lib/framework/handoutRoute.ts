import { error } from '@sveltejs/kit';
import { deckNames, isDeck } from '$lib/handout/handoutDecks';

export const prerender = true;
export const trailingSlash = 'never';

// `/_handout/slides.html` — outside the deck, and RESERVING NOTHING. A handout that lived at
// `/slides/handout.html` would have taken that name away from the deck's author forever, and a
// deck is a folder of slides they own; GeekPresent does not get to keep one of the names.
//
// What makes the inside tempting is that a slide's links are RELATIVE — `./appendix-detail.html`
// from an <AppendixLink>, `../` from the title slide's way home. The handout renders those very
// slides, so wherever it sits, their links resolve against ITS url; and from `/_handout/slides.html`
// every one of them would point into a directory that does not exist. A wall of 404s in the
// prerenderer's crawl, and a dead link for anyone who clicks one on screen.
//
// `<base href="…/slides/">` is the answer, and it is the mechanism built for exactly this: it says
// "resolve this document's relative URLs as if it lived there", which is precisely what a handout
// IS — a document *of* a deck. The page emits it (see +page.svelte); the browser honours it, and
// so does SvelteKit's prerender crawler (`kit/src/core/postbuild/crawl.js` reads a BASE tag and
// resolves every href after it against that), so the crawl walks into the real slides. Nothing
// else in the document is relative — assets are root-absolute — so the tag's blast radius is
// exactly the slide links it exists to fix.
//
// `.html` is not decoration: the built site is plain files on a dumb static host, so a URL is a
// FILE. A bare `/_handout/slides` would need the host to invent the extension — and where it does
// not, the file still loads but the CLIENT ROUTER cannot match the url it finds itself on, and
// hydrates the whole document into nothing. A blank page after a perfect prerender.
//
// The route also escapes the deck's +layout.svelte simply by not being inside it, which is what
// lets the handout render slides into the prerendered HTML at all: the deck shell gates its slot
// on `initialized`, and a document must not.

// A dynamic route has no fixed URL for the prerenderer to guess, so it is told: one handout per
// deck, from the same pages.ts glob the handout renders from. A new deck gets a printable handout
// with no second place to register it.
export function entries() {
	return deckNames().map((deck) => ({ deck }));
}

export function load({ params }: { params: { deck: string } }) {
	if (!isDeck(params.deck)) error(404, `No deck named "${params.deck}"`);
	return { deck: params.deck };
}
