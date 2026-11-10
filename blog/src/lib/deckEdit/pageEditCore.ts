// Pure half of deck structure editing (add / remove / duplicate / rename slides
// via Overview).
//
// A slide is a route folder + a pages.ts entry. This module owns:
//   - path slug / validation (never invent a bad folder name)
//   - line-based insert/remove/rename/duplicate of one-line pages.ts entries
//     (same bargain as wire-og.mjs / patchSource: refuse multi-line or
//     unparseable entries)
//   - the two-file scaffold (+layout.js + +page.svelte) as strings
//   - finding and rewriting links to a slide whose path changes
//
// Total: garbage input yields null / empty / a refused result, never a throw.

export type PageTemplate = 'content' | 'title';

export type PagesEditOk = { ok: true; source: string };
export type PagesEditFail = { ok: false; error: string };
export type PagesEditResult = PagesEditOk | PagesEditFail;

/** Characters allowed in a slide stem: lowercase alnum and hyphen, no leading hyphen. */
const STEM_RE = /^[a-z0-9][a-z0-9-]*$/;

/** One-line pages.ts entry: `{ path: "…", title: "…" … },` with optional trailing comment. */
const ENTRY_LINE =
	/^(\s*)\{(.*)\}(\s*,?\s*(?:\/\/.*)?)$/;

/** Extract path from an entry body (inside the braces). */
function pathFromBody(body: string): string | null {
	const m = body.match(/\bpath\s*:\s*["']([^"']+)["']/);
	return m ? m[1] : null;
}

/**
 * Title → slide path stem. "My New Slide!" → "my-new-slide".
 * Empty / pure punctuation → "slide". Caller still appends `.html`.
 */
export function slugifyStem(title: string): string {
	const s = String(title ?? '')
		.normalize('NFKD')
		.replace(/[\u0300-\u036f]/g, '')
		.toLowerCase()
		.replace(/[^a-z0-9]+/g, '-')
		.replace(/^-+|-+$/g, '')
		.replace(/-+/g, '-');
	if (!s || !STEM_RE.test(s)) return 'slide';
	// Cap length so paths stay readable in the grid.
	return s.length > 48 ? s.slice(0, 48).replace(/-+$/, '') || 'slide' : s;
}

/**
 * Normalize user path input to a `*.html` slide path, or null if unusable.
 * Accepts with or without `.html`; lowercases; strips leading/trailing junk.
 */
export function normalizeSlidePath(input: string): string | null {
	let raw = String(input ?? '').trim().toLowerCase();
	if (!raw) return null;
	// Reject path separators and traversal up front.
	if (raw.includes('/') || raw.includes('\\') || raw.includes('..')) return null;
	raw = raw.replace(/^\.+/, '');
	if (!raw.endsWith('.html')) {
		raw = raw.replace(/\.html?$/i, '');
		raw = `${raw}.html`;
	}
	const stem = raw.replace(/\.html$/i, '');
	if (!STEM_RE.test(stem)) return null;
	return `${stem}.html`;
}

/** True when `path` is a safe one-segment `name.html` slide path. */
export function isValidSlidePath(path: string): boolean {
	return normalizeSlidePath(path) === path;
}

