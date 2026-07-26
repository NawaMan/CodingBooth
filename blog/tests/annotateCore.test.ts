// Unit tests for the annotation geometry — pure, total, NaN-safe, in the
// drawCore/connectorCore tradition. Every input here may be junk (a pointer event
// fired before layout settled, a payload another tab wrote), and the contract is
// that the answer is still something drawable.
import { describe, expect, it } from 'vitest';
import {
	arrowD,
	barPosCodec,
	clampBarPos,
	distanceToStroke,
	hitStroke,
	hitText,
	inkAgeText,
	inkBookCodec,
	isColor,
	isStaleInk,
	levelPoints,
	rectD,
	sanitizeInkBook,
	sanitizeStrokes,
	sanitizeText,
	simplifyPoints,
	snapAxis,
	straightLine,
	strokeD,
	strokeWidth,
	textBounds,
	TEXT_MAX_LEN,
	toCanvasPoint
} from '../src/lib/annotate/annotateCore';
import {
	readAnnotateParam,
	readSticky,
	resolveCanAnnotate
} from '../src/lib/annotate/annotateAccessCore';
import type { Point } from '../src/lib/draw/types';

const RECT = { left: 0, top: 0, width: 960, height: 540 }; // canvas at 50%

describe('toCanvasPoint', () => {
	it('maps client coords into canvas pixels through the surface rect', () => {
		// The surface is on screen at half size, so a click at its centre is the
		// canvas centre — this is the whole reason we measure instead of computing:
		// the rect already encodes whatever transform the display mode applied.
		expect(toCanvasPoint(480, 270, RECT)).toEqual([960, 540]);
		expect(toCanvasPoint(0, 0, RECT)).toEqual([0, 0]);
		expect(toCanvasPoint(960, 540, RECT)).toEqual([1920, 1080]);
	});

	it('accounts for a surface that is offset in the viewport', () => {
		// FITTED centres the canvas, so the surface rarely starts at 0,0.
		const offset = { left: 100, top: 50, width: 960, height: 540 };
		expect(toCanvasPoint(100, 50, offset)).toEqual([0, 0]);
		expect(toCanvasPoint(580, 320, offset)).toEqual([960, 540]);
	});

	it('honours a non-default canvas (a portrait deck)', () => {
		const r = { left: 0, top: 0, width: 540, height: 960 };
		expect(toCanvasPoint(270, 480, r, 1080, 1920)).toEqual([540, 960]);
	});

	it('yields the origin rather than NaN for a zero-area or missing rect', () => {
		// Measured before layout, or a display:none surface. A dot at 0,0 is wrong but
		// drawable; `NaNpx` is neither.
		expect(toCanvasPoint(10, 10, { left: 0, top: 0, width: 0, height: 0 })).toEqual([0, 0]);
		expect(toCanvasPoint(10, 10, null)).toEqual([0, 0]);
		expect(toCanvasPoint(10, 10, undefined)).toEqual([0, 0]);
	});

	it('survives junk coordinates', () => {
		const p = toCanvasPoint(NaN, Infinity, RECT);
		expect(p.every(Number.isFinite)).toBe(true);
	});
});

describe('simplifyPoints', () => {
	it('drops samples closer than minDist to the last KEPT point', () => {
		// A slow drag emits many near-duplicates. Measuring against the last KEPT point
		// (not the last SEEN one) is what stops a creeping drag from sneaking every
		// sub-threshold step through.
		const dense: Point[] = [[0, 0], [1, 0], [2, 0], [3, 0], [10, 0], [11, 0], [20, 0]];
		expect(simplifyPoints(dense, 5)).toEqual([[0, 0], [10, 0], [20, 0]]);
	});

	it('always keeps the point where the pen lifted', () => {
		// Without this a quick flick loses its tail — the stroke would end short of
		// where the speaker actually stopped.
		const pts: Point[] = [[0, 0], [100, 0], [101, 0]];
		const out = simplifyPoints(pts, 50);
		expect(out[out.length - 1]).toEqual([101, 0]);
	});

	it('keeps a single point as a single point', () => {
		expect(simplifyPoints([[5, 5]], 4)).toEqual([[5, 5]]);
	});

	it('is total for junk input', () => {
		expect(simplifyPoints([], 4)).toEqual([]);
		expect(simplifyPoints(null as unknown as Point[], 4)).toEqual([]);
		// A NaN sample is repaired, not propagated.
		const out = simplifyPoints([[NaN, 0], [50, 50]] as Point[], 4);
		expect(out.flat().every(Number.isFinite)).toBe(true);
	});
});

