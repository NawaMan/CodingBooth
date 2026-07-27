import { writable } from 'svelte/store';

// `?notes` on a SLIDE — print this slide with its speaker note beneath it, on one page.
// The same flag the handout takes, for the same reason, and it reaches <Note> the same way it
// would there: by telling the note that the reader asked for it, rather than leaving the note
// to infer it from a display mode that is about something else.
//
// A STORE, not a context, and that is forced rather than chosen: a deck's slides are the
// ADJUST's slot content, so they read the layout's context and not <SlideDeck>'s — which is
// exactly why `setPages()` has to be called from each deck's +layout.svelte and cannot live in
// the shell. SlideDeck reads the URL, so a context set there would never reach the <Note> that
// needs it. A store crosses that boundary because it does not care about the tree.
//
// Not persisted (unlike displayMode): it describes THIS page load, asked for in its URL, and a
// speaker who printed one slide with notes last week should not find notes on their deck today.
// Default false, so it is inert everywhere it was not asked for — including at prerender.
export const printNotes = writable(false);