/** Format a one-line pages.ts entry matching the house style. */
export function formatPagesEntry(path: string, title: string): string {
	const p = normalizeSlidePath(path);
	const t = String(title ?? '').replace(/\\/g, '\\\\').replace(/"/g, '\\"');
	if (!p) return '';
	return `{ path: "${p}", title: "${t}" },`;
}

/**
 * List every one-line entry's path, in file order. Multi-line / non-entry lines
 * are skipped (they are not in the editable set).
 */
export function listEntryPaths(source: string): string[] {
	const paths: string[] = [];
	for (const line of String(source ?? '').split('\n')) {
		const m = line.match(ENTRY_LINE);
		if (!m) continue;
		const p = pathFromBody(m[2]);
		if (p) paths.push(p);
	}
	return paths;
}

/**
 * Insert a new one-line entry after `afterPath` (or append if null / "").
 * Refuses: bad path, duplicate path, missing afterPath, multi-line match chaos.
 */
export function insertPagesEntry(
	source: string,
	path: string,
	title: string,
	afterPath: string | null
): PagesEditResult {
	const norm = normalizeSlidePath(path);
	if (!norm) return { ok: false, error: `invalid slide path "${path}"` };
	if (!String(title ?? '').trim()) return { ok: false, error: 'title is required' };

	const existing = listEntryPaths(source);
	if (existing.includes(norm)) {
		return { ok: false, error: `pages.ts already lists "${norm}"` };
	}

	const entry = formatPagesEntry(norm, String(title).trim());
	const lines = String(source ?? '').split('\n');

	// Collect single-line entry indices for insert placement.
	const entryIdx: number[] = [];
	for (let i = 0; i < lines.length; i++) {
		const m = lines[i].match(ENTRY_LINE);
		if (!m) continue;
		if (pathFromBody(m[2])) entryIdx.push(i);
	}

	let insertAt: number;
	if (afterPath == null || afterPath === '') {
		// Append after the last entry, or before `];` if the array is empty.
		if (entryIdx.length) {
			insertAt = entryIdx[entryIdx.length - 1] + 1;
		} else {
			const close = lines.findIndex((l) => /^\s*\];\s*$/.test(l) || /^\s*\]\s*;?\s*$/.test(l));
			if (close < 0) return { ok: false, error: 'cannot find pages array closing bracket' };
			insertAt = close;
		}
	} else {
		const afterNorm = normalizeSlidePath(afterPath) ?? afterPath;
		let found = -1;
		for (const i of entryIdx) {
			const m = lines[i].match(ENTRY_LINE)!;
			if (pathFromBody(m[2]) === afterNorm) {
				found = i;
				break;
			}
		}
		if (found < 0) return { ok: false, error: `no pages.ts entry for "${afterPath}"` };
		insertAt = found + 1;
	}

	// Indent like neighboring entries.
	let indent = '\t';
	if (entryIdx.length) {
		const sample = lines[entryIdx[0]].match(/^(\s*)/)?.[1];
		if (sample != null) indent = sample;
	} else {
		// Peek at the line before the closing bracket.
		const prev = lines[insertAt - 1] ?? '';
		const m = prev.match(/^(\s+)/);
		if (m) indent = m[1];
		else indent = '    ';
	}

	const next = [...lines];
	next.splice(insertAt, 0, `${indent}${entry}`);
	return { ok: true, source: next.join('\n') };
}

/**
 * Remove the one-line entry for `path`. Refuses if missing or if the only match
 * is not a clean single-line entry (would need a human).
 */
export function removePagesEntry(source: string, path: string): PagesEditResult {
	const norm = normalizeSlidePath(path) ?? String(path ?? '');
	if (!norm) return { ok: false, error: 'path is required' };

	const lines = String(source ?? '').split('\n');
	const keep: string[] = [];
	let removed = false;
	for (const line of lines) {
		const m = line.match(ENTRY_LINE);
		if (m && pathFromBody(m[2]) === norm) {
			const body = m[2];
			// Nested object or comment-inside braces → leave alone (wire-og bargain).
			if (/[{}]/.test(body) || body.includes('//')) {
				return {
					ok: false,
					error: `entry for "${norm}" is not a simple one-line object — edit pages.ts by hand`
				};
			}
			removed = true;
			continue; // drop the line
		}
		keep.push(line);
	}
	if (!removed) return { ok: false, error: `no pages.ts entry for "${norm}"` };
	return { ok: true, source: keep.join('\n') };
}

/** The one clean one-line entry for `path`, or why it can't be edited. A body with
    nested braces or a comment inside is left for a human (wire-og bargain). */
function findSimpleEntry(
	lines: string[],
	path: string
): { ok: true; index: number } | PagesEditFail {
	for (let i = 0; i < lines.length; i++) {
		const m = lines[i].match(ENTRY_LINE);
		if (!m || pathFromBody(m[2]) !== path) continue;
		if (/[{}]/.test(m[2]) || m[2].includes('//')) {
			return {
				ok: false,
				error: `entry for "${path}" is not a simple one-line object — edit pages.ts by hand`
			};
		}
		return { ok: true, index: i };
	}
	return { ok: false, error: `no pages.ts entry for "${path}"` };
}

