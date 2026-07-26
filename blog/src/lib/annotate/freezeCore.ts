// FREEZE — turning a live ANNOTATE stroke into authored Draw source.
//
// ANNOTATE ink is deliberately transient: the inkBook is keyed by pathname, lives in
// localStorage, and the deck actively offers to clear it once it goes stale. Draw shapes
// are source. FREEZE is the one bridge between them — the speaker picks the marks worth
// keeping and they come back as <Polyline>/<Line>/<Rect> markup, either on the clipboard
// or (in dev, with SAVE allowed) written straight into the slide.
//
// This is a MAPPING, not new geometry, and it is nearly free for one reason: the two
// coordinate spaces are already identical. The ink surface is laid out at canvas size
// (1920x1080 — see annotateCore's toCanvasPoint) and <Draw>'s viewBox is `0 0 1920 1080`,
// so a stroke's `points` are drop-in Polyline points. No transform, no fitting, no
// rescaling to go subtly wrong.
//
// Total and pure, in the drawCore/patchSource tradition: garbage in yields a tag that
// still parses. Every coordinate goes through fmtNum, so a stroke carrying NaN emits `0`
// rather than pasting `NaN` into someone's source file. It is also the reason the whole
// thing unit-tests without a browser (tests/freezeCore.test.ts).

import { fmtNum, fmtPoint, sharedAttrs } from '$lib/draw/editing';
import type { Point } from '$lib/draw/types';
import { straightLine, strokeWidth, type AnnotateTool, type Stroke } from './annotateCore';

/** How a stroke is painted when frozen, so the markup matches what was on screen. */
export interface FreezeOptions {
	/** Pen stroke width in canvas px — must match <Annotate>'s own `penWidth`. */
	penWidth?: number;
	/** Highlighter band width in canvas px — must match <Annotate>'s `highlighterWidth`. */
	highlighterWidth?: number;
	/** Leading whitespace on each emitted line (the indent of the paste site). */
	indent?: string;
}

const PEN_WIDTH = 6;
const HIGHLIGHTER_WIDTH = 34;

/** <Draw>'s own default thickness (types.ts: "overrides --draw-thickness (default 4)").
    A frozen mark only carries `thickness` when it differs, so a pen at the Draw default
    emits no attribute at all and follows a later re-theme of the token. */
const DRAW_DEFAULT_THICKNESS = 4;

/** The highlighter's translucency, as the token ANNOTATE already paints it with rather
    than a frozen 0.45 — the same discipline that keeps a colourless stroke on
    `--annot-*`. A re-theme moves the frozen band with the live ink. */
const HIGHLIGHTER_STYLE = 'opacity:var(--annot-highlighter-alpha, 0.45)';

/** Which tools can become source at all. TEXT is the deliberate omission: it is not a
    `d`-from-points path but a typed label, and the Draw family has no counterpart for it
    (a <Block> is a different kind of thing with a different anchor). A text mark stays
    ink. */
const FREEZABLE: AnnotateTool[] = ['pen', 'line', 'arrow', 'rectangle', 'highlighter'];

/** Can this mark become a shape? The FREEZE mode uses this to decide what is even
    targetable, so a speaker never selects a label and then wonders why nothing came out. */
export function isFreezable(stroke: Stroke | undefined | null): boolean {
	return !!stroke && FREEZABLE.includes(stroke.tool);
}

function points(stroke: Stroke): Point[] {
	return Array.isArray(stroke.points) ? stroke.points : [];
}

/** `points={[[100, 900], [400, 700]]}` — the literal an author writes on a slide, built
    from the same fmtPoint every Draw shape's Copy uses, so a frozen tag is byte-identical
    in style to one ADJUST emits. */
function pointsAttr(pts: Point[]): string {
	return `points={[${pts.map(fmtPoint).join(', ')}]}`;
}

/** The colour attribute, and the ABSENCE is the meaningful case. A stroke with no colour
    was painted by the `--annot-*` role token; emitting no `color` hands the frozen shape
    to `--draw-stroke` in exactly the same way, so it follows a re-theme. Only a colour the
    speaker explicitly picked is carried across — never today's hex for the theme default. */
function styleAttrs(stroke: Stroke, opts: FreezeOptions): string {
	const thickness = strokeWidth(
		stroke.tool,
		opts.penWidth ?? PEN_WIDTH,
		opts.highlighterWidth ?? HIGHLIGHTER_WIDTH
	);
	return sharedAttrs({
		color: stroke.color || undefined,
		thickness: thickness === DRAW_DEFAULT_THICKNESS ? undefined : thickness,
		style: stroke.tool === 'highlighter' ? HIGHLIGHTER_STYLE : undefined
	});
}

