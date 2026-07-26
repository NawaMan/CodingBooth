// Who owns a draggable's geometry: the props, or the author's `style`?
//
// Every author-facing component takes a `style` prop that is appended LAST on the
// root element, so the author's declaration outranks the component's own rules
// (see AGENTS.md, "Give it `style`, `id` and `class`"). On a ADJUST-draggable
// shape that rule has one pathological case: `Block` writes its box as inline
// `left/top/width/height`, and an author's `style="left: 40px"` lands in the SAME
// declaration block — where the last declaration simply wins. The DOM keeps ONE
// `left`, and it is the author's:
//
//     <Block name="db" x={200} style="left: 40px">
//     -> left: 40px; top: 300px; width: 400px; height: 160px;   (x={200} is gone)
//
// ADJUST then drags a box that cannot move: `x` tracks the pointer, the readout
// climbs, SAVE dutifully writes `x={640}` to source — and on screen, nothing.
// ADJUST looks broken while behaving exactly as specified.
//
// The rule this module encodes: THE PROPS OWN THE GEOMETRY. `style` is for
// cosmetics — stroke, dash, colour, a decorative `rotate()`. The handful of
// properties a Block actually writes are RESERVED: they are filtered out of the
// author's style before it is appended, so what you see always matches x/y/width/
// height and the drag is honest. Everything else passes through untouched and
// still wins, exactly as before.
//
// Reserving is not the same as rewriting. The author's source `style` is left
// alone (Copy/Save echo it back verbatim); the stray declaration just stops
// having an effect, and ADJUST-mode chrome says so. Nothing is guessed, nothing
// is silently edited on disk.
//
// Pure and browser-free, so it unit-tests without a DOM (tests/styleGuardCore.test.ts).

/** Properties a draggable writes itself, so an author's `style` must not.
 *
 *  `left/top/width/height` are what `Block` puts in its inline style, and what
 *  an SVG `<rect>` (Draw's `Rect`) carries as presentation attributes — which
 *  ANY css, inline style included, outranks. `x`/`y` are the CSS geometry
 *  properties for that same `<rect>`; on an HTML Block they are inert, so
 *  dropping them costs nothing and the warning still reads true. `inset*` are
 *  shorthands for left/top, and `position` decides whether left/top apply at all.
 *
 *  Deliberately NOT reserved, because each has a legitimate cosmetic use that
 *  reserving would break, and none of them actually contends with the geometry:
 *    - `right` / `bottom` — over-constrained against `left`+`width`, so CSS
 *      ignores them outright. Reserving would warn about a no-op.
 *    - `margin` — `margin: 0` is common and harmless on an absolute box.
 *    - `transform` / `translate` — `rotate()` and `scale()` are real authoring
 *      tools and must keep working. A translate DOES displace the box (see
 *      `offsets` below), but it is reported, not stripped.
 *    - `rx` / `ry` — Draw's `Rect` uses `rx` for CORNER ROUNDING while `Ellipse`
 *      uses rx/ry as RADII. One name, two meanings; reserving it would break
 *      rounded rects to guard a case nobody authors.
 */
const RESERVED = new Set([
	'left',
	'top',
	'width',
	'height',
	'position',
	'inset',
	'inset-block',
	'inset-block-start',
	'inset-block-end',
	'inset-inline',
	'inset-inline-start',
	'inset-inline-end',
	'x',
	'y',
]);

/** A `transform` carrying one of these functions moves the painted box away from
 *  its x/y without overriding them — so the drag still works, but the pixels sit
 *  somewhere other than the geometry, and every `Connector`/`Spotlight` anchored
 *  to this Block (which resolve against the PROPS, via stores/blockAnchors.ts)
 *  points at empty space. Worth saying out loud; not worth confiscating. */
const DISPLACING = /\b(?:translate|translate3d|translatex|translatey|matrix|matrix3d)\s*\(/;

export interface StyleGuard {
	/** The author's style with every RESERVED declaration removed — this is what
	 *  gets appended to the component's own rules. Cosmetics survive verbatim. */
	safe: string;
	/** Reserved properties the author declared, in source order, de-duplicated.
	 *  Non-empty means "this style tried to set geometry and was ignored" — the
	 *  ADJUST badge. Empty for the overwhelmingly common case. */
	reserved: string[];
	/** Properties that displace the painted box from its geometry without
	 *  overriding it (a translate-bearing `transform`, or standalone `translate`).
	 *  Kept in `safe` — reported, not stripped. */
	offsets: string[];
}

const EMPTY: StyleGuard = { safe: '', reserved: [], offsets: [] };

/**
 * Split a CSS declaration list on top-level `;`, ignoring separators nested in
 * parens (`translate(1px, 2px)`) or quotes (`content: "a;b"`, `url('a;b')`) —
 * a naive `.split(';')` shreds both. Tolerant by design: unbalanced parens and
 * unterminated quotes yield the remainder as one last declaration rather than
 * throwing, because this runs on whatever an author typed.
 */
function declarations(style: string): string[] {
	const out: string[] = [];
	let depth = 0;
	let quote: string | null = null;
	let start = 0;

	for (let i = 0; i < style.length; i++) {
		const c = style[i];
		if (quote) {
			// A backslash-escaped quote does not close the string.
			if (c === quote && style[i - 1] !== '\\') quote = null;
			continue;
		}
		if (c === '"' || c === "'") quote = c;
		else if (c === '(') depth++;
		else if (c === ')') depth = Math.max(0, depth - 1);
		else if (c === ';' && depth === 0) {
			out.push(style.slice(start, i));
			start = i + 1;
		}
	}
	out.push(style.slice(start));
	return out;
}

/**
 * Decide what an author's `style` string is allowed to do to a ADJUST-draggable
 * shape: strip the properties the component owns, keep everything else, and say
 * what was taken and what merely displaces.
 *
 * Total: null, undefined, '' and pure garbage all return a drawable result. The
 * output is only ever a subset of the input's declarations — this never invents
 * a property, never reorders the survivors, and never rewrites a value.
 */
export function guardStyle(style: string | null | undefined): StyleGuard {
	if (typeof style !== 'string' || style.trim() === '') return { ...EMPTY };

	const kept: string[] = [];
	const reserved: string[] = [];
	const offsets: string[] = [];

	for (const raw of declarations(style)) {
		const decl = raw.trim();
		if (decl === '') continue;

		const colon = decl.indexOf(':');
		// No colon, or nothing either side of it: not a declaration we can read.
		// Keep it verbatim — it is the author's text and dropping it silently
		// would be a worse lie than passing along something inert.
		if (colon <= 0) {
			kept.push(decl);
			continue;
		}

		const prop = decl.slice(0, colon).trim().toLowerCase();
		const value = decl.slice(colon + 1).trim().toLowerCase();
		// `--custom-prop: left` is a variable, not the `left` property.
		const isCustom = prop.startsWith('--');

		if (!isCustom && RESERVED.has(prop)) {
			// A declaration with no value sets nothing — ignore it rather than
			// badging the author for `left:;`.
			if (value === '') continue;
			if (!reserved.includes(prop)) reserved.push(prop);
			continue; // dropped from `safe` — the props own this property
		}

		if (!isCustom && (prop === 'translate' || (prop === 'transform' && DISPLACING.test(value)))) {
			// `translate: none` / `transform: none` shift nothing.
			if (value !== 'none' && !offsets.includes(prop)) offsets.push(prop);
		}

		kept.push(decl);
	}

	return { safe: kept.join('; '), reserved, offsets };
}