/** A string field (`path` / `title` / `image`) in an entry body: the whole
    `name: "…"` match, so it can be replaced or dropped. */
function fieldRe(name: string): RegExp {
	return new RegExp(`\\b${name}\\s*:\\s*(["'])(?:\\\\.|(?!\\1).)*\\1`);
}

function quote(s: string): string {
	return `"${String(s).replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"`;
}

/** Rewrite one entry line's path and/or title, keeping every other field
    (`hidden`, `adjust`, `transition`, …) and the line's own spacing. */
function rewriteEntryLine(line: string, next: { path?: string; title?: string }): string | null {
	let out = line;
	if (next.path != null) {
		if (!fieldRe('path').test(out)) return null;
		out = out.replace(fieldRe('path'), `path: ${quote(next.path)}`);
	}
	if (next.title != null) {
		if (!fieldRe('title').test(out)) return null;
		out = out.replace(fieldRe('title'), `title: ${quote(next.title)}`);
	}
	return out;
}

/**
 * Change an entry's path and/or title in place. Refuses: missing / non-simple
 * entry, a bad new path, a new path already listed, an empty title.
 */
export function renamePagesEntry(
	source: string,
	path: string,
	next: { path?: string; title?: string }
): PagesEditResult {
	const norm = normalizeSlidePath(path) ?? String(path ?? '');
	const lines = String(source ?? '').split('\n');
	const at = findSimpleEntry(lines, norm);
	if (!at.ok) return at;

	const want: { path?: string; title?: string } = {};
	if (next.path != null && next.path !== norm) {
		const np = normalizeSlidePath(next.path);
		if (!np) return { ok: false, error: `invalid slide path "${next.path}"` };
		if (np !== norm && listEntryPaths(source).includes(np)) {
			return { ok: false, error: `pages.ts already lists "${np}"` };
		}
		want.path = np;
	}
	if (next.title != null) {
		const t = String(next.title).trim();
		if (!t) return { ok: false, error: 'title is required' };
		want.title = t;
	}
	const line = rewriteEntryLine(lines[at.index], want);
	if (line == null) return { ok: false, error: `entry for "${norm}" has no plain path/title — edit pages.ts by hand` };
	lines[at.index] = line;
	return { ok: true, source: lines.join('\n') };
}

/**
 * Insert a copy of `path`'s entry right after it, with a new path and title. The
 * copy keeps the original's other fields, minus `image` (that social card is a
 * picture of the ORIGINAL slide).
 */
export function duplicatePagesEntry(
	source: string,
	path: string,
	newPath: string,
	title: string
): PagesEditResult {
	const norm = normalizeSlidePath(path) ?? String(path ?? '');
	const np = normalizeSlidePath(newPath);
	if (!np) return { ok: false, error: `invalid slide path "${newPath}"` };
	const t = String(title ?? '').trim();
	if (!t) return { ok: false, error: 'title is required' };
	if (listEntryPaths(source).includes(np)) return { ok: false, error: `pages.ts already lists "${np}"` };
	const lines = String(source ?? '').split('\n');
	const at = findSimpleEntry(lines, norm);
	if (!at.ok) return at;
	let copy = rewriteEntryLine(lines[at.index], { path: np, title: t });
	if (copy == null) return { ok: false, error: `entry for "${norm}" has no plain path/title — edit pages.ts by hand` };
	copy = copy.replace(new RegExp(`,?\\s*${fieldRe('image').source}`), '');
	lines.splice(at.index + 1, 0, copy);
	return { ok: true, source: lines.join('\n') };
}

// ─── Links to a slide ───────────────────────────────────────────────────────
//
// A slide `<deck>/<name>.html` is referred to two ways in route sources:
//   - from ANY route file, deck-qualified: `slides/old.html`, `../slides/old.html`,
//     `/slides/old.html`, and ViewSource's own `src/routes/slides/old.html/+page.svelte`;
//   - from a file INSIDE the same deck folder, bare: `"old.html"`, `'./old.html'`,
//     `to="old.html?x"` — a relative link from one slide resolves to its sibling —
//     and `'/old.html'`, which the deck's index redirect appends to its own pathname.
// A bare name is only ever read inside its own deck: `title.html` in another deck
// is that deck's title. Matches are whole names (`old.html` never matches
// `bold.html`) ending at a quote, `?`, `#`, `/` or backtick.

