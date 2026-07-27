/*
  Annotation geometry — the pure decision layer behind the ink overlay (see
  components/Annotate.svelte, stores/annotation.ts).

  Side-effect free and total, in the drawCore/connectorCore tradition: every input
  may be junk — a pointer event fired before layout settled, a zero-width rect, a
  stroke list another window wrote in an older format — and the answer is still a
  drawable result. Nothing here ever yields NaN, and nothing ever throws.

  A stroke is `Point[]` plus a tool, NOT a PathShape: the `d` string is DERIVED
  (via drawCore's smoothPath) rather than stored, so the sampled points stay the
  single source of truth and the same stroke re-renders identically on the window
  that drew it and the window that mirrors it.
*/

import type { Point } from '$lib/draw/types';
import type { Codec } from '$lib/utils/stateCore';
import { finite, finitePoint, round, smoothPath } from '$lib/draw/drawCore';

/** The DRAW tools: pen (opaque, thin freehand), line (a straight two-point segment), arrow
    (a line with a chevron head DERIVED at render time, see arrowD), rectangle (a closed box
    between two corners, see rectD), highlighter (fat, translucent, blended band), or text (a
    typed label anchored at a point — the one mark that is NOT a `d`-from-points path). The
    stroke ones differ only in how the gesture is SHAPED and how the `d` is painted; text
    carries its own string. */
export type AnnotateTool = 'pen' | 'line' | 'arrow' | 'rectangle' | 'highlighter' | 'text';

/** What the bar can be set to: any DRAW tool, the ERASER, or FREEZE. Neither of the last
    two is a tool a stroke can be — the eraser removes whole strokes and freeze promotes
    them to source — so they live here and never in `Stroke.tool` or the per-tool colour
    map. */
export type AnnotateMode = AnnotateTool | 'eraser' | 'freeze';

/** One freehand mark. `id` exists so a mirrored list can be keyed without
    re-drawing every stroke on each update.

    `color` is OPTIONAL, and the absence is meaningful: a stroke with no colour is
    painted by the `--annot-*` role token, so it follows the theme. Only a stroke the
    speaker explicitly picked a colour for carries one. Storing the theme's current hex
    instead would freeze it — a deck that later re-themed would keep repainting old ink
    in the old palette. */
export interface Stroke {
	id: string;
	tool: AnnotateTool;
	points: Point[];
	color?: string;
	/** TEXT marks only: the typed label. `points[0]` is its top-left anchor. */
	text?: string;
	/** TEXT marks only: the font size in canvas px, stored so a re-theme or another window
	    renders the label at the size it was placed rather than the current default. */
	size?: number;
}

/** One slide's ink, plus when it was last touched.

    The timestamp is the whole reason ink can be persisted without becoming a trap: it
    is what lets the deck notice, when you land on a slide, that these marks are from
    LAST WEEK and offer to clear them — rather than silently showing a stranger's
    rehearsal notes to an audience. */
export interface SlideInk {
	strokes: Stroke[];
	ts: number;
}

/** Every slide's ink, keyed by the slide's full pathname (`/slides/intro.html`) — so
    two decks in one origin never scribble on each other. */
export type InkBook = Record<string, SlideInk>;

/** How old ink has to be before the deck mentions it. A day: today's marks never nag,
    and anything you drew in a previous sitting always does. */
export const INK_STALE_AFTER_MS = 24 * 60 * 60 * 1000;

/** The screen rect of the ink surface — the subset of DOMRect we actually use,
    so a test can hand in a plain object. */
export interface SurfaceRect {
	left: number;
	top: number;
	width: number;
	height: number;
}

/** Map a pointer event's CLIENT coordinates into canvas pixels.

    The overlay is laid out at canvas size (1920x1080) and then CSS-scaled by the
    display mode — FITTED scales about the center, SCALED about the top-left, and
    the presenter console applies no transform at all. Rather than track which is
    in force, we measure: the surface's own on-screen rect already encodes every
    transform above it, so `(client - rect.origin) / rect.size * canvas` is correct
    in all three without knowing which one we are in. This is the DrawHandle
    idiom (scale = rect.width / canvasWidth), solved for an absolute point rather
    than a delta.

    A zero-area rect (measured before layout, or a display:none surface) would
    divide by zero, so it yields the origin rather than NaN — a dot at [0,0] is
    wrong but drawable; `NaNpx` is neither. */