describe('levelPoints — a highlighter is not a pen', () => {
	it('pins a wobbly swipe to one level band across its horizontal extent', () => {
		// The bug: the band faithfully followed the hand, so it sloped across the very line of
		// text it was meant to sit on — and the smoothing then bowed it as well.
		const wobble: Point[] = [[100, 200], [200, 206], [300, 194], [400, 200]];
		expect(levelPoints(wobble)).toEqual([[100, 200], [400, 200]]);
	});

	it('sits at the height you PRESSED at, and stays there as the hand drifts', () => {
		const drift: Point[] = [[0, 100], [100, 100], [200, 140], [300, 140]];
		expect(levelPoints(drift)).toEqual([[0, 100], [300, 100]]);
	});

	it('does not MOVE the band as the swipe grows — the bug the mean-y version had', () => {
		// This is the whole reason the y is anchored rather than averaged. Levelling runs on
		// every pointermove (so the live band is what you get), and with a mean the band slid up
		// and down under the cursor mid-swipe. Feed the prefixes of one gesture: the height must
		// never budge.
		const gesture: Point[] = [[0, 100], [50, 130], [100, 90], [150, 140], [200, 100]];
		const heights = gesture.map((_, i) => levelPoints(gesture.slice(0, i + 2))[0][1]);
		expect(new Set(heights)).toEqual(new Set([100])); // one height, from the first sample on
	});

	it('reduces to two points, so smoothPath cannot bow it', () => {
		const d = strokeD(levelPoints([[0, 50], [50, 55], [100, 45], [150, 50]]));
		expect(d).not.toContain('C '); // a straight segment, not a cubic
		expect(d).toBe('M 0 50 L 150 50');
	});

	it('leaves a gesture with no horizontal extent ALONE', () => {
		// A vertical swipe (down a column of code) or a tap would otherwise collapse to a
		// zero-length band — i.e. vanish. The rule is "level a swipe", not "forbid anything else".
		const vertical: Point[] = [[100, 100], [100, 300]];
		expect(levelPoints(vertical)).toEqual(vertical);
		expect(levelPoints([[5, 5]])).toEqual([[5, 5]]);
	});

	it('is total for junk', () => {
		expect(levelPoints([])).toEqual([]);
		expect(levelPoints(null as unknown as Point[])).toEqual([]);
		expect(levelPoints([[NaN, 0], [100, Infinity]] as Point[]).flat().every(Number.isFinite)).toBe(true);
	});
});

describe('snapAxis — the pen borrows a straight edge from Shift', () => {
	it('snaps a mostly-horizontal drag to a dead-level underline at the press Y', () => {
		// The intent is "underline this line of code": travel is far in X, a wobble in Y, so the
		// line lays flat at the height the pen went down (200), and grows sideways to the far X.
		const underline: Point[] = [[100, 200], [200, 208], [300, 194], [500, 205]];
		expect(snapAxis(underline)).toEqual([[100, 200], [500, 200]]);
	});

	it('snaps a mostly-vertical drag to a dead-plumb line at the press X', () => {
		// Dropping a plumb line down a column: travel is far in Y, so the line stands vertical at
		// the X the pen went down (100), reaching the far Y.
		const plumb: Point[] = [[100, 100], [106, 220], [94, 340], [103, 500]];
		expect(snapAxis(plumb)).toEqual([[100, 100], [100, 500]]);
	});

	it('anchors at the PRESS point and reaches the CURRENT one — a ruler, not a bounding box', () => {
		// The far end is where the pen is now (the last sample), not the extreme of the wander —
		// so a stroke that overshoots and comes back ends where the pen actually is.
		const overshoot: Point[] = [[0, 0], [600, 5], [400, 5]];
		expect(snapAxis(overshoot)).toEqual([[0, 0], [400, 0]]); // ends at 400, not the 600 peak
	});

	it('resolves a dead-diagonal drag to horizontal — ties go to the underline', () => {
		// |dx| === |dy|: one axis has to win rather than jitter, and an underline is the commoner
		// intent than a plumb line.
		expect(snapAxis([[0, 0], [300, 300]])).toEqual([[0, 0], [300, 0]]);
	});

	it('reduces to two points, so smoothPath cannot bow the ruler', () => {
		const d = strokeD(snapAxis([[10, 50], [100, 60], [200, 45], [300, 50]]));
		expect(d).toBe('M 10 50 L 300 50');
		expect(d).not.toContain('C '); // a straight segment, not a cubic
	});

	it('leaves a gesture with no travel ALONE — a tap is a dot, not a zero-length line', () => {
		// No dominant axis to snap to; collapsing it would make the dot vanish. Mirrors
		// levelPoints leaving an extent-less swipe be.
		expect(snapAxis([[100, 100], [100, 100]])).toEqual([[100, 100], [100, 100]]);
		expect(snapAxis([[5, 5]])).toEqual([[5, 5]]);
	});

	it('is total for junk — never a NaN ruler', () => {
		expect(snapAxis([])).toEqual([]);
		expect(snapAxis(null as unknown as Point[])).toEqual([]);
		expect(snapAxis([[NaN, 0], [100, Infinity]] as Point[]).flat().every(Number.isFinite)).toBe(true);
	});
});