/** One stroke as its opening tag, or '' for a mark that cannot be frozen.

    The per-tool mapping, and why each one is what it is:
      - pen         → <Polyline … smooth>, the same Catmull-Rom the ink was already drawn
                      through, so the frozen curve is the curve that was on screen.
      - highlighter → a FAT, translucent <Polyline>, not a <Rect>. A band is just a wide
                      stroke; boxing it would throw away the gesture the speaker made.
      - line/arrow  → <Line from to>, the two ends of the straight segment the stroke was
                      already shaped to; an arrow adds `arrow="end"`, which Line has.
      - rectangle   → <Rect x y width height>, the corners normalised the way rectD paints
                      them, so a box dragged bottom-right-to-top-left freezes right way up. */
export function freezeTag(stroke: Stroke, opts: FreezeOptions = {}): string {
	if (!isFreezable(stroke)) return '';
	const pts = points(stroke);
	if (pts.length === 0) return '';
	const attrs = styleAttrs(stroke, opts);

	if (stroke.tool === 'line' || stroke.tool === 'arrow') {
		// The stroke was shaped to a straight segment when it committed, but re-running
		// straightLine costs nothing and makes the mapping total for hand-built input.
		const seg = straightLine(pts);
		const from = seg[0] ?? pts[0];
		const to = seg[seg.length - 1] ?? from;
		const arrow = stroke.tool === 'arrow' ? ' arrow="end"' : '';
		return `<Line from={${fmtPoint(from)}} to={${fmtPoint(to)}}${arrow}${attrs} />`;
	}

	if (stroke.tool === 'rectangle') {
		const a = pts[0];
		const b = pts[pts.length - 1];
		const x = Math.min(a[0], b[0]);
		const y = Math.min(a[1], b[1]);
		const w = Math.abs(b[0] - a[0]);
		const h = Math.abs(b[1] - a[1]);
		return `<Rect x={${fmtNum(x)}} y={${fmtNum(y)}} width={${fmtNum(w)}} height={${fmtNum(h)}}${attrs} />`;
	}

	// pen + highlighter — both freehand point lists, both smoothed the way they were drawn.
	return `<Polyline ${pointsAttr(pts)} smooth${attrs} />`;
}

/** The markup for the selected marks, in the order they were DRAWN (not the order they
    were picked) — ink paints in array order, so a later stroke sits over an earlier one,
    and emitting in that same order keeps the frozen shapes stacked as they looked.

    Returns '' when nothing selected is freezable, which is what makes the FREEZE button's
    disabled state and this function agree without either consulting the other. */
export function freezeTags(
	strokes: Stroke[],
	selected: Iterable<string>,
	opts: FreezeOptions = {}
): string[] {
	const want = new Set(selected);
	if (want.size === 0 || !Array.isArray(strokes)) return [];
	return strokes
		.filter((s) => s && want.has(s.id))
		.map((s) => freezeTag(s, opts))
		.filter((tag) => tag !== '');
}

/** How many of the selected marks would actually produce a shape — what the bar's
    `FREEZE (n)` counts, so the number on the button is the number of tags you get. */
export function freezeCount(strokes: Stroke[], selected: Iterable<string>): number {
	return freezeTags(strokes, selected).length;
}

/** The complete snippet: the selected marks wrapped in a <Draw>, ready to paste into a
    slide. A `<Polyline>` outside a <Draw> renders nothing — the shapes read their surface
    from Draw's context — so the wrapper is not decoration, it is the difference between
    markup that works and markup that silently does not.

    Pass `wrap: false` when the destination already HAS a <Draw> to splice into (the
    source-write path knows this; a clipboard paste generally does not). */
export function freezeSnippet(
	strokes: Stroke[],
	selected: Iterable<string>,
	opts: FreezeOptions & { wrap?: boolean } = {}
): string {
	const tags = freezeTags(strokes, selected, opts);
	if (tags.length === 0) return '';
	const indent = opts.indent ?? '';
	if (opts.wrap === false) return tags.map((t) => `${indent}${t}`).join('\n');
	return [
		`${indent}<Draw>`,
		...tags.map((t) => `${indent}\t${t}`),
		`${indent}</Draw>`
	].join('\n');
}

/** The `import` line a pasted snippet needs, naming only the components it actually uses
    — so freezing one underline does not tell the author to import Rect and Line as well.
    Emitted alongside the snippet by the clipboard path; the source-write path adds it only
    when the slide is missing one (see freezeInsert). */
export function freezeImport(tags: string[]): string {
	const used = new Set<string>();
	for (const tag of tags) {
		const m = /^<([A-Za-z]+)/.exec(tag);
		if (m) used.add(m[1]);
	}
	if (used.size === 0) return '';
	const names = ['Draw', ...['Line', 'Polyline', 'Rect'].filter((n) => used.has(n))];
	return `import { ${names.join(', ')} } from '$lib/draw';`;
}