export function toCanvasPoint(
	clientX: number,
	clientY: number,
	rect: SurfaceRect | null | undefined,
	canvasWidth = 1920,
	canvasHeight = 1080
): Point {
	if (!rect) return [0, 0];
	const w = finite(rect.width, 0);
	const h = finite(rect.height, 0);
	if (!(w > 0) || !(h > 0)) return [0, 0];

	const cw = finite(canvasWidth, 1920);
	const ch = finite(canvasHeight, 1080);
	const x = ((finite(clientX) - finite(rect.left)) / w) * cw;
	const y = ((finite(clientY) - finite(rect.top)) / h) * ch;
	return [round(x), round(y)];
}

/** Drop samples closer than `minDist` (canvas px) to the last one KEPT.

    A pointermove stream fires at the pointer's rate, not the pen's — a slow,
    deliberate circle emits hundreds of near-duplicate points, which would bloat
    the `d` string, and (the reason it actually matters) the JSON payload we push
    through the presenter's localStorage channel on every stroke. Distance from
    the last KEPT point, not the last SEEN one, so a slow drag decimates instead
    of sneaking through one sub-threshold step at a time.

    The final sample is always kept: a stroke has to end where the pen lifted, or
    a quick flick loses its tail. */
export function simplifyPoints(points: Point[], minDist = 4): Point[] {
	if (!Array.isArray(points) || points.length === 0) return [];
	const pts = points.map(finitePoint);
	const min = Math.max(0, finite(minDist, 4));

	const kept: Point[] = [pts[0]];
	for (let i = 1; i < pts.length; i++) {
		const p = pts[i];
		const last = kept[kept.length - 1];
		if (Math.hypot(p[0] - last[0], p[1] - last[1]) >= min) kept.push(p);
	}

	// Re-attach the lift point if decimation swallowed it.
	const end = pts[pts.length - 1];
	const tail = kept[kept.length - 1];
	if (pts.length > 1 && (tail[0] !== end[0] || tail[1] !== end[1])) kept.push(end);
	return kept;
}

/** Flatten a highlighter swipe into a LEVEL band.

    A highlighter is not a pen. Swiping over a line of text, the hand drifts and rolls, and a
    stroke that faithfully follows it comes out visibly crooked — the band slopes across the
    very line it is meant to sit on, and the smoothing then bows it for good measure. Nobody
    wants a wonky highlight; the intent was always "cover this row".

    So the band is pinned to ONE y and reduced to its horizontal extent: two points, dead
    level, so `smoothPath` degenerates to a straight segment and there is nothing left to bow.

    THE Y IS THE FIRST POINT'S — the height is chosen when you press down, and never moves
    again. The obvious-looking alternative, the mean of the samples, is what this function did
    first and it was wrong in a way only visible in the hand: the mean SHIFTS as each new
    sample arrives, so the whole band slid up and down under the cursor while the swipe was
    still being drawn. A mark that will not hold still is unusable, whatever its statistics.
    Anchoring costs nothing anyway — you set the line where you press, exactly as a physical
    highlighter does, and the swipe only ever grows sideways from there.

    A gesture with no horizontal extent is left ALONE: a vertical swipe (down a column of
    code, say) or a tap would otherwise collapse to a zero-length band, i.e. vanish. The rule
    is "level a horizontal swipe", not "forbid anything else". */
export function levelPoints(points: Point[]): Point[] {
	if (!Array.isArray(points) || points.length < 2) return Array.isArray(points) ? points.map(finitePoint) : [];
	const pts = points.map(finitePoint);

	const y = round(pts[0][1]); // the height you pressed at — fixed for the life of the stroke
	let minX = pts[0][0];
	let maxX = pts[0][0];
	for (const [x] of pts) {
		if (x < minX) minX = x;
		if (x > maxX) maxX = x;
	}
	if (maxX - minX < 1) return pts; // no horizontal extent — not a swipe; leave it be

	return [
		[round(minX), y],
		[round(maxX), y]
	];
}

