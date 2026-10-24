// Pure source surgery for the presenter console's NOTE EDIT: find the one
// `<Note>…</Note>` in a slide's +page.svelte, hand its inner source out for
// editing, and splice an edited version back in.
//
// Why Svelte's own parser and not a text search: a slide that DOCUMENTS notes
// shows `<Note>` as sample code inside a QuickCode string (see
// slides/note-highlight-component.html), and a regex cannot tell that sample from
// the real element. The parser can — a string attribute is not a component — so
// it hands back exactly the elements that render.
//
// The rules mirror ADJUST's patcher (layout/patchSource.ts): never guess. Zero
// notes, several notes, a self-closing note or a file that does not parse come
// back as a refusal with a reason, and so does an edit that would leave the file
// unparsable — a broken slide is worse than an unsaved note.
//
// Runs on the dev server (devSavePlugin) and under vitest; never in the browser,
// since svelte/compiler is not something a slide should ship.

import { parse } from 'svelte/compiler';

export type NoteRefusal = 'none' | 'many' | 'self-closing' | 'unparsable';

export interface NoteRange {
	/** Offset just past the opening tag's `>`. */
	start: number;
	/** Offset of the closing `</Note`. */
	end: number;
}

export type LocateResult = ({ ok: true } & NoteRange) | { ok: false; reason: NoteRefusal };

/** Human wording for each refusal — shown in the console as is. */
export const REFUSAL_TEXT: Record<NoteRefusal | 'conflict' | 'broken', string> = {
	none: 'This slide has no <Note> to edit.',
	many: 'This slide has more than one <Note>; edit it in the source.',
	'self-closing': 'This slide\'s <Note /> is self-closing; give it a body in the source first.',
	unparsable: 'The slide source does not parse right now; fix it in the source first.',
	conflict: 'The slide changed on disk since you opened the editor. Copy your text, CANCEL, and EDIT again.',
	broken: 'That edit would break the slide (unbalanced markup?). Nothing was saved.'
};

type AstNode = { type?: string; name?: string; start?: number; end?: number };

/** Every `<Note>` component in the markup, in document order. */
function findNotes(source: string): AstNode[] | null {
	let ast: unknown;
	try {
		ast = parse(source, { modern: true });
	} catch {
		return null;
	}
	const found: AstNode[] = [];
	const seen = new WeakSet<object>();
	const walk = (v: unknown) => {
		if (!v || typeof v !== 'object' || seen.has(v as object)) return;
		seen.add(v as object);
		if (Array.isArray(v)) {
			v.forEach(walk);
			return;
		}
		const n = v as AstNode & Record<string, unknown>;
		if (n.type === 'Component' && n.name === 'Note') found.push(n);
		for (const [k, child] of Object.entries(n)) {
			// The scripts and styles never hold markup; skip them outright.
			if (k === 'instance' || k === 'module' || k === 'css' || k === 'metadata') continue;
			walk(child);
		}
	};
	walk((ast as { fragment?: unknown }).fragment);
	found.sort((a, b) => (a.start ?? 0) - (b.start ?? 0));
	return found;
}

/** Offset of the `>` that closes the opening tag starting at `from` (a `<`), skipping
    quotes and `{…}` expressions so an attribute like `x={a > b}` cannot fool it. */
function openTagEnd(source: string, from: number): number {
	let depth = 0;
	let quote: string | null = null;
	for (let i = from + 1; i < source.length; i++) {
		const c = source[i];
		if (quote) {
			if (c === quote) quote = null;
		} else if (c === '"' || c === "'" || c === '`') {
			if (depth > 0 || c !== '`') quote = c;
		} else if (c === '{') depth++;
		else if (c === '}') depth = Math.max(0, depth - 1);
		else if (c === '>' && depth === 0) return i;
	}
	return -1;
}

