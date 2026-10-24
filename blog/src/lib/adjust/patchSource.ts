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
	//      the first exact occurrence of oldTag is swapped for newTag. Point shapes
	//      (Line/Curve/Arc/Path/Polyline) have no box geometry, so this is the only
	//      way to save them.
	//      A byte compare is fragile, and BOX shapes routinely lose it: boxTag()
	//      emits the cosmetic attrs BEFORE x/y/width/height, while a hand-written
	//      <Rect>/<Ellipse> almost always leads with the geometry the way a Block
	//      does. So Rect/Ellipse send `before`/`after` as WELL as the tags, and a
	//      literal miss falls through to mode 1 rather than reporting not-found.
	//      A shape with NO geometry to fall back on (a point shape, or a <Sprite>
	//      whose editable state is a stops array) falls through to mode 4 instead.
	//
	//   3. INSERT (FREEZE): give `insert` — markup that is not in the file at all yet
	//      and has to be ADDED. This is the one mode with no target tag to find, and
	//      it exists for exactly one caller: freezing an ANNOTATE stroke into a Draw
	//      shape (see annotate/freezeCore.ts). Everything else here rewrites what is
	//      already written; this writes something new.
	//
	//   4. ATTRIBUTE (Sprites, and any shape a literal miss leaves nowhere to go):
	//      rewrite just the attributes whose values changed — in the tag, or in the
	//      `const` the tag references by name — leaving the author's line breaks and
	//      every other prop alone. Derived from `oldTag`/`newTag`; no extra payload.
	//
	//   5. REMOVE (Delete on a selected Block): give `remove` plus `before` and the
	//      WHOLE element — opening tag, children, matching closing tag — is cut out,
	//      along with the lines it leaves empty. The target is chosen exactly as a
	//      geometry change chooses it, so a delete is refused wherever a drag would be.
	//
	//   6. PASTE (Ctrl+V on a copied Block): give `paste` plus `before` and the whole
	//      matched element is DUPLICATED right after itself — its opening tag carrying
	//      the paste's geometry and name, its children copied byte for byte. Found
	//      exactly as REMOVE finds it.
	//
	// A paste goes first, then a remove; then a literal change (oldTag present),
	// then an insert; otherwise geometry is used.
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
	/** Delete the matched element outright (mode 5). Needs `before` (and `name`
	    when it has one) to find it; `after` is ignored. */
	remove?: boolean;
	/** Duplicate the matched element (mode 6). `name` is the copy's own name
	    (omitted for an unnamed Block); `after` its box. Needs `before` (and
	    `name` when the original has one) to find the original. */
	paste?: { name?: string; after: Geometry };
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

// --- ATTRIBUTE: rewriting ONE prop's value (Sprite `stops`, `path`, …) --------
//
// The literal swap above needs the whole opening tag to match byte-for-byte, and
// a <Sprite> essentially never does: its editable state is a `stops` ARRAY, which
// authors write across several lines, or hoist into a `const` and pass by name.
// Geometry mode can't help either — five stops with pct/ease are not one box.
//
// So: find the tag, then rewrite only the attributes that actually changed,
// leaving the author's layout and every other prop alone. Two shapes of target:
//
//   DIRECT    <Sprite name="x" stops={[ … ]}>   → rewrite the value in the tag
//   INDIRECT  <Sprite name="x" stops={theStops}> → rewrite `const theStops = […]`
//
// Identification is the same principle geometry mode uses with `before`: the tag
// only matches if it CURRENTLY carries the pre-edit value, whitespace ignored.
// That is what lets a slide keep a <Sprite> code SAMPLE next to the real thing —
// the sample's stops are abridged, so it can't impersonate the tag being saved.

interface ParsedAttr {
	name: string;
	/** Raw value text WITH its delimiters (`{…}` / `"…"`), or null for a bare
	    boolean attribute like `lock`. */
	raw: string | null;
	/** Offsets of `raw` within the tag text. */
	start: number;
	end: number;
}

/** Attributes of one opening tag, in source order. Hand-rolled rather than
    regexed because a value can hold braces, quotes and `>` (`stops={[{…}]}`). */