describe('straightLine — an arrow is tail→head, free-angle', () => {
	it('reduces a wobbly drag to the press point and the lift point', () => {
		// Unlike snapAxis it does NOT project onto an axis: the arrow points wherever the hand
		// went. The wander in the middle is dropped; only where it started and ended survive.
		const drag: Point[] = [[100, 100], [150, 130], [220, 180], [300, 250]];
		expect(straightLine(drag)).toEqual([[100, 100], [300, 250]]);
	});

	it('ends where the pen is NOW, not at the extreme of an overshoot', () => {
		const overshoot: Point[] = [[0, 0], [400, 400], [250, 250]];
		expect(straightLine(overshoot)).toEqual([[0, 0], [250, 250]]);
	});

	it('leaves a gesture with no travel as its samples — a tap falls through to a dot', () => {
		expect(straightLine([[50, 50]])).toEqual([[50, 50]]);
	});

	it('is total for junk', () => {
		expect(straightLine([])).toEqual([]);
		expect(straightLine(null as unknown as Point[])).toEqual([]);
		expect(straightLine([[NaN, 0], [10, Infinity]] as Point[]).flat().every(Number.isFinite)).toBe(true);
	});
});

describe('arrowD — a straight shaft with a chevron head', () => {
	it('draws the shaft then a two-line chevron meeting at the head', () => {
		// A horizontal arrow: the shaft runs 0,0 → 100,0, then two barbs sweep BACK to the
		// head from behind it (x < 100) and splay symmetrically above and below the axis.
		const d = arrowD([[0, 0], [100, 0]]);
		expect(d.startsWith('M 0 0 L 100 0')).toBe(true);
		expect(d).toContain('L 100 0 L'); // the barbs both meet AT the head
		const nums = d.match(/-?\d+(?:\.\d+)?/g)!.map(Number);
		// Shaft (0,0)(100,0) then barb1 (bx,by) head (100,0) barb2 (bx,-by): symmetric in y.
		const b1y = nums[5];
		const b2y = nums[nums.length - 1];
		expect(b1y).toBe(-b2y); // the two barbs mirror across the shaft
		expect(nums[4]).toBeLessThan(100); // barbs sit BEHIND the head, not ahead of it
	});

	it('points the head wherever the arrow points — a downward arrow splays in x', () => {
		// Shaft straight down (0,0 → 0,100): now the barbs mirror across the vertical axis,
		// i.e. symmetric in X and both above the head (y < 100).
		const d = arrowD([[0, 0], [0, 100]]);
		expect(d.startsWith('M 0 0 L 0 100')).toBe(true);
		const seg = d.split(' M ')[1].split(' '); // "bx by L 0 100 L bx2 by2"
		expect(Number(seg[0])).toBe(-Number(seg[6])); // barbs mirror across the shaft in X
		expect(Number(seg[1])).toBeLessThan(100); // and sit behind the head
	});

	it('never lets the head outrun the shaft — a short arrow keeps a proportional head', () => {
		// headLen is clamped to the shaft length, so a stubby arrow does not grow a chevron
		// longer than the arrow itself. With a 10px shaft and a 36px default head, the barbs
		// cannot reach further than 10px back from the head.
		const d = arrowD([[0, 0], [10, 0]]);
		const nums = d.match(/-?\d+(?:\.\d+)?/g)!.map(Number);
		expect(nums[4]).toBeGreaterThanOrEqual(0); // barb x never runs back past the tail
	});

	it('renders a zero-length arrow as a dot, like strokeD — a mark, not nothing', () => {
		// A tap, or a press that never moved: there is no direction for a head, so it degrades
		// to the same dot strokeD paints for a lone point.
		expect(arrowD([[40, 60], [40, 60]])).toBe('M 40 60 L 40 60');
		expect(arrowD([[40, 60]])).toBe('M 40 60 L 40 60');
	});

	it('is empty only when there is genuinely nothing to draw', () => {
		expect(arrowD([])).toBe('');
		expect(arrowD(null as unknown as Point[])).toBe('');
	});

	it('never emits NaN', () => {
		expect(arrowD([[NaN, 0], [Infinity, 10]] as Point[])).not.toContain('NaN');
		expect(arrowD([[0, 0], [100, 0]], NaN)).not.toContain('NaN');
	});
});

