/*
  ADJUST access — the pure decision layer behind the authoring stores (see
  stores/adjustMode.ts). Three inputs decide whether a slide offers the ADJUST
  control, and they disagree often enough (a dev server, a sticky `?adjust` a
  speaker typed three slides ago, a deck that ships the control on purpose) that
  the precedence deserves to be stated once, in one readable place, rather than
  inferred from a chain of `||`s inside a store initializer.

  Side-effect free and total, in the drawCore/connectorCore tradition: every
  input may be junk — a localStorage key another tab corrupted, a URL with no
  query at all — and the answer is still a plain boolean.
*/

/** A recorded explicit choice, or `null` for "nothing was said". The distinction
    matters: "nothing was said" must fall through to the next authority, whereas
    a recorded `false` is a decision that outranks it. */
export type Choice = boolean | null;

/** Interpret the sticky `canAdjust` flag held in localStorage.

    Only the two exact strings the store writes count as a choice. Anything else
    — absent, empty, garbage from an older version or a half-finished write — is
    `null`, i.e. "no choice recorded". Mapping garbage to `false` instead would
    let one corrupt byte silently veto a deck's own demo default, and the author
    would have no way to see why their ADJUST button never appeared. */
export function readSticky(raw: string | null | undefined): Choice {
	if (raw === 'true') return true;
	if (raw === 'false') return false;
	return null;
}

/** Interpret a slide URL's `?adjust` flag.

    `?adjust`, `?adjust=on`, `?adjust=1` enable; `?adjust=off`, `?adjust=false`,
    `?adjust=0` disable. An absent flag is `null`, NOT `false` — a URL that says
    nothing about ADJUST must not overwrite what the speaker chose earlier, which
    is precisely what happens when they click through to the next slide (the nav
    links carry no query). */
export function readAdjustParam(search: URLSearchParams | null | undefined): Choice {
	if (!search || !search.has('adjust')) return null;
	const v = (search.get('adjust') ?? '').trim().toLowerCase();
	return v !== 'off' && v !== 'false' && v !== '0';
}

/** Is the ADJUST control OFFERED here? (Offered, not active — the mode itself always
    starts off. This only decides whether the button is in the chrome at all.)

    Highest authority first:

      1. `vite dev` — the authoring environment always offers it, and nothing can take
         it away. Turning ADJUST off on the machine where you author is never what
         anyone means.
      2. The speaker's own explicit choice (`?adjust` / `?adjust=off`), sticky across
         slides. They asked; they outrank the content.
      3. What the SLIDE declares — `adjust: true` in its pages.ts entry (or, deck-wide,
         SlideDeck's `adjust` prop). This is the piece that lets a BUILT deck offer
         ADJUST on the slides that actually demonstrate it, without a URL flag the
         speaker has to remember on stage, and without arming the authoring chrome on
         every other slide in the deck.
      4. Off. That is the default a published slide gets. */
export function resolveCanAdjust(dev: boolean, sticky: Choice, declared: boolean): boolean {
	if (dev === true) return true;
	if (sticky !== null) return sticky;
	return declared === true;
}
