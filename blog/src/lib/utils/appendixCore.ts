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

  Nested calls use a STACK in that same param: comma-separated slide names, oldest
  first, most recent caller on top:

    ?return=slide-pages.html                  hub → child deck
    ?return=slide-pages.html,webpage.html     hub → deck → appendix

  RETURN pops the top. Each level can be an in-deck slide (`./x.html`) or a hub
  card outside this folder (`../slide-pages.html`).

  Which makes the return address UNTRUSTED INPUT, and this module the place that
  says so. The two directions are not symmetric:

    - `target` (which appendix to jump into) comes from the AUTHOR, in the slide
      source. Trusted; passed through.
    - `return` (where to go back to) comes from the URL. Anyone can write it.
      Validated here, and anything that is not a plain slide name is refused —
      an appendix reached by a hostile link renders with NO return control rather
      than with one that walks the audience off the deck.

  Pure and total in the drawCore / adjustAccessCore tradition: a query string with
  no `return`, a `return` naming another origin, one hand-built out of `../` —
  each has one defined answer, and the answer is never "navigate somewhere
  surprising".
*/

/** The query parameter that carries the return address (single or stack). */
export const RETURN_PARAM = 'return';

/** Stack separator — cannot appear in a valid slide path. */
export const RETURN_STACK_SEP = ',';

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

/** Parse a return stack string (possibly URI-encoded). Invalid segments dropped. */
export function parseReturnStack(raw: string | null | undefined): string[] {
	if (typeof raw !== 'string' || !raw.trim()) return [];
	let text = raw.trim();
	try {
		// URLSearchParams already decodes once; tolerate a second layer.
		if (text.includes('%')) text = decodeURIComponent(text);
	} catch {
		/* keep raw */
	}
	return text
		.split(RETURN_STACK_SEP)
		.map((s) => s.trim())
		.filter(isSlidePath);
}

/** Encode a stack for `?return=`. Empty → ''. */
export function encodeReturnStack(stack: string[] | null | undefined): string {
	if (!Array.isArray(stack) || !stack.length) return '';
	return stack.filter(isSlidePath).join(RETURN_STACK_SEP);
}

/** Full return stack from the query string (oldest → newest). */
export function readReturnStack(search: URLSearchParams | null | undefined): string[] {
	if (!search) return [];
	return parseReturnStack(search.get(RETURN_PARAM));
}

/** Top of the stack (most recent caller) — single-level API for older call sites. */
export function readReturnParam(search: URLSearchParams | null | undefined): string | null {
	const stack = readReturnStack(search);
	return stack.length ? stack[stack.length - 1]! : null;
}

/** Push `from` onto the stack (no consecutive duplicates). */
export function pushReturn(
	stack: string[] | null | undefined,
	from: string | null | undefined
): string[] {
	const base = Array.isArray(stack) ? stack.filter(isSlidePath) : [];
	if (!from || !isSlidePath(from)) return base;
	if (base[base.length - 1] === from) return base;
	return [...base, from];
}

/** Pop the top caller. */
export function popReturn(stack: string[] | null | undefined): {
	to: string | null;
	rest: string[];
} {
	const base = Array.isArray(stack) ? stack.filter(isSlidePath) : [];
	if (!base.length) return { to: null, rest: [] };
	return { to: base[base.length - 1]!, rest: base.slice(0, -1) };
}

/** The current slide's own name, taken from its pathname — i.e. the return
    address a caller stamps into the link it hands the appendix. */
export function slidePathOf(pathname: string | null | undefined): string | null {
	const last = (pathname ?? '').replace(/\/+$/, '').split('/').pop() ?? '';
	return isSlidePath(last) ? last : null;
}

/** The href that jumps INTO an appendix, carrying the return stack.

    `from` is pushed onto `existingStack` (from the current URL). When `from` is
    unknown the stack is still carried so a hub return is not lost. */
export function appendixHref(
	target: string,
	from: string | null | undefined,
	existingStack: string[] | null | undefined = null
): string {
	const base = `./${target}`;
	const stack = pushReturn(existingStack ?? [], from);
	if (!stack.length) return base;
	return `${base}?${RETURN_PARAM}=${encodeURIComponent(encodeReturnStack(stack))}`;
}