describe('rectD — a box between two corners', () => {
	it('draws a closed rectangle, normalising the corners', () => {
		// Top-left then bottom-right, and the reverse, draw the SAME box — so dragging any
		// direction rings the same region.
		expect(rectD([[10, 10], [30, 40]])).toBe('M 10 10 L 30 10 L 30 40 L 10 40 Z');
		expect(rectD([[30, 40], [10, 10]])).toBe('M 10 10 L 30 10 L 30 40 L 10 40 Z');
	});

	it('is empty only when there is nothing to draw, and never emits NaN', () => {
		expect(rectD([])).toBe('');
		expect(rectD(null as unknown as [number, number][])).toBe('');
		expect(rectD([[NaN, 0], [10, Infinity]] as [number, number][])).not.toContain('NaN');
	});
});

describe('textBounds / hitText — a label is caught by its box', () => {
	it('anchors the box at the top-left and grows the width with the text', () => {
		const short = textBounds([100, 100], 'hi', 40);
		const long = textBounds([100, 100], 'a much longer label', 40);
		expect(short.x).toBe(100);
		expect(short.y).toBe(100);
		expect(long.w).toBeGreaterThan(short.w); // more characters → a wider box
		expect(short.h).toBeGreaterThan(0);
	});

	it('hits inside the box and misses outside it, with the tolerance as slop', () => {
		expect(hitText([110, 110], [100, 100], 'hello', 40)).toBe(true); // inside
		expect(hitText([500, 500], [100, 100], 'hello', 40)).toBe(false); // far away
		// Just past the right edge: outside with no slop, inside with a generous one.
		const b = textBounds([100, 100], 'hello', 40);
		expect(hitText([b.x + b.w + 5, 110], [100, 100], 'hello', 40, 0)).toBe(false);
		expect(hitText([b.x + b.w + 5, 110], [100, 100], 'hello', 40, 20)).toBe(true);
	});

	it('is total for junk anchors and sizes', () => {
		expect(typeof hitText([NaN, 0], [0, 0], 'x', NaN)).toBe('boolean');
		expect(textBounds([0, 0], 'x', 0).h).toBeGreaterThan(0); // a zero size floors to a visible box
	});
});

describe('sanitizeText — free user input, made safe to store and draw', () => {
	it('keeps ordinary text and trims-to-undefined the empty', () => {
		expect(sanitizeText('hello world')).toBe('hello world');
		expect(sanitizeText('   ')).toBeUndefined(); // all whitespace is nothing to show
		expect(sanitizeText('')).toBeUndefined();
		expect(sanitizeText(42)).toBeUndefined(); // not even a string
		expect(sanitizeText(null)).toBeUndefined();
	});

	it('strips control characters (including newlines) but keeps ordinary spaces', () => {
		expect(sanitizeText('a\nb\tc')).toBe('abc'); // newline + tab gone
		expect(sanitizeText('x\u0000y')).toBe('xy'); // a NUL between the letters, stripped
		expect(sanitizeText('two words')).toBe('two words'); // ordinary spaces are the speaker's
	});

	it('caps a runaway string at TEXT_MAX_LEN', () => {
		const huge = 'z'.repeat(TEXT_MAX_LEN + 500);
		expect(sanitizeText(huge)?.length).toBe(TEXT_MAX_LEN);
	});
});