function escRe(s: string): string {
	return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function refPatterns(deck: string, name: string, sameDeck: boolean): RegExp[] {
	const end = `(?=[?#/"'\`])`;
	const res = [new RegExp(`(?<=[/"'\`])${escRe(deck)}/${escRe(name)}${end}`, 'g')];
	if (sameDeck) res.push(new RegExp(`(?<=["'\`](?:\\.?/)?)${escRe(name)}${end}`, 'g'));
	return res;
}

/** How many references to `<deck>/<name>` a file holds. */
export function countSlideRefs(source: string, deck: string, name: string, sameDeck: boolean): number {
	let n = 0;
	for (const re of refPatterns(deck, name, sameDeck)) n += (String(source).match(re) ?? []).length;
	return n;
}

/** Point every reference to `<deck>/<from>` at `<deck>/<to>` instead. */
export function rewriteSlideRefs(
	source: string,
	deck: string,
	from: string,
	to: string,
	sameDeck: boolean
): { source: string; count: number } {
	let out = String(source);
	let count = 0;
	const [qualified, bare] = refPatterns(deck, from, sameDeck);
	out = out.replace(qualified, () => (count++, `${deck}/${to}`));
	if (bare) out = out.replace(bare, () => (count++, to));
	return { source: out, count };
}

/** Standard slide +layout.js — both lines required for the static build. */
export const LAYOUT_JS = `export const prerender = true;
export const trailingSlash = "never";
`;

/** Escape for embedding in a Svelte attribute / text. */
function escAttr(s: string): string {
	return String(s).replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;');
}

export interface ScaffoldOpts {
	/** Deck folder under src/routes, e.g. "slides". */
	deck?: string;
	/** Slide path segment, e.g. "my-slide.html". */
	path?: string;
}

/** Path string shown in ViewSource / used by SOURCE EDIT, if deck+path known. */
export function scaffoldSourcePath(deck: string, slidePath: string): string {
	const d = String(deck ?? '').trim();
	const p = String(slidePath ?? '').trim();
	if (!d || !p) return '';
	return `src/routes/${d}/${p}/+page.svelte`;
}

/**
 * Scaffold `+page.svelte` for the chosen template.
 *
 * Always includes `<ViewSource>` so ☰ → SOURCE / EDIT work on brand-new slides
 * (without it the hamburger has no content-edit entry — the deck shell only
 * offers those rows while a ViewSource/SourceView is mounted).
 */
export function scaffoldPage(
	template: PageTemplate,
	title: string,
	opts: ScaffoldOpts = {}
): string {
	const t = String(title ?? '').trim() || 'Untitled';
	const safe = escAttr(t);
	const srcPath = scaffoldSourcePath(opts.deck ?? '', opts.path ?? '');
	const pathLit = srcPath ? srcPath.replace(/\\/g, '\\\\').replace(/'/g, "\\'") : '';

	if (template === 'title') {
		return `<!--
  Slide: ${t}
-->
<script>
	import TitlePage from '$lib/templates/TitlePage.svelte';
	import ViewSource from '$lib/components/ViewSource.svelte';
	import source from './+page.svelte?raw';

	const path = '${pathLit}';
</script>

<TitlePage>
	<span slot="title">${safe}</span>
	<span slot="subtitle"></span>
</TitlePage>

<ViewSource {source} {path} />
`;
	}
	// default: content
	return `<!--
  Slide: ${t}
-->
<script>
	import ContentPage from '$lib/templates/ContentPage.svelte';
	import ViewSource from '$lib/components/ViewSource.svelte';
	import source from './+page.svelte?raw';

	const path = '${pathLit}';
</script>

<ContentPage title="${safe}">
	<p>Content goes here.</p>
</ContentPage>

<ViewSource {source} {path} />
`;
}

/** Normalize template name; unknown → content. */
export function normalizeTemplate(t: string | undefined | null): PageTemplate {
	return t === 'title' ? 'title' : 'content';
}