/** Where the one editable note's inner source sits, or why there isn't one. */
export function locateNote(source: string): LocateResult {
	const notes = findNotes(source);
	if (!notes) return { ok: false, reason: 'unparsable' };
	if (notes.length === 0) return { ok: false, reason: 'none' };
	if (notes.length > 1) return { ok: false, reason: 'many' };
	const n = notes[0];
	const open = openTagEnd(source, n.start ?? 0);
	if (open < 0) return { ok: false, reason: 'unparsable' };
	if (source[open - 1] === '/') return { ok: false, reason: 'self-closing' };
	const close = source.lastIndexOf('</Note', n.end ?? source.length);
	if (close < open) return { ok: false, reason: 'unparsable' };
	return { ok: true, start: open + 1, end: close };
}

/** The inner source split into the part the speaker edits and the frame around it:
    the leading/trailing whitespace and the common indentation the file uses. */
export interface NoteBody {
	lead: string;
	trail: string;
	indent: string;
	text: string;
}

export function toEditable(inner: string): NoteBody {
	const lead = /^\s*\n/.exec(inner)?.[0] ?? '';
	const afterLead = inner.slice(lead.length);
	const trail = /\n[ \t]*$/.exec(afterLead)?.[0] ?? '';
	const body = trail ? afterLead.slice(0, -trail.length) : afterLead;
	const lines = body.split('\n');
	const indents = lines
		.filter((l) => l.trim() !== '')
		.map((l) => /^[ \t]*/.exec(l)![0]);
	// The longest prefix every non-blank line shares — tabs and spaces kept literal.
	let indent = indents[0] ?? '';
	for (const s of indents) {
		let i = 0;
		while (i < indent.length && i < s.length && indent[i] === s[i]) i++;
		indent = indent.slice(0, i);
	}
	const text = lines.map((l) => (l.startsWith(indent) ? l.slice(indent.length) : l.trimStart())).join('\n');
	return { lead, trail, indent, text };
}

/** Re-wrap edited text in the original frame: re-indent every non-blank line. */
export function fromEditable(text: string, frame: Omit<NoteBody, 'text'>): string {
	const normal = text.replace(/\r\n?/g, '\n').replace(/\s+$/, '');
	const body = normal
		.split('\n')
		.map((l) => (l.trim() === '' ? '' : frame.indent + l))
		.join('\n');
	// A note written on one line with no frame gets one once it spans several, so
	// `<Note>a</Note>` edited to two lines does not glue a line to each tag.
	if (!frame.lead && !frame.trail && normal.includes('\n')) return `\n${body}\n`;
	return frame.lead + body + frame.trail;
}

/** The note's inner source, ready for the editor. */
export function readNote(source: string): ({ ok: true; text: string }) | { ok: false; reason: NoteRefusal } {
	const at = locateNote(source);
	if (!at.ok) return at;
	return { ok: true, text: toEditable(source.slice(at.start, at.end)).text };
}

export type WriteResult =
	| { ok: true; source: string }
	| { ok: false; reason: NoteRefusal | 'broken' };

/** Splice edited text into the note, keeping its indentation, and refuse any
    result that no longer parses with exactly one note in it. */
export function writeNote(source: string, text: string): WriteResult {
	const at = locateNote(source);
	if (!at.ok) return at;
	const frame = toEditable(source.slice(at.start, at.end));
	const next = source.slice(0, at.start) + fromEditable(text, frame) + source.slice(at.end);
	const check = locateNote(next);
	if (!check.ok) return { ok: false, reason: 'broken' };
	return { ok: true, source: next };
}

/** A cheap fingerprint (FNV-1a, 32-bit) of the file, so SAVE can tell that the
    file changed under the editor since it was loaded. Not a security measure. */
export function fingerprint(s: string): string {
	let h = 0x811c9dc5;
	for (let i = 0; i < s.length; i++) {
		h ^= s.charCodeAt(i);
		h = Math.imul(h, 0x01000193);
	}
	return (h >>> 0).toString(16).padStart(8, '0');
}