describe('distanceToStroke / hitStroke — the eraser asks "am I on this mark?"', () => {
	it('is zero on the polyline and the perpendicular offset beside it', () => {
		expect(distanceToStroke([50, 0], [[0, 0], [100, 0]])).toBe(0);
		expect(distanceToStroke([50, 10], [[0, 0], [100, 0]])).toBe(10);
	});

	it('measures to the END, not the infinite line, past a segment', () => {
		// A point beyond the tip is as far as the tip, so an eraser off the end of a stroke does
		// not "hit" the line it would extend to.
		expect(distanceToStroke([150, 0], [[0, 0], [100, 0]])).toBe(50);
	});

	it('takes the nearest of several segments', () => {
		// An L-shaped stroke: the point is closest to the vertical leg, 10 px away.
		expect(distanceToStroke([110, 50], [[0, 0], [100, 0], [100, 100]])).toBe(10);
	});

	it('is infinitely far from an empty stroke, and measures to a lone dot', () => {
		expect(distanceToStroke([0, 0], [])).toBe(Infinity);
		expect(distanceToStroke([3, 4], [[0, 0]])).toBe(5); // 3-4-5
	});

	it('is total — junk coordinates are repaired, never propagated', () => {
		expect(Number.isFinite(distanceToStroke([NaN, 0], [[0, 0], [10, 0]]))).toBe(true);
		expect(distanceToStroke([0, 0], null as unknown as [number, number][])).toBe(Infinity);
	});

	it('hits within the tolerance and misses beyond it', () => {
		expect(hitStroke([50, 10], [[0, 0], [100, 0]], 17)).toBe(true);
		expect(hitStroke([50, 30], [[0, 0], [100, 0]], 17)).toBe(false);
	});

	it('reads a negative or NaN tolerance as 0 — a hit only dead on the ink', () => {
		expect(hitStroke([50, 0], [[0, 0], [100, 0]], -5)).toBe(true); // on the line
		expect(hitStroke([50, 0.5], [[0, 0], [100, 0]], -5)).toBe(false); // just off it
		expect(hitStroke([50, 0], [[0, 0], [100, 0]], NaN)).toBe(true);
	});

	it('never hits an empty stroke, however generous the tolerance', () => {
		expect(hitStroke([0, 0], [], 1000)).toBe(false);
	});
});

describe('clampBarPos / barPosCodec — a bar you can always get back', () => {
	it('keeps the bar inside the canvas', () => {
		expect(clampBarPos(-50, -50, 400, 60)).toEqual({ x: 0, y: 0 });
		expect(clampBarPos(9999, 9999, 400, 60)).toEqual({ x: 1520, y: 1020 });
		expect(clampBarPos(300, 400, 400, 60)).toEqual({ x: 300, y: 400 });
	});

	it('clamps a bar WIDER than the canvas to 0, not to a negative bound', () => {
		// Otherwise a narrow portrait deck would shove the bar off the opposite edge.
		expect(clampBarPos(10, 10, 3000, 60, 1080, 1920)).toEqual({ x: 0, y: 10 });
	});

	it('never parks the bar at NaN — which would be off-screen and unrecoverable', () => {
		const p = clampBarPos(NaN, Infinity, NaN, NaN);
		expect(Number.isFinite(p.x) && Number.isFinite(p.y)).toBe(true);
	});

	it('reads a corrupt stored position as "not dragged" rather than as garbage', () => {
		const c = barPosCodec();
		expect(c.read('{"x":300,"y":400}')).toEqual({ x: 300, y: 400 });
		expect(c.read('{"x":"left","y":4}')).toBe(null);
		expect(c.read('null')).toBe(null);
		expect(c.read('not json')).toBe(null);
	});

	it('round-trips a dragged position', () => {
		const c = barPosCodec();
		expect(c.read(c.write({ x: 12, y: 34 }))).toEqual({ x: 12, y: 34 });
	});
});

describe('strokeD', () => {
	it('smooths two or more points through drawCore (a cubic path)', () => {
		const d = strokeD([[0, 0], [10, 10], [20, 0]]);
		expect(d.startsWith('M 0 0')).toBe(true);
		expect(d).toContain('C '); // Catmull-Rom → cubic Béziers, same as Polyline
	});

	it('renders a lone point as a zero-length line — a dot, not nothing', () => {
		// The case smoothPath cannot serve (it needs a segment and returns ''), and it is
		// exactly what a tap produces. Drawing nothing here reads as a broken pen.
		expect(strokeD([[40, 60]])).toBe('M 40 60 L 40 60');
	});

	it('is empty only when there is genuinely nothing to draw', () => {
		expect(strokeD([])).toBe('');
		expect(strokeD(null as unknown as Point[])).toBe('');
	});

	it('never emits NaN', () => {
		expect(strokeD([[NaN, 0], [Infinity, 10]] as Point[])).not.toContain('NaN');
	});
});