/** Snap a PEN stroke to a dead-straight X- or Y-axis line — the pen's answer to Shift.

    Underlining a line of code, or dropping a plumb line down a column, is the common
    ANNOTATE move, and a freehand hand cannot hold a straight edge on stage — the very
    reason `levelPoints` pins a HIGHLIGHTER swipe to one row. The pen has no such discipline
    of its own; this is the one it borrows while Shift is held. The stroke is reduced to the
    two points a ruler would draw: the press point, and the current point PROJECTED onto
    whichever axis the gesture has travelled furthest along.

    ANCHORED AT THE PRESS POINT, exactly as the level band is — the line grows out from where
    the pen went down and never shifts under it. It is recomputed every `pointermove` (Shift
    is a live modifier, not a commit-time flag), so the axis is free to FLIP mid-gesture as
    the dominant direction changes, and releasing Shift hands the raw freehand samples back
    untouched.

    A gesture with no travel — a tap, or a press that has not moved yet — is left ALONE
    rather than collapsed to a zero-length line: there is no dominant axis to choose, and a
    dot is a real mark (`strokeD` paints a lone point as one). This mirrors `levelPoints`
    leaving an extent-less swipe be.

    Horizontal wins a tie: an underline is the more common intent than a plumb line, and a
    dead-diagonal drag has to resolve to one axis rather than jitter between the two. */
export function snapAxis(points: Point[]): Point[] {
	if (!Array.isArray(points) || points.length < 2) return Array.isArray(points) ? points.map(finitePoint) : [];
	const pts = points.map(finitePoint);

	const start = pts[0];
	const end = pts[pts.length - 1]; // where the pen is NOW — the far end of the ruler
	const dx = end[0] - start[0];
	const dy = end[1] - start[1];
	if (Math.abs(dx) < 1 && Math.abs(dy) < 1) return pts; // no travel yet — a tap; leave it be

	return Math.abs(dx) >= Math.abs(dy)
		? [[round(start[0]), round(start[1])], [round(end[0]), round(start[1])]] // dead HORIZONTAL, at the press Y
		: [[round(start[0]), round(start[1])], [round(start[0]), round(end[1])]]; // dead VERTICAL, at the press X
}

/** Reduce a gesture to the straight segment a LINE or an ARROW draws — tail (press) to
    head (current/lift).

    Like `snapAxis`, but FREE-ANGLE: the mark points wherever the hand dragged, it is not
    projected onto an axis. Anchored at the press point, with the head chasing the current
    sample — so the live mark swings with the pointer and commits pointing where it was let
    go. A drag that never travelled (a tap) is left as its samples, so it falls through to a
    dot rather than collapsing to a zero-length segment. Total and NaN-safe. */
export function straightLine(points: Point[]): Point[] {
	if (!Array.isArray(points) || points.length < 2) return Array.isArray(points) ? points.map(finitePoint) : [];
	const pts = points.map(finitePoint);
	return [pts[0], pts[pts.length - 1]];
}

/** The SVG `d` for an ARROW — a straight shaft from tail to head, with an OPEN two-line
    chevron head at the head end.

    Defined by exactly two points, the tail (press) and the head (current/lift): the
    head is DERIVED here rather than stored, the same "the points are the truth, the `d`
    is derived" discipline `strokeD` keeps — so a mirrored arrow re-draws identically on
    the window that only heard it, and the head stays crisp at any canvas scale. The head
    is two barbs swept `headAngle` back from the reversed shaft direction, drawn as an
    open chevron rather than a filled triangle so it paints with the SAME round-cap stroke
    (and the same theme colour and glow) as the rest of the ink — no fill to theme, no
    <marker> to register.

    `headLen` is clamped to the shaft length, so a short arrow keeps a head no longer than
    itself instead of a chevron that overshoots the tail. A zero-length arrow (tail == head,
    a tap that never travelled) falls back to a dot exactly as `strokeD` does — a mark, not
    nothing. Every input may be junk and the answer is still drawable: nothing here is NaN. */
