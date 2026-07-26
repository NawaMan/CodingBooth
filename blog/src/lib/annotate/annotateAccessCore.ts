/*
  ANNOTATE access — the pure decision layer behind the annotation stores (see
  stores/annotation.ts). The sibling of adjust/adjustAccessCore.ts, and deliberately
  ONE TIER SHORTER than it.

  ADJUST resolves dev > sticky ?adjust > what the SLIDE declares > off. Annotation
  drops the slide tier, because "which slide declared it" is the wrong axis for this
  tool: ADJUST is an AUTHORING aid, so the slide being authored has a real opinion
  about whether you should be dragging on it. Annotation is a SPEAKER tool — the
  speaker decides to circle a term while answering a question, and the slide they
  happen to be standing on has no opinion about that at all. So the flag is
  deck-wide and sticky:

    dev > the speaker's sticky ?annotate > a deck-wide prop on SlideDeck > off

  What it costs: no featured-pill treatment. The warm pulsing ADJUST button works
  because a SLIDE can say "press this"; a deck-wide tool can't, so the ANNOTATE
  button stays chrome-grey and the demo slide has to teach the flag rather than
  light it up.

  Side-effect free and total, like the core it sits beside: junk in, plain boolean out.
*/

import { readSticky, type Choice } from '$lib/adjust/adjustAccessCore';

// Re-exported so a caller reaching for the annotation precedence never has to
// import half of it from the ADJUST module. `readSticky` is shared verbatim rather
// than copied: "the two exact strings the store writes, everything else is
// no-choice-recorded" is the same rule here, for the same reason.
export { readSticky };
export type { Choice };

/** Interpret a slide URL's `?annotate` flag.

    `?annotate`, `?annotate=on`, `?annotate=1` enable; `?annotate=off`,
    `?annotate=false`, `?annotate=0` disable. An absent flag is `null`, NOT `false`
    — the nav links carry no query, so a URL that says nothing about annotation must
    not silently revoke what the speaker turned on three slides ago. */
export function readAnnotateParam(search: URLSearchParams | null | undefined): Choice {
	if (!search || !search.has('annotate')) return null;
	const v = (search.get('annotate') ?? '').trim().toLowerCase();
	return v !== 'off' && v !== 'false' && v !== '0';
}

/** Is the ANNOTATE control OFFERED here? (Offered, not active — the mode itself
    always starts off, so the audience never sees an armed pen they didn't ask for.)

    Highest authority first:

      1. `vite dev` — the authoring environment always offers it.
      2. The speaker's own explicit choice (`?annotate` / `?annotate=off`), sticky
         across slides. They asked; they outrank the deck. A corrupt sticky value is
         `null` (see readSticky) and falls THROUGH to the deck rather than vetoing it
         — one bad byte must not silently disarm a deck that ships the pen on purpose.
      3. What the DECK says — SlideDeck's `annotate` prop. This is what lets a talk
         ship with the pen available without the speaker typing a URL flag on stage.
      4. Off. That is the default a published deck gets. */
export function resolveCanAnnotate(dev: boolean, sticky: Choice, deckWide: boolean): boolean {
	if (dev === true) return true;
	if (sticky !== null) return sticky;
	return deckWide === true;
}