describe('strokeWidth', () => {
	it('gives the highlighter a band and the pen a line', () => {
		expect(strokeWidth('pen')).toBe(6);
		expect(strokeWidth('highlighter')).toBe(34);
		expect(strokeWidth('highlighter')).toBeGreaterThan(strokeWidth('pen'));
	});

	it('draws a line, an arrow and a rectangle at the pen width — a stroke, not a band', () => {
		expect(strokeWidth('arrow')).toBe(strokeWidth('pen'));
		expect(strokeWidth('line')).toBe(strokeWidth('pen'));
		expect(strokeWidth('rectangle')).toBe(strokeWidth('pen'));
	});

	it('falls back to a visible width rather than a zero/NaN one', () => {
		expect(strokeWidth('pen', 0)).toBe(1);
		expect(strokeWidth('pen', NaN)).toBe(6);
	});
});

describe('sanitizeStrokes', () => {
	it('accepts a well-formed list off the wire', () => {
		const out = sanitizeStrokes([{ id: 'a', tool: 'highlighter', points: [[0, 0], [1, 1]] }]);
		expect(out).toEqual([{ id: 'a', tool: 'highlighter', points: [[0, 0], [1, 1]] }]);
	});

	it('drops strokes it cannot draw, rather than guessing geometry', () => {
		// A malformed stroke has no "reasonable" shape to invent, and drawing a guess over
		// the speaker's slide is worse than drawing nothing.
		const out = sanitizeStrokes([
			{ id: 'ok', tool: 'pen', points: [[0, 0], [1, 1]] },
			{ id: 'no-points', tool: 'pen' },
			{ id: 'empty', tool: 'pen', points: [] },
			null,
			'nope',
			42
		]);
		expect(out).toHaveLength(1);
		expect(out[0].id).toBe('ok');
	});

	it('falls back to the pen for an unknown tool instead of dropping the stroke', () => {
		// A tool is only a paint choice — losing the mark over it would be a bad trade.
		const out = sanitizeStrokes([{ id: 'x', tool: 'crayon', points: [[0, 0], [1, 1]] }]);
		expect(out[0].tool).toBe('pen');
	});

	it('preserves every known tool off the wire, so a mark survives a reload and the mirror', () => {
		// The trap the pen/highlighter-only coercion had: an arrow (or a line) read back from
		// localStorage would come back a pen and lose its head. Every known tool must round-trip.
		const roundTrip = (tool: string) =>
			sanitizeStrokes([{ id: 't', tool, points: [[0, 0], [1, 1]] }])[0].tool;
		expect(roundTrip('line')).toBe('line');
		expect(roundTrip('arrow')).toBe('arrow');
		expect(roundTrip('rectangle')).toBe('rectangle');
		expect(roundTrip('highlighter')).toBe('highlighter');
		expect(roundTrip('pen')).toBe('pen');
	});

	it('carries a TEXT mark\u2019s words and size, and DROPS a text mark with no words', () => {
		// A label is nothing without its string, so a text mark whose content fails sanitation is
		// dropped rather than kept blank; a good one keeps its text and size.
		const ok = sanitizeStrokes([{ id: 't', tool: 'text', points: [[10, 10]], text: 'hi', size: 40 }]);
		expect(ok).toHaveLength(1);
		expect(ok[0]).toMatchObject({ tool: 'text', text: 'hi', size: 40 });
		expect(sanitizeStrokes([{ id: 'x', tool: 'text', points: [[10, 10]] }])).toHaveLength(0);
		expect(sanitizeStrokes([{ id: 'x', tool: 'text', points: [[10, 10]], text: '   ' }])).toHaveLength(0);
	});

	it('repairs NaN coordinates and names an unnamed stroke', () => {
		const out = sanitizeStrokes([{ points: [[NaN, 2], [3, 4]] }]);
		expect(out[0].id).toBeTruthy();
		expect(out[0].points.flat().every(Number.isFinite)).toBe(true);
	});

	it('is total for a payload that is not a list at all', () => {
		expect(sanitizeStrokes(null)).toEqual([]);
		expect(sanitizeStrokes({ strokes: [] })).toEqual([]);
		expect(sanitizeStrokes('[]')).toEqual([]);
	});
});

