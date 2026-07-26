/*
  Appendix — the pure logic behind AppendixPage / AppendixLink.

  An appendix is a slide you jump INTO and return FROM: a slide as a function
  call, not a destination. The deep-dive a talk only sometimes needs — a proof, a
  full API table, a backup demo. Linking to one used to strand you, because the
  deck's forward march resumed from the appendix rather than from the slide that
  asked the question.

  The return address rides in the URL (`?return=heap-layout.html`) rather than in
  a store, so it survives a reload, a hand-typed link, and the presenter console
  in its own window — none of which share memory with the caller.

  Which makes the return address UNTRUSTED INPUT, and this module the place that
  says so. The two directions are not symmetric:

    - `target` (which appendix to jump into) comes from the AUTHOR, in the slide
      source. Trusted; passed through.
    - `return` (where to go back to) comes from the URL. Anyone can write it.
      Validated here, and anything that is not a plain in-deck slide name is
      refused — an appendix reached by a hostile link renders with NO return
      control rather than with one that walks the audience off the deck.

  Pure and total in the drawCore / adjustAccessCore tradition: a query string with
  no `return`, a `return` naming another origin, one hand-built out of `../` —
  each has one defined answer, and the answer is never "navigate somewhere
  surprising".
*/

/** The query parameter that carries the return address. */
export const RETURN_PARAM = 'return';

/** A slide path is a bare file name WITHIN the deck — `heap-layout.html`. The
    pattern admits nothing that could escape the deck folder: no slashes (so no
    `../`, no protocol-relative `//evil.example`), no scheme, no query or
    fragment of its own. */
const SLIDE_PATH = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;

/** Is this a plain in-deck slide name — the only thing we will navigate to? */
export function isSlidePath(path: string | null | undefined): boolean {
	if (typeof path !== 'string' || path.length === 0 || path.length > 128) return false;
	// `..` cannot traverse without a slash, but a name containing it is never a real
	// slide either, so refuse it outright rather than reason about why it is safe.
	if (path.includes('..')) return false;
	return SLIDE_PATH.test(path);
}

/** Read the return address out of an appendix slide's query string.

    Absent → `null`, which is the ordinary case for a direct link or a bookmark,
    and the caller degrades to the deck instead. Present-but-not-a-slide-path →
    also `null`: a refused address is indistinguishable from no address, so there
    is exactly one degraded path to render and to test. */
export function readReturnParam(search: URLSearchParams | null | undefined): string | null {
	if (!search) return null;
	const raw = search.get(RETURN_PARAM);
	if (raw === null) return null;
	const value = raw.trim();
	return isSlidePath(value) ? value : null;
}

/** The current slide's own name, taken from its pathname — i.e. the return
    address a caller stamps into the link it hands the appendix. */
export function slidePathOf(pathname: string | null | undefined): string | null {
	const last = (pathname ?? '').replace(/\/+$/, '').split('/').pop() ?? '';
	return isSlidePath(last) ? last : null;
}

/** The href that jumps INTO an appendix, carrying the caller's return address.

    `from` is where RETURN will come back to; when it is unknown (or not a slide
    path — e.g. the deck is served from a route we can't name), the link still
    works, it just arrives with no return address and the appendix shows its
    deck-level fallback instead. */
export function appendixHref(target: string, from: string | null | undefined): string {
	const base = `./${target}`;
	if (!from || !isSlidePath(from)) return base;
	return `${base}?${RETURN_PARAM}=${encodeURIComponent(from)}`;
}

/** The href RETURN goes back to. `null` when there is no usable return address. */
export function returnHref(returnTo: string | null | undefined): string | null {
	return returnTo && isSlidePath(returnTo) ? `./${returnTo}` : null;
}

/* ── An appendix is a CHAPTER, not a slide ──────────────────────────────────────

   A real book's appendix runs for as many pages as it needs, and you page through
   it exactly as you page through the body. So does this one: the RUN is the
   contiguous block of `hidden` slides an appendix slide belongs to, and PREV/NEXT
   walk it.

   What makes it a chapter rather than a detour is where the run's EDGES lead. Page
   forward off the end — with NEXT, → or Space, whichever the speaker reaches for —
   and you do not stop dead: you land back on the slide that called you. Page back
   off the front and you land there too, having left the way you came in. So the
   ordinary forward march, applied to an appendix, returns from it. That is the
   whole gesture, and it needs no key of its own.

   Every in-run link carries the return address forward. It has to: paging from the
   first appendix slide to the second must not lose the way home, and since the
   address lives in the URL rather than in a store, "carrying it" means literally
   re-stamping it on each link.

   `hidden` is what makes an appendix a DETOUR — off the linear order, so a straight
   run-through never wanders in. It is optional. Leave it off and the same appendix
   sits in the deck's normal flow, like back matter you can simply page into, and
   still returns to a caller that jumped in from elsewhere. The two are the same
   component; `hidden` only decides whether the deck's forward march can find it. */