export function arrowD(points: Point[], headLen = 36, headAngle = Math.PI / 7): string {
	if (!Array.isArray(points) || points.length === 0) return '';
	const pts = points.map(finitePoint);
	const tail = pts[0];
	const head = pts[pts.length - 1];
	const dx = head[0] - tail[0];
	const dy = head[1] - tail[1];
	const len = Math.hypot(dx, dy);
	if (!(len > 0)) {
		const [x, y] = tail; // a tap, or tail == head — a dot, like strokeD
		return `M ${round(x)} ${round(y)} L ${round(x)} ${round(y)}`;
	}

	const ux = dx / len;
	const uy = dy / len;
	const h = Math.min(Math.max(0, finite(headLen, 36)), len); // never longer than the shaft
	const a = Math.max(0, finite(headAngle, Math.PI / 7));
	const cos = Math.cos(a);
	const sin = Math.sin(a);

	// The two barbs: the reversed shaft direction (-ux, -uy) rotated by ±a, scaled by h,
	// hung off the head. Rotation of (vx, vy) by θ is (vx·cos − vy·sin, vx·sin + vy·cos).
	const b1x = head[0] + h * (-ux * cos + uy * sin);
	const b1y = head[1] + h * (-uy * cos - ux * sin);
	const b2x = head[0] + h * (-ux * cos - uy * sin);
	const b2y = head[1] + h * (-uy * cos + ux * sin);

	return (
		`M ${round(tail[0])} ${round(tail[1])} L ${round(head[0])} ${round(head[1])}` +
		` M ${round(b1x)} ${round(b1y)} L ${round(head[0])} ${round(head[1])} L ${round(b2x)} ${round(b2y)}`
	);
}

/** The SVG `d` for a RECTANGLE — a closed box between two opposite corners. The corners are
    NORMALISED (min/max), so dragging up-left draws the same box as down-right, and the outline
    is drawn stroke-only (the surface fills nothing) so it rings what it is put around. A
    zero-area drag — a tap, or a dead-horizontal/vertical drag — still yields a drawable path
    rather than nothing. Total and NaN-safe, like the rest of the family. */
export function rectD(points: Point[]): string {
	if (!Array.isArray(points) || points.length === 0) return '';
	const pts = points.map(finitePoint);
	const a = pts[0];
	const b = pts[pts.length - 1];
	const x1 = round(Math.min(a[0], b[0]));
	const y1 = round(Math.min(a[1], b[1]));
	const x2 = round(Math.max(a[0], b[0]));
	const y2 = round(Math.max(a[1], b[1]));
	return `M ${x1} ${y1} L ${x2} ${y1} L ${x2} ${y2} L ${x1} ${y2} Z`;
}

/** Distance in canvas px from a point to a single segment a→b — the classic projection
    onto the segment, clamped to its ends. A degenerate segment (a == b) collapses to the
    distance to that point rather than dividing by zero. Total: junk in → a finite answer. */
function segmentDistance(p: Point, a: Point, b: Point): number {
	const vx = b[0] - a[0];
	const vy = b[1] - a[1];
	const wx = p[0] - a[0];
	const wy = p[1] - a[1];
	const len2 = vx * vx + vy * vy;
	// t = how far along a→b the foot of the perpendicular falls, clamped into [0, 1] so a
	// point beyond an end measures to the END, not to the infinite line.
	let t = len2 > 0 ? (wx * vx + wy * vy) / len2 : 0;
	t = Math.max(0, Math.min(1, t));
	const cx = a[0] + t * vx;
	const cy = a[1] + t * vy;
	return Math.hypot(p[0] - cx, p[1] - cy);
}

/** The closest a stroke's INK comes to a point, in canvas px — the min over its segments.
    This is the eraser's whole question: "is the pointer on this mark?" A stroke stored as
    its sampled points is exactly a polyline, so hit-testing the samples hit-tests the ink.

    An EMPTY stroke is infinitely far (nothing to touch), so it never registers a hit; a
    single-point stroke (a tap → a dot) measures to that point. Total and NaN-safe, in the
    drawCore tradition: every coordinate is repaired before it is used. */
export function distanceToStroke(point: Point, points: Point[]): number {
	if (!Array.isArray(points) || points.length === 0) return Infinity;
	const p = finitePoint(point);
	const pts = points.map(finitePoint);
	if (pts.length === 1) return Math.hypot(p[0] - pts[0][0], p[1] - pts[0][1]);

	let min = Infinity;
	for (let i = 1; i < pts.length; i++) {
		const d = segmentDistance(p, pts[i - 1], pts[i]);
		if (d < min) min = d;
	}
	return min;
}

/** Does an eraser centred at `point` with reach `tolerance` (canvas px) touch this stroke?
    `tolerance` is the eraser's own radius plus the stroke's half-width, so a fat highlighter
    band is as easy to catch as it looks and a hair-thin pen needs a near-direct hit. A
    non-finite or negative tolerance reads as 0 — a hit only dead on the ink. */