describe('isColor — the gate on what may reach an inline style', () => {
	it('accepts the colour forms a swatch or a picker can produce', () => {
		expect(isColor('#fff')).toBe(true);
		expect(isColor('#F0A33E')).toBe(true);
		expect(isColor('#F0A33E80')).toBe(true);
		expect(isColor('rgb(1, 2, 3)')).toBe(true);
		expect(isColor('rgba(1,2,3,0.5)')).toBe(true);
		expect(isColor('hsl(20 100% 50%)')).toBe(true);
	});

	it('refuses anything that could break OUT of the style it lands in', () => {
		// The value arrives from localStorage, which another tab — or a console — may have
		// written, and it is interpolated into `style="stroke: …"`. A `}` in the wrong place
		// there is a CSS injection, so this is an allow-list, not a "non-empty string" check.
		expect(isColor('red; } body { display:none')).toBe(false);
		expect(isColor('url(javascript:alert(1))')).toBe(false);
		expect(isColor('expression(alert(1))')).toBe(false);
		expect(isColor('')).toBe(false);
		expect(isColor(null)).toBe(false);
		expect(isColor(42)).toBe(false);
		// Even a plausible-looking keyword is refused — the swatches emit hex, so nothing is lost.
		expect(isColor('rebeccapurple')).toBe(false);
	});

	it('strips an unusable colour from a stroke rather than dropping the mark', () => {
		const out = sanitizeStrokes([{ id: 'x', tool: 'pen', points: [[0, 0], [1, 1]], color: 'red;}evil{' }]);
		expect(out).toHaveLength(1);
		expect(out[0].color).toBeUndefined(); // falls back to the theme token
	});

	it('keeps a good colour', () => {
		const out = sanitizeStrokes([{ id: 'x', tool: 'pen', points: [[0, 0], [1, 1]], color: '#E5484D' }]);
		expect(out[0].color).toBe('#E5484D');
	});
});

describe('sanitizeInkBook', () => {
	const ok = { strokes: [{ id: 'a', tool: 'pen', points: [[0, 0], [1, 1]] }], ts: 123 };

	it('accepts a well-formed book', () => {
		const out = sanitizeInkBook({ '/slides/a.html': ok });
		expect(out['/slides/a.html'].strokes).toHaveLength(1);
		expect(out['/slides/a.html'].ts).toBe(123);
	});

	it('drops a slide whose strokes are all unusable, rather than keeping an empty entry', () => {
		// Otherwise the book accretes a key per slide ever visited and never shrinks, and
		// "has this slide got ink?" stops being answerable by looking.
		const out = sanitizeInkBook({ '/a': { strokes: [], ts: 1 }, '/b': { strokes: 'nope' }, '/c': ok });
		expect(Object.keys(out)).toEqual(['/c']);
	});

	it('repairs a missing or junk timestamp to 0 (which reads as stale)', () => {
		const out = sanitizeInkBook({ '/a': { strokes: ok.strokes } });
		expect(out['/a'].ts).toBe(0);
	});

	it('is total for anything that is not a book', () => {
		expect(sanitizeInkBook(null)).toEqual({});
		expect(sanitizeInkBook([1, 2])).toEqual({});
		expect(sanitizeInkBook('{}')).toEqual({});
		expect(sanitizeInkBook(7)).toEqual({});
	});
});

describe('inkBookCodec', () => {
	it('round-trips a book', () => {
		const c = inkBookCodec();
		const book = { '/a': { strokes: [{ id: 'x', tool: 'pen' as const, points: [[0, 0], [1, 1]] as Point[] }], ts: 9 } };
		expect(c.read(c.write(book))).toEqual(book);
	});

	it('refuses JSON that parses but is not a book — the jsonCodec trap', () => {
		// JSON.parse happily returns an array or a string, either of which would poison every
		// subscriber downstream. Validated on the way in, exactly as booleanCodec does.
		const c = inkBookCodec();
		expect(c.read('[1,2,3]')).toEqual({});
		expect(c.read('"hello"')).toEqual({});
		expect(c.read('not json at all')).toBe(null); // → the store keeps its initial
	});
});

