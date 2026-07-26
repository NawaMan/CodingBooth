// Server-side source patcher for the ADJUST-mode "Save" feature.
//
// ADJUST edits live only in the browser (see adjustMode.ts / adjustChanges.ts) —
// the author drags a <Block>, and the only way those coordinates ever reach the
// slide's Svelte source is a copy → paste. "Save" closes that loop IN DEV ONLY:
// the browser POSTs the changed tags to a Vite dev endpoint (devSavePlugin.ts)
// which calls this module to rewrite the `.svelte` file on disk, then HMR
// reloads the slide.
//
// The hard part is matching. The registry's `oldTag` is a RE-SERIALIZATION of a
// Block's props (canonical `<Block name=".." x={..} …>`), not the literal source
// bytes — so a whole-line string replace misses any tag written multi-line, with
// reordered/extra attributes, or with expressions. So we DON'T match whole lines.
// Instead we locate the target opening tag (by `name`, falling back to its old
// x/y/width/height tuple) and rewrite ONLY the numeric geometry attributes in
// place — x/y/width/height, plus `z` when the tag carries one or the new z is
// non-zero — preserving indentation, multi-line layout, and every other prop.
// Anything we can't confidently place is returned as `unmatched` for the author
// to paste by hand — never guessed.
//
// Pure and browser-free so it unit-tests without a dev server (tests/adjustPatch.test.ts).

export interface Geometry {
	x: number;
	y: number;
	width: number;
	height: number;
	/** Persistent stacking order (Block `z`). Optional: only rewritten in place
	    when the tag already carries a `z={…}`, or inserted when non-zero — so a
	    plain x/y drag never litters the source with `z={0}`. */
	z?: number;
}

export interface LayoutChange {
	/** Component/tag name — 'Block', 'ImageBlock', 'Curve', … */
	kind: string;
	/** The tag's `name=".."`, when it has one (the strongest match signal). */
	name?: string;
	// A change is applied one of two ways:
	//
	//   1. GEOMETRY (Blocks): give `before`/`after` and only the x/y/width/height
	//      numbers are rewritten in place — robust to attribute reordering,
	//      multi-line tags, and extra props.
	//
	//   2. LITERAL (Draw shapes): give the whole `oldTag`/`newTag` opening tag and
	//      the first exact occurrence of oldTag is swapped for newTag. Draw emits
	//      its shapes' source tags in the same canonical order it serializes here,
	//      so the old tag matches the source line byte-for-byte. Curves/Lines/Arcs
	//      have no box geometry, so this is the only way to save them.
	//
	//   3. INSERT (FREEZE): give `insert` — markup that is not in the file at all yet
	//      and has to be ADDED. This is the one mode with no target tag to find, and
	//      it exists for exactly one caller: freezing an ANNOTATE stroke into a Draw
	//      shape (see annotate/freezeCore.ts). Everything else here rewrites what is
	//      already written; this writes something new.
	//
	// A literal change (oldTag present) takes precedence, then an insert; otherwise
	// geometry is used.
	/** Geometry as the tag was mounted (matches the current source). */
	before?: Geometry;
	/** Geometry to write. */
	after?: Geometry;
	/** Whole opening tag as mounted — the literal string to find in source. */
	oldTag?: string;
	/** Whole opening tag to write in its place. */
	newTag?: string;
	/** NEW markup to add to the slide — one shape tag per line, unindented. Placed
	    inside the slide's existing <Draw> when it has exactly one, or in a fresh
	    top-level <Draw> appended to the markup when it has none. */
	insert?: string;
	/** Component names from `$lib/draw` the inserted markup needs. Merged into the
	    slide's existing draw import, or added as a new one — without this, an
	    inserted <Polyline> is a build error rather than a shape. */
	insertImports?: string[];
}

/** WHY a change couldn't be placed — so the UI can tell the author the true
    story instead of one blanket explanation:
    - 'not-found':  no tag in the source matches at all. For a literal (Draw
      shape) change that means the canonical serialized tag isn't in the file —
      geometry written as EXPRESSIONS (`from={curve.from}`), a reformatted /
      multi-line tag, or a tag living in another file.
    - 'ambiguous':  several tags tie for the match (a code sample of the tag in
      the same file, say) and it is never guessed at. */
