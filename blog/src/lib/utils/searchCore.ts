// Full-deck search — the pure, total core.
//
// The deck has no search: "which slide mentioned backpressure?" is answered by
// paging. This module is the arithmetic behind a filter box in the Table of
// Contents. It is pure and total in the drawCore/connectorCore discipline —
// junk input (a non-string source, a null doc, an empty query) yields a defined,
// drawable answer, never a throw and never `undefined` leaking into the UI.
//
// The index is built at BUILD time from the slide *sources* (a `?raw` glob, the
// same drift-proof trick ViewSource uses — a raw import of the real file cannot
// drift from what is on screen). searchIndex.ts owns the glob; everything here is
// a string function you can unit-test with hand-written input.

/** One searchable slide: its route `path` (as in pages.ts), its `title` (the
    same string the TOC shows), its `text` — the visible prose of its source with
    tags and script blocks stripped out — and its 1-based `number`, the slide's
    position in the deck's linear order (the same number OVERVIEW and the console
    ToC show). `number` is optional so a caller with no notion of position (a
    hand-written test doc, say) still type-checks. */
export interface SearchDoc {
	path: string;
	title: string;
	text: string;
	number?: number;
}

/** A match. `where` says whether the query hit the slide's title, its file name
    (the route path), its page number, or its body; `snippet` is a short window
    of body text around the first body hit (empty for a title match, since the
    title is already shown; the file name for a path hit, "#N" for a number hit
    — so the row can show WHY it matched). `number`, when the doc carried one,
    rides along on every hit regardless of what actually matched. */
export interface SearchHit {
	path: string;
	title: string;
	snippet: string;
	where: 'title' | 'path' | 'number' | 'body';
	number?: number;
}

const SCRIPT_OR_STYLE = /<(script|style)\b[\s\S]*?<\/\1>/gi;
const HTML_COMMENT = /<!--[\s\S]*?-->/g;
const MUSTACHE = /\{[^{}]*\}/g; // Svelte {#each}/{expr} — logic, not prose
const TAG = /<[^>]+>/g;
const WHITESPACE = /\s+/g;

const ENTITIES: Record<string, string> = {
	'&amp;': '&',
	'&lt;': '<',
	'&gt;': '>',
	'&quot;': '"',
	'&#39;': "'",
	'&nbsp;': ' '
};

/** Reduce a slide's raw `.svelte` source to the words a reader would see. Removes
    `<script>`/`<style>` blocks (so imports and component names are not searched),
    HTML comments, Svelte mustaches, and every remaining tag; decodes the handful
    of entities prose actually uses; collapses whitespace. Total: a non-string in
    is an empty string out. */
export function stripToText(src: unknown): string {
	if (typeof src !== 'string') return '';
	let text = src
		.replace(SCRIPT_OR_STYLE, ' ')
		.replace(HTML_COMMENT, ' ')
		.replace(MUSTACHE, ' ')
		.replace(TAG, ' ');
	for (const [entity, char] of Object.entries(ENTITIES)) {
		text = text.split(entity).join(char);
	}
	return text.replace(WHITESPACE, ' ').trim();
}

/** Build a deck→path→text index from a `?raw` glob's module map. Keys look like
    `/src/routes/<deck>/<slide-path>/+page.svelte`; the last two directory
    segments are the deck and the slide path (which equals its pages.ts `path`).
    Pure — searchIndex.ts feeds it the real glob, tests feed it a literal. */
export function buildDeckIndex(
	modules: Record<string, unknown>
): Record<string, Record<string, string>> {
	const byDeck: Record<string, Record<string, string>> = {};
	for (const [file, src] of Object.entries(modules ?? {})) {
		const parts = file.split('/');
		const path = parts[parts.length - 2];
		const deck = parts[parts.length - 3];
		if (!deck || !path) continue;
		(byDeck[deck] ??= {})[path] = stripToText(src);
	}
	return byDeck;
}

/** A window of `text` around the first case-insensitive occurrence of `needle`,
    with `…` where it was clipped. Empty if `needle` is absent. `radius` chars of
    context sit on each side of the match. */
export function snippetAround(text: string, needle: string, radius = 48): string {
	if (typeof text !== 'string' || !needle) return '';
	const at = text.toLowerCase().indexOf(needle.toLowerCase());
	if (at < 0) return '';
	const start = Math.max(0, at - radius);
	const end = Math.min(text.length, at + needle.length + radius);
	const lead = start > 0 ? '…' : '';
	const tail = end < text.length ? '…' : '';
	return `${lead}${text.slice(start, end).trim()}${tail}`;
}

/** The part of a slide's route path a search should match: the file name without
    its `.html` extension. Slides are named for what they are
    (`adjust-styles-guard.html`), so the name is real, searchable metadata — but
    keeping the extension in would make "html" (and every prefix of it) match the
    whole deck. Total. */
export function searchablePath(path: unknown): string {
	if (typeof path !== 'string') return '';
	return path.replace(/\.html?$/i, '');
}

/** Filter `docs` to those matching `query` (a case-insensitive substring of the
    title, the file name, the 1-based page number, or the body), in deck order.
    A title hit comes back with an empty snippet; a file-name hit shows the file
    name as its snippet; a number hit shows "#N"; a body-only hit carries a
    snippet around the match. Numeric matching is a substring of the number's
    digits, same as every other field — "1" finds pages 1, 10-19, 21… — and a doc
    with no `number` simply can't match that way. An empty or whitespace query
    returns no hits — the caller shows the full list instead, so an untouched
    search box leaves the TOC exactly as it was. Total: a doc with a missing
    title/text is treated as empty rather than throwing. */
export function searchDocs(docs: SearchDoc[], query: string): SearchHit[] {
	const q = (typeof query === 'string' ? query : '').trim().toLowerCase();
	if (!q) return [];
	const hits: SearchHit[] = [];
	for (const doc of docs ?? []) {
		if (!doc) continue;
		const title = typeof doc.title === 'string' ? doc.title : '';
		const text = typeof doc.text === 'string' ? doc.text : '';
		const name = searchablePath(doc.path);
		const number = Number.isFinite(doc.number) ? (doc.number as number) : undefined;
		if (title.toLowerCase().includes(q)) {
			hits.push({ path: doc.path, title, snippet: '', where: 'title', number });
		} else if (name.toLowerCase().includes(q)) {
			hits.push({ path: doc.path, title, snippet: doc.path, where: 'path', number });
		} else if (number != null && String(number).includes(q)) {
			hits.push({ path: doc.path, title, snippet: `#${number}`, where: 'number', number });
		} else if (text.toLowerCase().includes(q)) {
			hits.push({ path: doc.path, title, snippet: snippetAround(text, q), where: 'body', number });
		}
	}
	return hits;
}