export function hitStroke(point: Point, points: Point[], tolerance: number): boolean {
	const tol = Math.max(0, finite(tolerance, 0));
	return distanceToStroke(point, points) <= tol;
}

/** Approximate the box a TEXT mark occupies, in canvas px: its anchor is the TOP-LEFT, the
    width grows with the character count, the height is one line of the font size. Approximate
    on purpose — it is used to GRAB, RE-EDIT or ERASE a label, where "near enough" beats a
    glyph-metric measurement the pure layer cannot make (real advances live in the browser).
    A wider-than-average font just means the grab box runs a little short of the last glyph. */
export function textBounds(
	anchor: Point,
	text: string,
	size: number
): { x: number; y: number; w: number; h: number } {
	const a = finitePoint(anchor);
	const s = Math.max(1, finite(size, 40));
	const chars = typeof text === 'string' ? text.length : 0;
	const w = Math.max(s * 0.6, chars * s * 0.55); // a rough mean glyph advance
	const h = s * 1.25; // one line, with a little lead
	return { x: round(a[0]), y: round(a[1]), w: round(w), h: round(h) };
}

/** Is a point within a TEXT mark's box, padded by `tolerance` (the eraser's reach, or a grab
    slop)? Uses textBounds, so it is the same box the label is measured to draw inside. */
export function hitText(point: Point, anchor: Point, text: string, size: number, tolerance = 0): boolean {
	const p = finitePoint(point);
	const tol = Math.max(0, finite(tolerance, 0));
	const b = textBounds(anchor, text, size);
	return p[0] >= b.x - tol && p[0] <= b.x + b.w + tol && p[1] >= b.y - tol && p[1] <= b.y + b.h + tol;
}

/** Keep the pen's bar inside the canvas.

    A bar dragged off the edge is a bar the speaker cannot get back — and since the position
    is persisted, it would still be gone tomorrow. Clamping is what makes the drag safe to
    remember. A bar larger than the canvas (a very narrow portrait deck) clamps to 0 rather
    than to a negative bound, so it stays reachable rather than being pushed off the other side. */
export function clampBarPos(
	x: number,
	y: number,
	barWidth: number,
	barHeight: number,
	canvasWidth = 1920,
	canvasHeight = 1080
): { x: number; y: number } {
	const maxX = Math.max(0, finite(canvasWidth, 1920) - Math.max(0, finite(barWidth, 0)));
	const maxY = Math.max(0, finite(canvasHeight, 1080) - Math.max(0, finite(barHeight, 0)));
	return {
		x: round(Math.min(maxX, Math.max(0, finite(x, 0)))),
		y: round(Math.min(maxY, Math.max(0, finite(y, 0))))
	};
}

/** Where the speaker parked the pen's bar, in canvas px. `null` means "wherever it
    normally sits" (bottom-centre) — an un-dragged bar stores no coordinates, so a deck
    that later moves the default is free to. */
export type BarPos = { x: number; y: number } | null;

export function sanitizeBarPos(raw: unknown): BarPos {
	if (!raw || typeof raw !== 'object') return null;
	const p = raw as { x?: unknown; y?: unknown };
	if (typeof p.x !== 'number' || typeof p.y !== 'number') return null;
	if (!Number.isFinite(p.x) || !Number.isFinite(p.y)) return null;
	return { x: round(p.x), y: round(p.y) };
}

/** The codec the persisted bar position rides on — validated on the way in, for the same
    reason the ink book is: a corrupt `{"x":"left"}` would otherwise park the bar at
    `NaNpx`, off-screen and unrecoverable. */
export function barPosCodec(): Codec<BarPos> {
	return {
		read(rawText: string): BarPos {
			try {
				return sanitizeBarPos(JSON.parse(rawText));
			} catch {
				return null;
			}
		},
		write(value: BarPos): string {
			return JSON.stringify(value ?? null);
		}
	};
}

/** The SVG `d` for a stroke's points.

    Two or more points go through drawCore's `smoothPath` — the same Catmull-Rom
    smoothing `Polyline` and `Curve` render through, so ink is drawn by the code
    the rest of the Draw family is already tested against.

    A SINGLE point is the case smoothPath cannot serve (it needs two to make a
    segment and returns ''), yet it is exactly what a tap produces — the speaker
    dotting a term. Emitting a zero-length line gives it back: with the round
    linecap the surface paints, `M x y L x y` renders as a dot of the stroke's
    width. Without this a tap drew nothing at all, which reads as a broken pen. */