describe('isStaleInk / inkAgeText', () => {
	const DAY = 24 * 60 * 60 * 1000;
	const NOW = 1_000 * DAY;
	const ink = (ts: number) => ({ strokes: [{ id: 'a', tool: 'pen' as const, points: [[0, 0], [1, 1]] as Point[] }], ts });

	it('is stale past the threshold and fresh before it', () => {
		expect(isStaleInk(ink(NOW - 3 * DAY), NOW)).toBe(true);
		expect(isStaleInk(ink(NOW - 1000), NOW)).toBe(false);
	});

	it('never nags about a slide with no ink — a prompt about nothing is just noise', () => {
		expect(isStaleInk({ strokes: [], ts: 0 }, NOW)).toBe(false);
		expect(isStaleInk(undefined, NOW)).toBe(false);
		expect(isStaleInk(null, NOW)).toBe(false);
	});

	it('treats undated ink as stale — we cannot date it, and that is the point', () => {
		expect(isStaleInk(ink(0), NOW)).toBe(true);
	});

	it('honours a deck-supplied threshold', () => {
		const hour = 60 * 60 * 1000;
		expect(isStaleInk(ink(NOW - 2 * hour), NOW, hour)).toBe(true);
		expect(isStaleInk(ink(NOW - 2 * hour), NOW, DAY)).toBe(false);
	});

	it('is total for a junk clock', () => {
		expect(typeof isStaleInk(ink(NaN), NaN, NaN)).toBe('boolean');
	});

	it('says WHEN in words a speaker can act on', () => {
		expect(inkAgeText(NOW - 3 * DAY, NOW)).toBe('3 days ago');
		expect(inkAgeText(NOW - DAY, NOW)).toBe('1 day ago');
		expect(inkAgeText(NOW - 5 * 60 * 60 * 1000, NOW)).toBe('5 hours ago');
		expect(inkAgeText(NOW - 2 * 60 * 1000, NOW)).toBe('2 minutes ago');
		expect(inkAgeText(NOW, NOW)).toBe('just now');
	});

	it('does not date undated ink from the epoch', () => {
		// The bug this pins: ts=0 fell through the arithmetic and rendered as "20138 days
		// ago" — a fact about 1970, not about the ink. Say the one true thing we know.
		expect(inkAgeText(0, NOW)).toBe('an earlier session');
		expect(inkAgeText(NaN, NOW)).toBe('an earlier session'); // total, never "NaN days ago"
	});
});

describe('resolveCanAnnotate — the precedence, one tier shorter than ADJUST', () => {
	it('offers the pen in dev no matter what', () => {
		expect(resolveCanAnnotate(true, false, false)).toBe(true);
	});

	it("lets the speaker's sticky flag outrank the deck, both ways", () => {
		expect(resolveCanAnnotate(false, true, false)).toBe(true);
		expect(resolveCanAnnotate(false, false, true)).toBe(false);
	});

	it('falls through to the deck when nothing was recorded', () => {
		expect(resolveCanAnnotate(false, null, true)).toBe(true);
		expect(resolveCanAnnotate(false, null, false)).toBe(false);
	});

	it("takes no input from the slide — the tool is the speaker's, not the page's", () => {
		// The whole point of the shorter precedence: there is no `declared` parameter to
		// pass, so no slide can arm or disarm the pen out from under the speaker.
		expect(resolveCanAnnotate.length).toBe(3);
	});
});

describe('readAnnotateParam / readSticky', () => {
	const q = (s: string) => new URLSearchParams(s);

	it('reads the flag in every spelling', () => {
		expect(readAnnotateParam(q('annotate'))).toBe(true);
		expect(readAnnotateParam(q('annotate=on'))).toBe(true);
		expect(readAnnotateParam(q('annotate=1'))).toBe(true);
		expect(readAnnotateParam(q('annotate=off'))).toBe(false);
		expect(readAnnotateParam(q('annotate=false'))).toBe(false);
		expect(readAnnotateParam(q('annotate=0'))).toBe(false);
	});

	it('treats an ABSENT flag as "nothing was said", not as off', () => {
		// The nav links carry no query, so paging must not revoke a pen the speaker armed
		// three slides ago.
		expect(readAnnotateParam(q(''))).toBe(null);
		expect(readAnnotateParam(q('layout=on'))).toBe(null);
		expect(readAnnotateParam(null)).toBe(null);
	});

	it('lets a corrupt sticky value fall through rather than veto the deck', () => {
		expect(readSticky('true')).toBe(true);
		expect(readSticky('false')).toBe(false);
		expect(readSticky('yes')).toBe(null);
		expect(readSticky(null)).toBe(null);
		// …so a garbage byte leaves a deck that ships the pen still shipping it.
		expect(resolveCanAnnotate(false, readSticky('garbage'), true)).toBe(true);
	});
});