/** The href RETURN goes back to (same folder). `null` when unusable. */
export function returnHref(returnTo: string | null | undefined): string | null {
	return returnTo && isSlidePath(returnTo) ? `./${returnTo}` : null;
}

/**
 * Return into a *parent* folder (e.g. hub card → group deck).
 *
 * Same-deck appendix RETURN is `./slide.html`. Opening a child deck from a hub
 * card stamps `?return=slide-pages.html`; the child lives in a subfolder, so
 * the way home is one level up: `../slide-pages.html` → `/references/slide-pages.html`.
 */
export function parentReturnHref(returnTo: string | null | undefined): string | null {
	return returnTo && isSlidePath(returnTo) ? `../${returnTo}` : null;
}

/** sessionStorage key for a deck's return stack (survives full-page paging). */
export function catalogReturnStorageKey(deckId: string): string {
	const id = typeof deckId === 'string' ? deckId.trim() : '';
	return id ? `gp-catalog-return:${id}` : 'gp-catalog-return';
}

/**
 * A hub/catalog return names a slide **outside** this deck (e.g. hub card
 * `slide-pages.html`). In-deck appendix returns name a path in `pages`.
 */
export function isHubReturn(
	returnTo: string | null | undefined,
	pages: Array<{ path?: string } | null | undefined> | null | undefined
): boolean {
	if (!returnTo || !isSlidePath(returnTo)) return false;
	const list = Array.isArray(pages) ? pages : [];
	return !list.some((p) => p && p.path === returnTo);
}

/** Href for one stack entry: parent folder if hub, else same-deck. */
export function resolveReturnHref(
	returnTo: string | null | undefined,
	pages: Array<{ path?: string } | null | undefined> | null | undefined
): string | null {
	if (!returnTo || !isSlidePath(returnTo)) return null;
	if (isHubReturn(returnTo, pages)) return parentReturnHref(returnTo);
	return returnHref(returnTo);
}

/**
 * Build the navigation target for RETURN: pop the stack, resolve the top,
 * re-attach the remainder as `?return=`.
 */
export function exitHrefFromStack(
	stack: string[] | null | undefined,
	pages: Array<{ path?: string } | null | undefined> | null | undefined,
	deckHome: string | null | undefined
): string {
	const { to, rest } = popReturn(stack);
	if (!to) return deckHome && isSlidePath(deckHome) ? `./${deckHome}` : '';
	const base = resolveReturnHref(to, pages);
	if (!base) return deckHome && isSlidePath(deckHome) ? `./${deckHome}` : '';
	return rest.length ? carryReturn(base, rest) : base;
}

/**
 * Full stack from URL merged with sessionStorage (for paging that dropped the
 * query, or a partial stamp that lost an outer hub caller).
 */
export function resolveReturnStack(
	search: URLSearchParams | null | undefined,
	deckId: string,
	storage: { getItem(key: string): string | null } | null | undefined,
	pages: Array<{ path?: string } | null | undefined> | null | undefined = null
): string[] {
	const fromUrl = readReturnStack(search);
	if (!storage) return fromUrl;
	try {
		const existing = parseReturnStack(storage.getItem(catalogReturnStorageKey(deckId)));
		if (!fromUrl.length) return existing;
		if (!existing.length) return fromUrl;
		return mergeReturnStacks(existing, fromUrl, pages);
	} catch {
		return fromUrl;
	}
}

/**
 * Combine a stored stack with one just read from the URL.
 *
 * URL wins when it extends the stored stack (deeper nested call). When the URL
 * only has the *top* of a longer stored stack (or a lone in-deck return after a
 * hub was stored), keep the outer callers so hub → deck → appendix still unwinds.
 */