export type UnmatchReason = 'not-found' | 'ambiguous';

export interface PatchResult {
	/** The rewritten source (unchanged if nothing matched). */
	source: string;
	/** Changes that were located and applied. */
	patched: LayoutChange[];
	/** Changes no tag could be confidently matched to, each carrying WHY. */
	unmatched: Array<LayoutChange & { reason: UnmatchReason }>;
}

const GEOM_ATTRS = ['x', 'y', 'width', 'height'] as const;

interface TagSpan {
	/** Index of the leading `<` in the source. */
	start: number;
	/** Index just past the closing `>`. */
	end: number;
	/** The full opening-tag text, `<Kind …>` or `<Kind … />`. */
	text: string;
}

/** True when `ch` can't be part of a component tag name right after `<Kind`. */
function isTagBoundary(ch: string | undefined): boolean {
	return ch === undefined || /\s/.test(ch) || ch === '>' || ch === '/';
}

// Walk every `<Kind …>` opening tag in `source`. We can't lean on a regex for the
// whole tag because attribute values contain `{ … }` (which may hold `>`), so we
// scan character by character tracking quote + brace state and stop at the first
// top-level `>`.
function findOpeningTags(source: string, kind: string): TagSpan[] {
	const spans: TagSpan[] = [];
	const needle = `<${kind}`;
	let from = 0;
	for (;;) {
		const start = source.indexOf(needle, from);
		if (start === -1) break;
		// Reject `<Blockish` when scanning for `<Block`: the char after the name
		// must end the identifier.
		if (!isTagBoundary(source[start + needle.length])) {
			from = start + needle.length;
			continue;
		}
		let i = start + needle.length;
		let brace = 0;
		let quote: string | null = null;
		let end = -1;
		for (; i < source.length; i++) {
			const ch = source[i];
			if (quote) {
				if (ch === quote) quote = null;
				continue;
			}
			if (ch === '"' || ch === "'") quote = ch;
			else if (ch === '{') brace++;
			else if (ch === '}') brace = Math.max(0, brace - 1);
			else if (ch === '>' && brace === 0) {
				end = i + 1;
				break;
			}
		}
		if (end === -1) break; // unterminated tag — give up on this file
		spans.push({ start, end, text: source.slice(start, end) });
		from = end;
	}
	return spans;
}

/** Read `attr={<number>}` out of a tag's text; null when absent or non-numeric. */
function readGeomAttr(tagText: string, attr: string): number | null {
	const m = tagText.match(new RegExp(`\\b${attr}=\\{([^}]*)\\}`));
	if (!m) return null;
	const n = Number(m[1].trim());
	return Number.isFinite(n) ? n : null;
}

/** Does a tag carry `name="<name>"` (or single-quoted)? */
function hasName(tagText: string, name: string): boolean {
	return new RegExp(`\\bname=(["'])${escapeRegExp(name)}\\1`).test(tagText);
}

function escapeRegExp(s: string): string {
	return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function geomMatches(tagText: string, g: Geometry | undefined): boolean {
	if (!g) return false;
	return GEOM_ATTRS.every((a) => readGeomAttr(tagText, a) === Math.round(g[a]));
}

/** Pick the tag this change targets, or the reason none is a confident match. */
function chooseTarget(spans: TagSpan[], change: LayoutChange): TagSpan | UnmatchReason {
	let pool = spans;
	if (change.name) {
		const named = pool.filter((s) => hasName(s.text, change.name!));
		// A name should be unique on a slide; if exactly one carries it, take it
		// even if its geometry drifted. If NONE carries it, the tag isn't in this
		// file (likely an imported child component) — report unmatched rather than
		// risk patching an unrelated tag that merely shares the geometry. With
		// several, narrow by geometry to disambiguate.
		if (named.length === 1) return named[0];
		if (named.length === 0) return 'not-found';
		pool = named;
	}
	const byGeom = pool.filter((s) => geomMatches(s.text, change.before));
	if (byGeom.length === 1) return byGeom[0];
	// Zero candidates → the tag just isn't here; several → a genuine twin tie.
	return byGeom.length === 0 ? 'not-found' : 'ambiguous';
}

/** Rewrite the four geometry attributes in a single opening tag's text, plus the
    optional `z` (stacking order) — but z, unlike x/y/width/height, is never
    inserted just to write a 0: a Block defaults to `z-index: auto`, so a tag with
    no z is CORRECT at z 0 and must stay clean. z is therefore written only when
    the tag already carries a `z={…}` (rewrite it — including down to 0) or the new
    value is non-zero (insert it). */
function applyGeometry(tagText: string, after: Geometry): string {
	let out = tagText;
	for (const attr of GEOM_ATTRS) {
		const val = Math.round(after[attr]);
		const re = new RegExp(`(\\b${attr}=\\{)[^}]*(\\})`);
		if (re.test(out)) {
			out = out.replace(re, `$1${val}$2`);
		} else {
			// Attr missing on the tag — insert it just before the tag close.
			const insert = ` ${attr}={${val}}`;
			out = out.replace(/\s*\/?>$/, (close) => insert + close);
		}
	}
	if (after.z != null) {
		const val = Math.round(after.z);
		const zre = /(\bz=\{)[^}]*(\})/;
		if (zre.test(out)) {
			out = out.replace(zre, `$1${val}$2`);
		} else if (val !== 0) {
			out = out.replace(/\s*\/?>$/, (close) => ` z={${val}}` + close);
		}
	}
	return out;
}