function parseAttrs(tagText: string): ParsedAttr[] {
	const out: ParsedAttr[] = [];
	// Skip `<Kind`; the name runs to the first boundary char.
	let i = 1;
	while (i < tagText.length && !isTagBoundary(tagText[i])) i++;
	for (; i < tagText.length; ) {
		const ch = tagText[i];
		if (/\s/.test(ch)) {
			i++;
			continue;
		}
		if (ch === '>' || ch === '/') break;
		const nameStart = i;
		while (i < tagText.length && /[\w:$-]/.test(tagText[i])) i++;
		if (i === nameStart) {
			i++; // not an identifier (a spread, say) — step over it
			continue;
		}
		const name = tagText.slice(nameStart, i);
		while (i < tagText.length && /\s/.test(tagText[i])) i++;
		if (tagText[i] !== '=') {
			out.push({ name, raw: null, start: nameStart, end: i });
			continue;
		}
		i++; // past '='
		while (i < tagText.length && /\s/.test(tagText[i])) i++;
		const valStart = i;
		const open = tagText[i];
		if (open === '"' || open === "'") {
			i++;
			while (i < tagText.length && tagText[i] !== open) i++;
			i++; // past the closer
		} else if (open === '{') {
			let depth = 0;
			let quote: string | null = null;
			for (; i < tagText.length; i++) {
				const c = tagText[i];
				if (quote) {
					if (c === quote) quote = null;
					continue;
				}
				if (c === '"' || c === "'" || c === '`') quote = c;
				else if (c === '{' || c === '[') depth++;
				else if (c === '}' || c === ']') {
					depth--;
					if (depth === 0) {
						i++;
						break;
					}
				}
			}
		} else {
			while (i < tagText.length && !/[\s>]/.test(tagText[i])) i++;
		}
		out.push({ name, raw: tagText.slice(valStart, i), start: valStart, end: i });
	}
	return out;
}

const attrMap = (tagText: string) => new Map(parseAttrs(tagText).map((a) => [a.name, a]));

/** Compare attribute values ignoring ALL whitespace AND quote style — the
    difference between a stops array written on one line and the same array
    written across six is not a difference, and neither is `ease: 'ease-in'`
    versus the `ease: "ease-in"` the serializer emits. (Whitespace folding also
    equates `"50% 50%"` with `"50%50%"`; that only ever makes two already-
    near-identical tags look identical, never the reverse.) */