/** A slide list entry, as far as this module needs to know. */
export interface RunPage {
	path: string;
	hidden?: boolean;
}

/** Where PREV/NEXT/FIRST/LAST point (mirrors utils/navigate's PageNavigation). */
export interface Nav {
	first: string | undefined;
	last: string | undefined;
	prev: string | undefined;
	next: string | undefined;
}

/** The contiguous run of `hidden` slides containing `currentPath` — the appendix
    chapter this slide belongs to.

    Empty when the slide is not hidden: an appendix living in the deck's normal
    flow has no run of its own, because its neighbours are the deck's. */
export function appendixRun(pages: Array<RunPage>, currentPath: string): Array<RunPage> {
	const here = pages.findIndex((p) => p.path === currentPath);
	if (here < 0 || !pages[here]?.hidden) return [];

	let start = here;
	let end = here;
	while (start > 0 && pages[start - 1]?.hidden) start--;
	while (end < pages.length - 1 && pages[end + 1]?.hidden) end++;
	return pages.slice(start, end + 1);
}

/** Navigation for a slide INSIDE an appendix run.

    PREV/NEXT walk the run; at either edge they leave it, landing on `exitHref` —
    the caller, or the deck when there is nobody to return to. FIRST/LAST are the
    run's own ends, not the deck's, because inside an appendix "last" means the last
    page of the appendix; jumping to the end of the deck from here would be a jump to
    a slide the audience has not reached yet. */
export function appendixNavigation(
	run: Array<RunPage>,
	currentPath: string,
	exitHref: string,
	returnTo: string | null | undefined,
	prefix: string = './'
): Nav {
	const here = run.findIndex((p) => p.path === currentPath);
	if (here < 0) return { first: undefined, last: undefined, prev: undefined, next: undefined };

	const exit = exitHref || undefined;
	const at = (i: number) => carryReturn(prefix + run[i]!.path, returnTo);

	return {
		first: here > 0 ? at(0) : undefined,
		last: here < run.length - 1 ? at(run.length - 1) : undefined,
		// The edges are the point: off the end (or off the front) is the way OUT.
		prev: here > 0 ? at(here - 1) : exit,
		next: here < run.length - 1 ? at(here + 1) : exit
	};
}

/* ── The motion of a detour ─────────────────────────────────────────────────────

   When an appendix opts into `transition`, the animation is the sentence that tells
   the audience we have stepped out of the talk: we travel DOWN into the appendix and
   back UP out of it, while paging within it is ordinary sideways paging. So the
   vertical axis means exactly one thing — entering and leaving — and the horizontal
   axis keeps meaning what it means everywhere else in the deck.

   Which is why leaving ignores DIRECTION. Off the front with PREV, off the end with
   NEXT, or straight out with RETURN: all of them are the appendix closing, so all of
   them travel back up. See lib/styles/appendix-transition.css. */

/** Going in — down to the appendix, which rises from below to meet you. */
export const KIND_IN = 'appendix-in';
/** Coming out — back up to the talk, whichever control did it. */
export const KIND_OUT = 'appendix-out';
/** Paging within the appendix — sideways, like the rest of the deck. */
export const KIND_STEP = 'appendix-step';

/** Which transition each edge of the nav bar performs, for a slide in a run.

    A step that stays inside the appendix is a step; a step off either end is the
    appendix closing. This is knowable only here, because the NavigationBar picks its
    transition from the LEAVING slide (pages.ts), and cannot see that the slide it is
    leaving to lies outside the appendix. */
export function appendixKinds(
	run: Array<RunPage>,
	currentPath: string
): { next: string; prev: string } {
	const here = run.findIndex((p) => p.path === currentPath);
	if (here < 0) return { next: KIND_STEP, prev: KIND_STEP };
	return {
		next: here < run.length - 1 ? KIND_STEP : KIND_OUT,
		prev: here > 0 ? KIND_STEP : KIND_OUT
	};
}

/** Stamp the return address onto a link, so paging within an appendix keeps the way
    home. A no-op when there is no address, or when the href already carries one. */
export function carryReturn(href: string, returnTo: string | null | undefined): string {
	if (!href || !returnTo || !isSlidePath(returnTo)) return href;
	if (href.includes(`${RETURN_PARAM}=`)) return href;
	const sep = href.includes('?') ? '&' : '?';
	return `${href}${sep}${RETURN_PARAM}=${encodeURIComponent(returnTo)}`;
}

/** The same, for a whole navigation set — used by an appendix that lives in the
    deck's NORMAL flow (no run of its own), so that paging through it with the
    ordinary PREV/NEXT still carries the caller's address along. */
export function carryReturnThrough(nav: Nav, returnTo: string | null | undefined): Nav {
	const one = (href: string | undefined) => (href ? carryReturn(href, returnTo) : undefined);
	return { first: one(nav.first), last: one(nav.last), prev: one(nav.prev), next: one(nav.next) };
}