// --- INSERT: adding markup that isn't there yet (FREEZE) ---------------------
//
// Every other mode in this file finds a tag and rewrites it. Freezing a stroke has
// no tag to find: the shape is new. So the question changes from "which tag is
// this?" to "where does a new shape go?", and there are exactly two answers — into
// the <Draw> the slide already has, or into one we append. Both are conservative:
// several <Draw>s is a genuine ambiguity and is never guessed at, exactly as a twin
// tag tie isn't.

/** The whitespace at the start of the line `at` falls on. */
function indentAt(source: string, at: number): string {
	const lineStart = source.lastIndexOf('\n', at - 1) + 1;
	const m = /^[ \t]*/.exec(source.slice(lineStart, at));
	return m ? m[0] : '';
}

/** Every `</Draw>` in the source, as indices. */
function drawCloseTags(source: string): number[] {
	const out: number[] = [];
	for (let at = source.indexOf('</Draw>'); at !== -1; at = source.indexOf('</Draw>', at + 1)) {
		out.push(at);
	}
	return out;
}

/** Where a fresh top-level <Draw> block belongs: after the markup, but BEFORE the
    `<style>` block if the slide has one — a `<Draw>` written after `</style>` still
    compiles, but it reads as an accident and it is not where an author would put it.
    Only a `<style` at column 0 counts, so a `<style>` mentioned inside a code sample
    can't drag the insert into the middle of a paragraph. */
function markupEnd(source: string): number {
	const m = /^<style\b/m.exec(source);
	return m ? m.index : source.length;
}

/** Merge the names an inserted shape needs into the slide's `$lib/draw` import,
    adding the import (and, if need be, the whole `<script>` block) when it has none.
    Names already imported are left alone, and the merged list is sorted so repeated
    freezes converge on one stable line rather than churning the import on every save. */