const norm = (s: string) => s.replace(/\s+/g, '').replace(/'/g, '"');

/** Top-level `key: value` pairs of an object literal (`{ pct: 0, x: 80 }`), or
    null when the text isn't one. */
function objectPairs(text: string): Map<string, string> | null {
	const t = text.trim();
	if (t[0] !== '{' || t[t.length - 1] !== '}') return null;
	const out = new Map<string, string>();
	for (const part of splitTopLevel(t.slice(1, -1))) {
		const at = part.indexOf(':');
		if (at === -1) return null;
		out.set(part.slice(0, at).trim(), part.slice(at + 1).trim());
	}
	return out;
}

/** Does one element of the source array still hold what the browser mounted?

    Identical text (modulo whitespace and quote style) is the happy path. Failing
    that, compare STRUCTURALLY — every key the serializer wrote must be present
    and equal in the source. This exists because the serializer omits a property
    sitting at its default (`rot: 0`, an empty ease) while an author routinely
    writes it out: sprite-multi.html's star stop is `{ …, rot: 0, ease: 'ease-in-out' }`
    in the file and `{ …, ease: "ease-in-out" }` on the wire. Demanding identical
    text refuses that save for no real reason.

    Extra keys in the SOURCE are therefore tolerated. The one drift that hides
    behind that is someone ADDING a key to the file while ADJUST sat open with
    unsaved edits — the same race the feature already runs; a key that merely
    CHANGED is still caught. */
function elementMatches(sourceEl: string, mountedEl: string): boolean {
	if (norm(sourceEl) === norm(mountedEl)) return true;
	const src = objectPairs(sourceEl);
	const mounted = objectPairs(mountedEl);
	if (!src || !mounted) return false;
	for (const [k, v] of mounted) {
		const got = src.get(k);
		if (got == null || norm(got) !== norm(v)) return false;
	}
	return true;
}

/** The same question for a whole attribute value — element by element, so a list
    only matches when it is the same length and every entry still agrees. */
function valueMatches(sourceRaw: string, mountedRaw: string): boolean {
	if (norm(sourceRaw) === norm(mountedRaw)) return true;
	const strip = (s: string) => {
		const t = s.trim();
		return (t[0] === '[' || t[0] === '{') && t.length > 1 ? t.slice(1, -1) : t;
	};
	const src = splitTopLevel(strip(sourceRaw));
	const mounted = splitTopLevel(strip(mountedRaw));
	if (src.length === 0 || src.length !== mounted.length) return false;
	return src.every((el, i) => elementMatches(el, mounted[i]));
}

/** Write the replacement in the quote style the replaced text used. Without this
    every save flips a slide's `'ease-in'` to `"ease-in"`, so a drag that moved one
    stop shows up in the diff as a change to all of them. Skipped unless the swap
    is unambiguous — the new text must have no apostrophe of its own to mangle. */
function matchQuoteStyle(next: string, previous: string): string {
	if (!next.includes('"') || next.includes("'")) return next;
	if (!previous.includes("'") || previous.includes('"')) return next;
	return next.replace(/"/g, "'");
}

/** Attribute names whose value differs between the mounted tag and the new one. */
function changedAttrNames(oldTag: string, newTag: string): string[] {
	const before = attrMap(oldTag);
	const after = attrMap(newTag);
	const names = new Set([...before.keys(), ...after.keys()]);
	return [...names].filter((n) => {
		const a = before.get(n)?.raw ?? null;
		const b = after.get(n)?.raw ?? null;
		if (a === null || b === null) return a !== b;
		return norm(a) !== norm(b);
	});
}

/** `{someName}` → `someName`, for a value that is a bare identifier reference and
    nothing else. Anything with an operator, call or literal in it returns null —
    `stops={makeStops(3)}` must NOT be flattened into an array behind the author's
    back, so it refuses rather than guessing. */
function identifierOf(raw: string | null): string | null {
	if (!raw) return null;
	const m = /^\{\s*([A-Za-z_$][\w$]*)\s*\}$/.exec(raw);
	return m ? m[1] : null;
}

/** The initializer of a `const <id> = …` in the source, as offsets. Only a `const`
    declared in THIS file counts: an import or a `let` that something else may
    reassign is not ours to rewrite. Returns 'ambiguous' when the name is declared
    or referenced more than once — rewriting a shared array would silently move a
    second sprite too. */
function findConstInit(source: string, id: string): { start: number; end: number } | UnmatchReason {
	const decl = new RegExp(`\\bconst\\s+${escapeRegExp(id)}\\s*=\\s*`, 'g');
	const hits = [...source.matchAll(decl)];
	if (hits.length === 0) return 'not-found';
	if (hits.length > 1) return 'ambiguous';
	// Every other mention must be the single tag we are patching; more than that
	// and the binding is shared.
	const uses = [...source.matchAll(new RegExp(`\\b${escapeRegExp(id)}\\b`, 'g'))];
	if (uses.length > 2) return 'ambiguous';

	const start = hits[0].index! + hits[0][0].length;
	const open = source[start];
	if (open !== '[' && open !== '{') return 'not-found'; // not an array/object literal
	let depth = 0;
	let quote: string | null = null;
	for (let i = start; i < source.length; i++) {
		const c = source[i];
		if (quote) {
			if (c === quote) quote = null;
			continue;
		}
		if (c === '"' || c === "'" || c === '`') quote = c;
		else if (c === '[' || c === '{') depth++;
		else if (c === ']' || c === '}') {
			depth--;
			if (depth === 0) return { start, end: i + 1 };
		}
	}
	return 'not-found'; // unterminated
}

/** Split `[a, b, c]` (or `{…}`) into its top-level elements, ignoring commas
    nested inside elements or strings. */
function splitTopLevel(inner: string): string[] {
	const out: string[] = [];
	let depth = 0;
	let quote: string | null = null;
	let from = 0;
	for (let i = 0; i < inner.length; i++) {
		const c = inner[i];
		if (quote) {
			if (c === quote) quote = null;
			continue;
		}
		if (c === '"' || c === "'" || c === '`') quote = c;
		else if (c === '[' || c === '{' || c === '(') depth++;
		else if (c === ']' || c === '}' || c === ')') depth--;
		else if (c === ',' && depth === 0) {
			out.push(inner.slice(from, i).trim());
			from = i + 1;
		}
	}
	const last = inner.slice(from).trim();
	if (last) out.push(last);
	return out;
}

/** Re-emit a new array/object value in the shape the old one was written in. A
    five-stop array is authored one stop per line; collapsing it onto one
    400-column line is a diff nobody wants to read, so when the value being
    replaced spanned lines the replacement does too, at the same indent.

    Elements that did not actually change are copied from the OLD text verbatim,
    so dragging one stop produces a one-line diff instead of rewriting all five
    with the serializer's spacing. That matters here more than most places: these
    slides display their own source. */
function reflow(next: string, previous: string, indent: string): string {
	if (!previous.includes('\n')) return next;
	const open = next[0];
	const close = next[next.length - 1];
	if ((open !== '[' && open !== '{') || next.length < 2) return next;
	const parts = splitTopLevel(next.slice(1, -1));
	if (parts.length < 2) return next;
	const was = splitTopLevel(previous.slice(1, -1));
	// Only a same-length list can be paired up element-for-element; adding or
	// removing a keyframe re-emits the whole array, which is honest.
	// elementMatches, not raw equality: a stop the author wrote with an explicit
	// `rot: 0` is unchanged even though the serializer drops that key, and must
	// keep its own text rather than being rewritten without it.
	const merged =
		was.length === parts.length ? parts.map((p, i) => (elementMatches(was[i], p) ? was[i] : p)) : parts;
	const inner = indent + '\t';
	return `${open}\n${merged.map((p) => inner + p).join(',\n')}\n${indent}${close}`;
}

type AttrResult = { ok: true; source: string } | { ok: false; reason: UnmatchReason };

/** Rewrite the changed attributes of `change` in `source`. See the block comment
    at the top of this section for how the target tag is identified. */
function applyAttrChange(source: string, change: LayoutChange): AttrResult {
	const oldTag = change.oldTag;
	const newTag = change.newTag;
	if (oldTag == null || newTag == null) return { ok: false, reason: 'not-found' };
	const changed = changedAttrNames(oldTag, newTag);
	if (changed.length === 0) return { ok: false, reason: 'not-found' };

	const oldAttrs = attrMap(oldTag);
	const newAttrs = attrMap(newTag);
	// Removals (old only) and bare boolean flips are structural — refuse.
	if (changed.some((n) => !newAttrs.get(n)?.raw)) {
		return { ok: false, reason: 'not-found' };
	}
	// Rewrites need a value on both sides; pure insertions (e.g. adding `widths=`
	// to a bare <Columns>) are allowed and handled below.
	const rewrites = changed.filter((n) => oldAttrs.get(n)?.raw != null);
	const inserts = changed.filter((n) => oldAttrs.get(n)?.raw == null);

	let pool = findOpeningTags(source, change.kind);
	if (change.name) pool = pool.filter((s) => hasName(s.text, change.name!));
	if (pool.length === 0) return { ok: false, reason: 'not-found' };

	const carries = (tagText: string, resolve: (raw: string | null) => string | null) => {
		const attrs = attrMap(tagText);
		for (const n of rewrites) {
			const got = resolve(attrs.get(n)?.raw ?? null);
			if (got == null || !valueMatches(got, oldAttrs.get(n)!.raw!)) return false;
		}
		// An insert matches only when the source tag does NOT already carry the attr
		// (otherwise we would be inventing a second widths=).
		for (const n of inserts) {
			if (attrs.get(n)?.raw != null) return false;
		}
		return true;
	};

	// DIRECT — the tag itself carries the pre-edit value (or lacks the insert attrs).
	const direct = pool.filter((s) => carries(s.text, (raw) => raw));
	if (direct.length > 1) return { ok: false, reason: 'ambiguous' };
	if (direct.length === 1) {
		const span = direct[0];
		let text = span.text;
		// Right to left, so an earlier rewrite can't shift a later offset.
		for (const attr of parseAttrs(span.text)
			.filter((a) => rewrites.includes(a.name))
			.sort((a, b) => b.start - a.start)) {
			const next = newAttrs.get(attr.name)!.raw!;
			// Only a `{…}` expression is reflowed; a quoted value is written as-is.
			const written =
				next[0] === '{'
					? `{${reflow(matchQuoteStyle(next.slice(1, -1), attr.raw!.slice(1, -1)), attr.raw!.slice(1, -1), indentAt(source, span.start))}}`
					: next;
			text = text.slice(0, attr.start) + written + text.slice(attr.end);
		}
		// Pure inserts (Columns ADJUST SAVE adding widths=): park them just before
		// the closing `>` / `/>`, after a single space.
		if (inserts.length) {
			const selfClose = /\/>\s*$/.test(text);
			const cut = selfClose ? text.lastIndexOf('/>') : text.lastIndexOf('>');
			if (cut === -1) return { ok: false, reason: 'not-found' };
			const added = inserts.map((n) => ` ${n}=${newAttrs.get(n)!.raw!}`).join('');
			text = text.slice(0, cut) + added + text.slice(cut);
		}
		return { ok: true, source: source.slice(0, span.start) + text + source.slice(span.end) };
	}

	// INDIRECT — the value is a `const` the tag references by name. Only one
	// changed attr is supported here: two hoisted arrays edited in one gesture is
	// not a case the editors produce, and guessing at it is how you corrupt a file.
	if (changed.length !== 1) return { ok: false, reason: 'not-found' };
	const attrName = changed[0];
	const consts = new Map<TagSpan, { id: string; at: { start: number; end: number } }>();
	for (const span of pool) {
		const id = identifierOf(attrMap(span.text).get(attrName)?.raw ?? null);
		if (!id) continue;
		const at = findConstInit(source, id);
		if (typeof at === 'string') continue;
		if (!valueMatches(source.slice(at.start, at.end), oldAttrs.get(attrName)!.raw!.slice(1, -1))) {
			continue;
		}
		consts.set(span, { id, at });
	}
	if (consts.size > 1) return { ok: false, reason: 'ambiguous' };
	if (consts.size === 0) {
		// Distinguish "the binding is shared / not a const" from "no such tag", so
		// the author is told which one it is.
		for (const span of pool) {
			const id = identifierOf(attrMap(span.text).get(attrName)?.raw ?? null);
			if (id && findConstInit(source, id) === 'ambiguous') return { ok: false, reason: 'ambiguous' };
		}
		return { ok: false, reason: 'not-found' };
	}
	const [{ at }] = [...consts.values()];
	const previous = source.slice(at.start, at.end);
	const next = matchQuoteStyle(newAttrs.get(attrName)!.raw!.slice(1, -1), previous);
	const inner = reflow(next, previous, indentAt(source, at.start));
	return { ok: true, source: source.slice(0, at.start) + inner + source.slice(at.end) };
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

// --- REMOVE: cutting a whole element out (Delete) -----------------------------
//
// The opening tag is found the way geometry mode finds it; what's new is finding
// where the ELEMENT ends. A self-closing tag ends with itself. Otherwise we walk
// forward counting same-kind opens and closes, so a <Block> nested inside the one
// being deleted can't end it early. No matching close → refuse, never guess.

/** Index just past the element whose opening tag is `open`, or -1 when its
    closing tag can't be found. */
function elementEnd(source: string, kind: string, open: TagSpan): number {
	if (/\/\s*>$/.test(open.text)) return open.end;
	const close = `</${kind}>`;
	let depth = 1;
	let from = open.end;
	const opens = findOpeningTags(source, kind).filter((s) => s.start >= open.end);
	for (;;) {
		const nextClose = source.indexOf(close, from);
		if (nextClose === -1) return -1;
		// Every unclosed same-kind open before this close nests one level deeper.
		for (const s of opens) {
			if (s.start >= from && s.start < nextClose && !/\/\s*>$/.test(s.text)) depth++;
		}
		depth--;
		if (depth === 0) return nextClose + close.length;
		from = nextClose + close.length;
	}
}

/** Cut [start, end) out of `source`. When the element is alone on its lines, the
    whole lines go with it — indentation before, newline after — so a delete leaves
    no blank line behind. Sharing a line with other markup, only the element goes. */
function cutElement(source: string, start: number, end: number): string {
	const lineStart = source.lastIndexOf('\n', start - 1) + 1;
	const aloneBefore = /^[ \t]*$/.test(source.slice(lineStart, start));
	const nl = source.indexOf('\n', end);
	const lineEnd = nl === -1 ? source.length : nl;
	const aloneAfter = /^[ \t]*$/.test(source.slice(end, lineEnd));
	if (aloneBefore && aloneAfter) {
		// Take the trailing newline; at EOF take the preceding one instead.
		if (nl !== -1) return source.slice(0, lineStart) + source.slice(nl + 1);
		return source.slice(0, Math.max(0, lineStart - 1)) + source.slice(lineEnd);
	}
	return source.slice(0, start) + source.slice(end);
}

function applyRemove(source: string, change: LayoutChange): AttrResult {
	const target = chooseTarget(findOpeningTags(source, change.kind), change);
	if (typeof target === 'string') return { ok: false, reason: target };
	const end = elementEnd(source, change.kind, target);
	if (end === -1) return { ok: false, reason: 'not-found' };
	return { ok: true, source: cutElement(source, target.start, end) };
}

// --- PASTE: duplicating a whole element (Copy / Paste) -----------------------
//
// The original is found and bounded exactly as REMOVE does it; the copy is its
// text with the opening tag rewritten — new geometry, new name, and NO `id`, since
// a DOM id must stay unique and the live copy never rendered one either. It lands
// right after the original: on a line of its own when the original had its own
// lines, otherwise straight after it on the same line.

function applyPaste(source: string, change: LayoutChange): AttrResult {
	const paste = change.paste!;
	// A copy's name must be new to the file — a Connector or a later SAVE would
	// otherwise find two Blocks answering to it.
	if (paste.name && new RegExp(`\\bname=(["'])${escapeRegExp(paste.name)}\\1`).test(source)) {
		return { ok: false, reason: 'ambiguous' };
	}
	const target = chooseTarget(findOpeningTags(source, change.kind), change);
	if (typeof target === 'string') return { ok: false, reason: target };
	const end = elementEnd(source, change.kind, target);
	if (end === -1) return { ok: false, reason: 'not-found' };

	let open = applyGeometry(target.text, paste.after);
	open = open.replace(/\s+id=("[^"]*"|'[^']*'|\{[^}]*\})/, '');
	if (paste.name) {
		const named = /(\bname=)(["'])[^"']*\2/;
		open = named.test(open)
			? open.replace(named, `$1$2${paste.name}$2`)
			: open.replace(new RegExp(`^<${escapeRegExp(change.kind)}`), (m) => `${m} name="${paste.name}"`);
	}
	const copy = open + source.slice(target.end, end);

	const lineStart = source.lastIndexOf('\n', target.start - 1) + 1;
	const indent = source.slice(lineStart, target.start);
	const nl = source.indexOf('\n', end);
	const lineEnd = nl === -1 ? source.length : nl;
	const ownLines = /^[ \t]*$/.test(indent) && /^[ \t]*$/.test(source.slice(end, lineEnd));
	if (ownLines) {
		return { ok: true, source: source.slice(0, lineEnd) + '\n' + indent + copy + source.slice(lineEnd) };
	}
	return { ok: true, source: source.slice(0, end) + copy + source.slice(end) };
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
		// Paste: duplicate the whole element.
		if (change.paste) {
			const result = applyPaste(current, change);
			if (!result.ok) {
				unmatched.push({ ...change, reason: result.reason });
				continue;
			}
			current = result.source;
			patched.push(change);
			continue;
		}

		// Delete: cut the whole element out.
		if (change.remove) {
			const result = applyRemove(current, change);
			if (!result.ok) {
				unmatched.push({ ...change, reason: result.reason });
				continue;
			}
			current = result.source;
			patched.push(change);
			continue;
		}

		// Literal whole-tag replacement (Draw shapes): find the exact old tag and
		// swap it. Draw authors its shape tags in the order it serializes, so the
		// old tag is a byte-for-byte source match.
		if (change.oldTag != null && change.newTag != null) {
			if (change.oldTag === change.newTag) {
				patched.push(change); // not actually dirty — nothing to do
				continue;
			}
			const at = current.indexOf(change.oldTag);
			if (at !== -1) {
				current = current.slice(0, at) + change.newTag + current.slice(at + change.oldTag.length);
				patched.push(change);
				continue;
			}
			// The canonical tag isn't in the file. For a BOX shape that is usually
			// not "unpatchable" — just written in a different attribute order than
			// the serializer emits. boxTag() puts the cosmetic attrs BEFORE
			// x/y/width/height, while a hand-written tag almost always leads with
			// the geometry (as a Block does), and a byte compare cannot see past
			// that. Those changes also carry structured geometry, so fall through
			// to the same order-independent attribute rewrite Blocks use, which
			// preserves the author's ordering, spacing, and multi-line layout.
			// Point shapes (Line/Curve/Arc/Path/Polyline) have no box and send no
			// geometry; they fall through to the attribute rewrite instead, which
			// is the only thing that can place a <Sprite> at all (its editable
			// state is a stops ARRAY — see that section).
			if (!change.after) {
				const attrs = applyAttrChange(current, change);
				if (attrs.ok) {
					current = attrs.source;
					patched.push(change);
					continue;
				}
				unmatched.push({ ...change, reason: attrs.reason });
				continue;
			}
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