export function strokeD(points: Point[]): string {
	if (!Array.isArray(points) || points.length === 0) return '';
	const pts = points.map(finitePoint);
	if (pts.length === 1) {
		const [x, y] = pts[0];
		return `M ${round(x)} ${round(y)} L ${round(x)} ${round(y)}`;
	}
	return smoothPath(pts);
}

/** Stroke width in canvas px for a tool. The highlighter is deliberately a band,
    not a line — highlighting here means SWIPING OVER the words, so the mark has to
    be tall enough to cover a line of text at canvas scale. */
export function strokeWidth(tool: AnnotateTool, pen = 6, highlighter = 34): number {
	const w = tool === 'highlighter' ? finite(highlighter, 34) : finite(pen, 6);
	return w > 0 ? w : 1;
}

/** Coerce whatever came off the wire into strokes we can draw.

    The presenter channel is JSON in localStorage, which means the payload may be
    from another tab, an older release, or a half-finished write. Anything
    unreadable is DROPPED rather than defaulted: a malformed stroke has no
    "reasonable" geometry to guess, and drawing a guess over the speaker's slide is
    worse than drawing nothing. An unknown tool, though, is just a paint choice, so
    it falls back to the pen rather than costing the stroke. */
export function sanitizeStrokes(raw: unknown): Stroke[] {
	if (!Array.isArray(raw)) return [];
	const out: Stroke[] = [];
	for (const item of raw) {
		if (!item || typeof item !== 'object') continue;
		const s = item as Partial<Stroke>;
		if (!Array.isArray(s.points)) continue;

		const points = s.points
			.filter((p) => Array.isArray(p) && p.length >= 2)
			.map((p) => finitePoint(p as Point));
		if (points.length === 0) continue;

		const tool: AnnotateTool = KNOWN_TOOLS.includes(s.tool as AnnotateTool)
			? (s.tool as AnnotateTool)
			: 'pen';

		const stroke: Stroke = {
			id: typeof s.id === 'string' && s.id ? s.id : `ink-${out.length}`,
			tool,
			points
		};
		// An unusable colour drops back to the theme token rather than costing the stroke —
		// and is never passed through to the DOM, since it lands in an inline `style`.
		if (isColor(s.color)) stroke.color = s.color as string;

		// A TEXT mark carries a string, and a label with no words is nothing to draw — so a
		// text mark whose content fails sanitation is DROPPED, not kept blank.
		if (tool === 'text') {
			const text = sanitizeText(s.text);
			if (!text) continue;
			stroke.text = text;
			const size = finite(s.size as number, 0);
			if (size > 0) stroke.size = round(size);
		}

		out.push(stroke);
	}
	return out;
}

/** The tools a stored mark may legitimately claim. An unknown value falls back to the pen
    (a tool is just a paint choice — losing the mark over it would be a bad trade); this list
    is the gate that keeps the eraser MODE, or any junk, from riding in as a stroke. */
const KNOWN_TOOLS: AnnotateTool[] = ['pen', 'line', 'arrow', 'rectangle', 'highlighter', 'text'];

/** The longest a text label may be — a guard on the one field that carries free user input
    into storage. Not a UX limit so much as an abuse cap: a runaway string would bloat the
    localStorage payload the presenter channel pushes on every change. */
export const TEXT_MAX_LEN = 280;

/** Coerce a text mark's content into something safe to store and draw.

    It reaches the DOM as SVG TEXT content, which Svelte escapes — no markup runs — so the
    risk is not injection but abuse: the string is capped at TEXT_MAX_LEN, control characters
    (including the newlines a single-line label never has) are dropped, and an all-whitespace
    or empty result is `undefined` so the caller drops the mark rather than storing a blank. */
export function sanitizeText(raw: unknown): string | undefined {
	if (typeof raw !== 'string') return undefined;
	// eslint-disable-next-line no-control-regex
	const cleaned = raw.replace(/[\u0000-\u001F\u007F]/g, '').slice(0, TEXT_MAX_LEN);
	return cleaned.trim().length > 0 ? cleaned : undefined;
}

