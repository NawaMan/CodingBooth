// Arriving BACKWARDS — the note a PREV leaves for the slide it pages to.
//
// A slide is its own page, so a <Steps> build has no idea how it was reached and
// always started at step 0. Paging back from slide N+1 to a slide whose build
// MOVED something then showed it at its old place again, and the next Space
// replayed the move. Paging back should instead land where the slide was left:
// the build spent, every Fragment showing.
//
// PREV writes a mark naming the slide it pages to (deckNav.navigate), and that
// slide's Steps reads it once. The mark carries its time, so a mark nobody
// consumed (a slide with no build) cannot fire on a much later visit, and its
// path, so it only ever applies to the slide PREV was going to.
//
// Pure: strings in, values out. The storage calls live in deckNav.ts.

/** The sessionStorage key the mark lives under. */
export const ARRIVAL_KEY = 'gp:arrive-at-end';

/** How long a mark stays good. A page load takes well under this. */
export const ARRIVAL_MAX_AGE_MS = 15_000;

/** A path without its trailing slashes, so `/a/b.html/` and `/a/b.html` match. */
export function normalizePath(path: string): string {
	return path.replace(/\/+$/, '') || '/';
}

/** The mark for paging to `href` (resolved against `base`), or null when `href`
    is not a URL at all. */
export function arrivalMark(href: string, base: string, now: number): string | null {
	try {
		const path = normalizePath(new URL(href, base).pathname);
		return JSON.stringify({ path, at: now });
	} catch {
		return null;
	}
}

/** True when `raw` is a fresh mark for `pathname`. Anything else — no mark, junk,
    another slide's mark, a stale one — is false. */
export function arrivesAtEnd(
	raw: string | null,
	pathname: string,
	now: number,
	maxAgeMs: number = ARRIVAL_MAX_AGE_MS
): boolean {
	if (!raw) return false;
	let mark: unknown;
	try {
		mark = JSON.parse(raw);
	} catch {
		return false;
	}
	if (!mark || typeof mark !== 'object') return false;
	const { path, at } = mark as { path?: unknown; at?: unknown };
	if (typeof path !== 'string' || typeof at !== 'number' || !Number.isFinite(at)) return false;
	const age = now - at;
	if (age < 0 || age > maxAgeMs) return false;
	return path === normalizePath(pathname);
}