function ensureDrawImports(source: string, names: string[]): string {
	const want = names.filter((n) => n);
	if (want.length === 0) return source;

	const existing = /import\s*\{([^}]*)\}\s*from\s*(['"])\$lib\/draw\2\s*;?/.exec(source);
	if (existing) {
		const have = existing[1]
			.split(',')
			.map((s) => s.trim())
			.filter(Boolean);
		const missing = want.filter((n) => !have.includes(n));
		if (missing.length === 0) return source;
		const merged = [...have, ...missing].sort().join(', ');
		const line = `import { ${merged} } from '$lib/draw';`;
		return source.slice(0, existing.index) + line + source.slice(existing.index + existing[0].length);
	}

	const line = `import { ${[...want].sort().join(', ')} } from '$lib/draw';`;
	const scriptClose = source.indexOf('</script>');
	if (scriptClose !== -1) {
		// Last line inside the script block, indented like whatever is already there.
		const indent = indentAt(source, scriptClose) || '\t';
		return source.slice(0, scriptClose) + `${indent}${line}\n` + source.slice(scriptClose);
	}
	// No script block at all (a pure-markup slide) — give it one.
	return `<script lang="ts">\n\t${line}\n</script>\n\n` + source;
}

/** Place new shape markup. Returns the rewritten source, or WHY it couldn't be
    placed — 'ambiguous' when the slide has more than one <Draw> and picking is a
    coin flip. Nothing else here can fail: a slide with no <Draw> gets one.

    Tagged rather than returning `string | UnmatchReason`: both arms would be strings,
    and a source file that happened to equal "not-found" would read as a failure. */
type InsertResult = { ok: true; source: string } | { ok: false; reason: UnmatchReason };

function applyInsert(source: string, change: LayoutChange): InsertResult {
	const tags = (change.insert ?? '')
		.split('\n')
		.map((t) => t.trim())
		.filter(Boolean);
	if (tags.length === 0) return { ok: false, reason: 'not-found' }; // nothing to add

	const withImports = ensureDrawImports(source, change.insertImports ?? []);
	const closes = drawCloseTags(withImports);
	if (closes.length > 1) return { ok: false, reason: 'ambiguous' };

	if (closes.length === 1) {
		const at = closes[0];
		const outer = indentAt(withImports, at);
		const inner = outer + '\t';
		const block = tags.map((t) => `${inner}${t}\n`).join('') + outer;
		// Splice from the start of the `</Draw>` line, so the close tag keeps its own
		// indentation instead of being pushed along by ours.
		const lineStart = withImports.lastIndexOf('\n', at - 1) + 1;
		return { ok: true, source: withImports.slice(0, lineStart) + block + withImports.slice(at) };
	}

	const end = markupEnd(withImports);
	const before = withImports.slice(0, end).replace(/\s*$/, '');
	const after = withImports.slice(end);
	const block =
		'\n\n<!-- Frozen from an ANNOTATE stroke. -->\n<Draw>\n' +
		tags.map((t) => `\t${t}\n`).join('') +
		'</Draw>\n';
	return { ok: true, source: before + block + (after ? '\n' + after : '') };
}

/**
 * Apply ADJUST geometry changes to a slide's Svelte source. Each change is
 * matched to one opening tag and its x/y/width/height rewritten in place; the
 * rest of the tag (and file) is untouched. Changes are applied sequentially so
 * a just-patched tag can't be re-matched by a later change.
 */
export function patchSlideSource(source: string, changes: LayoutChange[]): PatchResult {
	let current = source;
	const patched: LayoutChange[] = [];
	const unmatched: PatchResult['unmatched'] = [];

	for (const change of changes) {
		// Literal whole-tag replacement (Draw shapes): find the exact old tag and
		// swap it. Draw authors its shape tags in the order it serializes, so the
		// old tag is a byte-for-byte source match.
		if (change.oldTag != null && change.newTag != null) {
			if (change.oldTag === change.newTag) {
				patched.push(change); // not actually dirty — nothing to do
				continue;
			}
			const at = current.indexOf(change.oldTag);
			if (at === -1) {
				// The canonical tag isn't in the file — geometry via expressions, a
				// reformatted tag, or a tag in another file. Nothing to rewrite.
				unmatched.push({ ...change, reason: 'not-found' });
				continue;
			}
			current = current.slice(0, at) + change.newTag + current.slice(at + change.oldTag.length);
			patched.push(change);
			continue;
		}

		// New markup (FREEZE): nothing to find, something to add.
		if (change.insert != null) {
			const result = applyInsert(current, change);
			if (!result.ok) {
				unmatched.push({ ...change, reason: result.reason });
				continue;
			}
			current = result.source;
			patched.push(change);
			continue;
		}

		// Geometry attribute patch (Blocks).
		if (!change.after) {
			unmatched.push({ ...change, reason: 'not-found' });
			continue;
		}
		const spans = findOpeningTags(current, change.kind);
		const target = chooseTarget(spans, change);
		if (typeof target === 'string') {
			unmatched.push({ ...change, reason: target });
			continue;
		}
		const newText = applyGeometry(target.text, change.after);
		if (newText === target.text) {
			// Nothing to write (already at the target geometry) — count as done.
			patched.push(change);
			continue;
		}
		current = current.slice(0, target.start) + newText + current.slice(target.end);
		patched.push(change);
	}

	return { source: current, patched, unmatched };
}