/** Is this a colour we are willing to write into an inline `style`?

    Deliberately a strict allow-list (`#rgb`, `#rrggbb`, `#rrggbbaa`, and the
    `rgb()/rgba()/hsl()/hsla()` functions) rather than "any non-empty string". The value
    reaches the DOM as `style="stroke: …"`, and it can arrive from `localStorage`, which
    another tab — or an older release, or a bad actor with a console — may have written.
    A `}` in the wrong place there is a CSS injection, so anything that is not plainly a
    colour is refused and the stroke falls back to the theme. */
export function isColor(value: unknown): boolean {
	if (typeof value !== 'string') return false;
	const v = value.trim();
	if (v.length === 0 || v.length > 32) return false;
	if (/^#[0-9a-f]{3}$/i.test(v) || /^#[0-9a-f]{6}$/i.test(v) || /^#[0-9a-f]{8}$/i.test(v)) return true;
	return /^(rgb|hsl)a?\([0-9a-z\s.,%/-]+\)$/i.test(v);
}

/** Coerce a whole ink book off the wire (or out of `localStorage`).

    A slide whose strokes all fail sanitation is DROPPED rather than kept as an empty
    entry — otherwise the book accretes a key per slide ever visited and never shrinks,
    and "does this slide have ink?" stops being answerable by looking. */
export function sanitizeInkBook(raw: unknown): InkBook {
	if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return {};
	const out: InkBook = {};
	for (const [path, value] of Object.entries(raw as Record<string, unknown>)) {
		if (!path || !value || typeof value !== 'object') continue;
		const entry = value as Partial<SlideInk>;
		const strokes = sanitizeStrokes(entry.strokes);
		if (strokes.length === 0) continue;
		out[path] = { strokes, ts: Math.max(0, finite(entry.ts as number, 0)) };
	}
	return out;
}

/** The codec the persisted ink book rides on. `jsonCodec` would very nearly do, and
    that is the trap it shares with `booleanCodec`: `JSON.parse` will hand back an array,
    a string or a number just as happily as an object, and any of them would poison every
    subscriber downstream. Everything is validated on the way in. */
export function inkBookCodec(): Codec<InkBook> {
	return {
		read(raw: string): InkBook | null {
			try {
				return sanitizeInkBook(JSON.parse(raw));
			} catch {
				return null; // unparseable → the store keeps its initial (an empty book)
			}
		},
		write(value: InkBook): string {
			return JSON.stringify(value ?? {});
		}
	};
}

/** Is this slide's ink old enough to mention? False for a slide with no ink at all —
    there is nothing to offer to clear, and a prompt about nothing is just noise.

    Ink with NO timestamp (written by a release before we recorded them) counts as stale:
    we cannot date it, and the whole point of the prompt is to catch marks you have
    forgotten about. */
export function isStaleInk(
	ink: SlideInk | undefined | null,
	now: number,
	maxAgeMs = INK_STALE_AFTER_MS
): boolean {
	if (!ink || !Array.isArray(ink.strokes) || ink.strokes.length === 0) return false;
	const ts = finite(ink.ts, 0);
	if (ts <= 0) return true;
	const max = Math.max(0, finite(maxAgeMs, INK_STALE_AFTER_MS));
	return finite(now, 0) - ts >= max;
}

/** "3 days ago" / "5 hours ago" — how the prompt says WHEN, since "you have old ink" is
    a lot less persuasive than "you have ink from last Tuesday". Coarse on purpose: the
    speaker needs to decide whether it is theirs, not to time it. */
export function inkAgeText(ts: number, now: number): string {
	// Undated ink (written before we stamped it, or with a corrupt `ts`) must NOT be dated
	// from the epoch — that reads as "20138 days ago", which is not a fact about the ink, it
	// is a fact about 1970. Say the one true thing we know instead.
	const stamp = finite(ts, 0);
	if (stamp <= 0) return 'an earlier session';

	const ms = finite(now, 0) - stamp;
	if (!(ms > 0)) return 'just now';
	const mins = Math.floor(ms / 60000);
	if (mins < 1) return 'just now';
	if (mins < 60) return `${mins} minute${mins === 1 ? '' : 's'} ago`;
	const hours = Math.floor(mins / 60);
	if (hours < 24) return `${hours} hour${hours === 1 ? '' : 's'} ago`;
	const days = Math.floor(hours / 24);
	return `${days} day${days === 1 ? '' : 's'} ago`;
}