export function mergeReturnStacks(
	existing: string[] | null | undefined,
	fromUrl: string[] | null | undefined,
	pages: Array<{ path?: string } | null | undefined> | null | undefined = null
): string[] {
	const ex = Array.isArray(existing) ? existing.filter(isSlidePath) : [];
	const url = Array.isArray(fromUrl) ? fromUrl.filter(isSlidePath) : [];
	if (!url.length) return ex;
	if (!ex.length) return url;

	// URL extends existing (same prefix, deeper).
	if (url.length >= ex.length && ex.every((s, i) => url[i] === s)) return url;

	// URL is a strict suffix of existing — lost outer callers; keep storage.
	if (ex.length > url.length) {
		const start = ex.length - url.length;
		if (url.every((s, i) => ex[start + i] === s)) return ex;
	}

	// Stored hub prefix + in-deck-only URL (legacy single-level stamp after hub).
	if (pages) {
		const hubs: string[] = [];
		for (const s of ex) {
			if (isHubReturn(s, pages)) hubs.push(s);
			else break;
		}
		if (hubs.length && url.every((s) => !isHubReturn(s, pages))) {
			if (!hubs.every((h, i) => url[i] === h)) return [...hubs, ...url];
		}
	}

	return url;
}

/** Remember the URL stack whenever it is non-empty (full stack, not hub-only). */
export function rememberReturnStack(
	search: URLSearchParams | null | undefined,
	deckId: string,
	storage:
		| {
				getItem?(key: string): string | null;
				setItem(key: string, value: string): void;
		  }
		| null
		| undefined,
	pages: Array<{ path?: string } | null | undefined> | null | undefined = null
): void {
	if (!storage) return;
	const fromUrl = readReturnStack(search);
	if (!fromUrl.length) return;
	try {
		const key = catalogReturnStorageKey(deckId);
		let existing: string[] = [];
		try {
			existing = parseReturnStack(storage.getItem?.(key) ?? null);
		} catch {
			existing = [];
		}
		const merged = mergeReturnStacks(existing, fromUrl, pages);
		storage.setItem(key, encodeReturnStack(merged));
	} catch {
		/* private mode */
	}
}

/** @deprecated use resolveReturnStack + isHubReturn; kept for older call sites */
export function resolveHubReturn(
	search: URLSearchParams | null | undefined,
	pages: Array<{ path?: string } | null | undefined> | null | undefined,
	deckId: string,
	storage: { getItem(key: string): string | null } | null | undefined
): string | null {
	const stack = resolveReturnStack(search, deckId, storage, pages);
	const hub = stack.find((s) => isHubReturn(s, pages));
	return hub ?? null;
}

/** @deprecated use rememberReturnStack */
export function rememberHubReturn(
	search: URLSearchParams | null | undefined,
	pages: Array<{ path?: string } | null | undefined> | null | undefined,
	deckId: string,
	storage: {
		getItem?(key: string): string | null;
		setItem(key: string, value: string): void;
	} | null | undefined
): void {
	rememberReturnStack(search, deckId, storage, pages);
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
	/** Full return stack (or a single slide name) carried on in-run links. */
	returnTo: string | string[] | null | undefined,
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

/** Stamp the return stack onto a link, so paging keeps every caller.
    Accepts a single slide name or a full stack (oldest → newest).
    A no-op when there is nothing usable, or when the href already carries `return`. */
export function carryReturn(
	href: string,
	returnTo: string | string[] | null | undefined
): string {
	if (!href) return href;
	if (href.includes(`${RETURN_PARAM}=`)) return href;
	const encoded = Array.isArray(returnTo)
		? encodeReturnStack(returnTo)
		: returnTo && isSlidePath(returnTo)
			? returnTo
			: '';
	if (!encoded) return href;
	const sep = href.includes('?') ? '&' : '?';
	return `${href}${sep}${RETURN_PARAM}=${encodeURIComponent(encoded)}`;
}

/** The same, for a whole navigation set — used by an appendix that lives in the
    deck's NORMAL flow (no run of its own), so that paging through it with the
    ordinary PREV/NEXT still carries the caller's address along. Also used by
    SlideDeck to re-stamp a hub/nested stack on every deck-level NEXT/PREV. */
export function carryReturnThrough(
	nav: Nav,
	returnTo: string | string[] | null | undefined
): Nav {
	const one = (href: string | undefined) => (href ? carryReturn(href, returnTo) : undefined);
	return { first: one(nav.first), last: one(nav.last), prev: one(nav.prev), next: one(nav.next) };
}
