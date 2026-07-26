// DOM tests for the ink overlay: it draws, it REMEMBERS (per slide, across reloads), it
// undoes and resets, it offers to clear ink that has gone stale — and it is INERT with the
// pen down, which is what keeps a tool nobody armed from eating clicks on every slide.
import { render, cleanup, fireEvent, screen } from '@testing-library/svelte';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { get } from 'svelte/store';
import { tick } from 'svelte';
import AnnotateHost from './AnnotateHost.svelte';
import {
	annotationMode,
	canAnnotate,
	annotateTool,
	annotateColor,
	inkBook,
	inkPath,
	strokes,
	staleDismissed,
	inkStaleAfterMs,
	barPos,
	setInkPath,
	resetAllInk
} from '../src/lib/stores/annotation';
import { INK_STALE_AFTER_MS } from '../src/lib/annotate/annotateCore';

const SLIDE = '/slides/intro.html';
const OTHER = '/slides/next.html';

// The overlay is laid out at canvas size and then CSS-scaled; jsdom does no layout, so every
// rect is zero and toCanvasPoint would correctly (but uselessly) fold every stroke onto the
// origin. Stub the one measurement it makes: the surface on screen at half size, so client
// (x, y) maps to canvas (2x, 2y) and the assertions below can say where the ink landed.
function surfaceAt(): SVGSVGElement {
	const svg = document.querySelector('.annot-surface') as SVGSVGElement;
	svg.getBoundingClientRect = () =>
		({ left: 0, top: 0, width: 960, height: 540, right: 960, bottom: 540, x: 0, y: 0 }) as DOMRect;
	return svg;
}

/** A pointer gesture. jsdom has no PointerEvent, but the handlers only read
    clientX/clientY/button/pointerId — all of which a MouseEvent carries. */
function stroke(svg: Element, points: [number, number][]): void {
	const at = (type: string, [clientX, clientY]: [number, number]) =>
		fireEvent(svg, new MouseEvent(type, { clientX, clientY, bubbles: true, button: 0 }));

	at('pointerdown', points[0]);
	for (const p of points.slice(1)) at('pointermove', p);
	at('pointerup', points[points.length - 1]);
}

/** The same gesture with Shift held — the pen's straight-edge modifier (snapAxis). */
function shiftStroke(svg: Element, points: [number, number][]): void {
	const at = (type: string, [clientX, clientY]: [number, number]) =>
		fireEvent(svg, new MouseEvent(type, { clientX, clientY, bubbles: true, button: 0, shiftKey: true }));

	at('pointerdown', points[0]);
	for (const p of points.slice(1)) at('pointermove', p);
	at('pointerup', points[points.length - 1]);
}

/** Move the pointer over the surface without a button down — drives the eraser's hover
    highlight (what a delete right here WOULD take). */
function hover(svg: Element, [clientX, clientY]: [number, number]): void {
	fireEvent(svg, new MouseEvent('pointermove', { clientX, clientY, bubbles: true }));
}

/** A single eraser tap at a point: press and release, no drag. */
function eraseAt(svg: Element, [clientX, clientY]: [number, number]): void {
	fireEvent(svg, new MouseEvent('pointerdown', { clientX, clientY, bubbles: true, button: 0 }));
	fireEvent(svg, new MouseEvent('pointerup', { clientX, clientY, bubbles: true, button: 0 }));
}

beforeEach(() => {
	localStorage.clear();
	resetAllInk();
	canAnnotate.set(true);
	annotationMode.set(false);
	annotateTool.set('pen');
	annotateColor.set({ pen: null, line: null, arrow: null, rectangle: null, highlighter: null, text: null });
	inkStaleAfterMs.set(INK_STALE_AFTER_MS);
	barPos.set(null);
	inkPath.set('');
	setInkPath(SLIDE);
	staleDismissed.set(false);
});

afterEach(cleanup);

describe('Annotate — armed', () => {
	beforeEach(() => annotationMode.set(true));

	it('turns a pointer gesture into a smoothed stroke in canvas pixels', () => {
		render(AnnotateHost);
		stroke(surfaceAt(), [[100, 100], [200, 150], [300, 100]]);

		const list = get(strokes);
		expect(list).toHaveLength(1);
		expect(list[0].tool).toBe('pen');
		// Half-size surface → client 100,100 is canvas 200,200.
		expect(list[0].points[0]).toEqual([200, 200]);

		const path = document.querySelector('.annot-stroke');
		expect(path?.getAttribute('d')).toContain('M 200 200');
		expect(path?.getAttribute('stroke-width')).toBe('6');
	});

	it('files the ink under the SLIDE, and survives paging away and back', () => {
		// The reversal: ink used to die on navigation. Now it is a book, and paging just turns
		// the page — the drawing is still there when you come back.
		render(AnnotateHost);
		stroke(surfaceAt(), [[10, 10], [60, 60]]);
		expect(get(strokes)).toHaveLength(1);

		setInkPath(OTHER);
		expect(get(strokes)).toHaveLength(0); // a different slide, a clean canvas

		setInkPath(SLIDE);
		expect(get(strokes)).toHaveLength(1); // …and back again
		expect(get(inkBook)[SLIDE].strokes).toHaveLength(1);
	});

	it('writes the ink to localStorage, which is also how the other window hears it', () => {
		render(AnnotateHost);
		stroke(surfaceAt(), [[10, 10], [60, 60]]);

		const raw = localStorage.getItem('geekpresent:ink');
		expect(raw).toBeTruthy();
		const book = JSON.parse(raw!);
		expect(book[SLIDE].strokes[0].points[0]).toEqual([20, 20]);
		expect(book[SLIDE].ts).toBeGreaterThan(0); // stamped, so it can later go stale
	});

	it('paints the highlighter as a fat band, not a line', () => {
		render(AnnotateHost);
		annotateTool.set('highlighter');
		stroke(surfaceAt(), [[10, 10], [200, 10]]);

		const path = document.querySelector('.annot-stroke');
		expect(path?.classList.contains('highlighter')).toBe(true);
		expect(Number(path?.getAttribute('stroke-width'))).toBe(34);
	});

	it('keeps a highlighter swipe LEVEL, however wobbly the hand was', () => {
		// A highlighter is not a pen: the band belongs on the row you swiped, not sloping along
		// with your wrist. Client y wobbles 50→60→45; canvas y is double that.
		render(AnnotateHost);
		annotateTool.set('highlighter');
		stroke(surfaceAt(), [[10, 50], [100, 60], [200, 45], [300, 50]]);

		const pts = get(strokes)[0].points;
		expect(pts).toHaveLength(2); // reduced to a level segment…
		expect(pts[0][1]).toBe(pts[1][1]); // …dead level…
		expect(document.querySelector('.annot-stroke')?.getAttribute('d')).not.toContain('C ');
	});

	it('does NOT level the pen — freehand stays freehand', () => {
		render(AnnotateHost);
		annotateTool.set('pen');
		stroke(surfaceAt(), [[10, 50], [100, 60], [200, 45], [300, 50]]);

		const pts = get(strokes)[0].points;
		expect(pts.length).toBeGreaterThan(2);
		expect(document.querySelector('.annot-stroke')?.getAttribute('d')).toContain('C ');
	});

	it('snaps a Shift-held pen stroke to a dead-level underline', () => {
		// Shift is the pen's straight-edge: a wobbly, mostly-horizontal drag commits as a ruler.
		// Client y wobbles 50→60→45→50; canvas is double, and horizontal travel wins.
		render(AnnotateHost);
		annotateTool.set('pen');
		shiftStroke(surfaceAt(), [[10, 50], [100, 60], [200, 45], [300, 50]]);

		const pts = get(strokes)[0].points;
		expect(pts).toHaveLength(2); // reduced to a ruler…
		expect(pts[0][1]).toBe(pts[1][1]); // …dead level, at the height the pen went down
		expect(document.querySelector('.annot-stroke')?.getAttribute('d')).not.toContain('C ');
	});

	it('snaps a Shift-held vertical drag to a dead-plumb line', () => {
		// The other axis: travel is far in Y, so the ruler stands vertical at the press X.
		render(AnnotateHost);
		annotateTool.set('pen');
		shiftStroke(surfaceAt(), [[50, 10], [56, 100], [45, 200], [52, 300]]);

		const pts = get(strokes)[0].points;
		expect(pts).toHaveLength(2);
		expect(pts[0][0]).toBe(pts[1][0]); // dead vertical, at the X the pen went down (canvas 100)
		expect(pts[0][0]).toBe(100);
	});

	it('leaves the pen freehand when snapPen is off, Shift or no Shift', () => {
		// The opt-out: a deck that wants a purely freehand pen sets snapPen={false}, and Shift
		// becomes inert rather than straightening the mark.
		render(AnnotateHost, { props: { snapPen: false } });
		annotateTool.set('pen');
		shiftStroke(surfaceAt(), [[10, 50], [100, 60], [200, 45], [300, 50]]);

		const pts = get(strokes)[0].points;
		expect(pts.length).toBeGreaterThan(2);
		expect(document.querySelector('.annot-stroke')?.getAttribute('d')).toContain('C ');
	});

	it('draws a LINE as a dead-straight two-point segment, no head, whatever the hand did', () => {
		// A line is an arrow without the chevron: however the drag wandered, it commits as a
		// straight tail→head segment, and strokeD paints exactly one `M … L …` (no curve, no
		// second sub-path for a head).
		render(AnnotateHost);
		annotateTool.set('line');
		stroke(surfaceAt(), [[10, 10], [150, 40], [300, 200]]);

		const list = get(strokes);
		expect(list).toHaveLength(1);
		expect(list[0].tool).toBe('line');
		expect(list[0].points).toHaveLength(2); // tail and head only — the wander is dropped

		const d = document.querySelector('.annot-stroke')?.getAttribute('d') ?? '';
		expect(d).toBe('M 20 20 L 600 400'); // one straight segment, in canvas px (double)
		expect(d).not.toContain('C '); // not smoothed
		expect(d.split('M ')).toHaveLength(2); // one sub-path — no arrowhead
		expect(document.querySelector('.annot-stroke')?.classList.contains('highlighter')).toBe(false);
	});

	it('snaps a Shift-held line to a dead-straight axis, like the pen and the arrow', () => {
		render(AnnotateHost);
		annotateTool.set('line');
		shiftStroke(surfaceAt(), [[10, 50], [100, 60], [300, 45]]);

		const pts = get(strokes)[0].points;
		expect(pts).toHaveLength(2);
		expect(pts[0][1]).toBe(pts[1][1]); // dead level — tail and head share a Y
	});

	it('draws an ARROW as a straight shaft with a chevron head, whatever the hand did', () => {
		// The arrow is not freehand: however the drag wandered, it commits as a straight
		// tail→head line, and renders a shaft plus a two-line head (a second M sub-path).
		render(AnnotateHost);
		annotateTool.set('arrow');
		stroke(surfaceAt(), [[10, 10], [150, 40], [300, 200]]);

		const list = get(strokes);
		expect(list).toHaveLength(1);
		expect(list[0].tool).toBe('arrow');
		expect(list[0].points).toHaveLength(2); // tail and head only — the wander is dropped

		const d = document.querySelector('.annot-stroke')?.getAttribute('d') ?? '';
		expect(d.startsWith('M 20 20 L 600 400')).toBe(true); // shaft, in canvas px (double)
		expect(d.split('M ')).toHaveLength(3); // a shaft sub-path AND a head sub-path
		expect(d).toContain('L 600 400 L'); // the two barbs meet at the head
		expect(Number(document.querySelector('.annot-stroke')?.getAttribute('stroke-width'))).toBe(6);
	});

	it('is NOT a highlighter — an arrow paints opaque, like the pen', () => {
		render(AnnotateHost);
		annotateTool.set('arrow');
		stroke(surfaceAt(), [[10, 10], [200, 10]]);
		expect(document.querySelector('.annot-stroke')?.classList.contains('highlighter')).toBe(false);
	});

	it('snaps a Shift-held arrow to a dead-straight axis, like the pen', () => {
		// The arrow borrows the pen's straight-edge: a mostly-horizontal Shift-drag lies flat
		// at the press Y, so the arrow points dead sideways.
		render(AnnotateHost);
		annotateTool.set('arrow');
		shiftStroke(surfaceAt(), [[10, 50], [100, 60], [300, 45]]);

		const pts = get(strokes)[0].points;
		expect(pts).toHaveLength(2);
		expect(pts[0][1]).toBe(pts[1][1]); // dead level — tail and head share a Y
	});

	it('lights the stroke under the eraser, and clears the light when the pointer moves off', () => {
		// The hover preview: the mark a delete right here WOULD take gets the `erasing` class,
		// so the speaker deletes exactly the one they meant. Pen mark runs along canvas y=200.
		render(AnnotateHost);
		stroke(surfaceAt(), [[100, 100], [140, 100]]);
		expect(get(strokes)).toHaveLength(1);

		annotateTool.set('eraser');
		hover(surfaceAt(), [120, 100]); // client 120,100 → canvas 240,200 — on the mark
		expect(document.querySelector('.annot-stroke')?.classList.contains('erasing')).toBe(true);

		hover(surfaceAt(), [400, 400]); // far off it
		expect(document.querySelector('.annot-stroke')?.classList.contains('erasing')).toBe(false);
	});

	it('erases the whole stroke under an eraser tap', () => {
		render(AnnotateHost);
		stroke(surfaceAt(), [[100, 100], [140, 100]]);
		expect(get(strokes)).toHaveLength(1);

		annotateTool.set('eraser');
		eraseAt(surfaceAt(), [120, 100]);
		expect(get(strokes)).toHaveLength(0);
		expect(document.querySelectorAll('.annot-stroke')).toHaveLength(0);
	});

	it('wipes every stroke the eraser is dragged across', () => {
		render(AnnotateHost);
		const svg = surfaceAt();
		stroke(svg, [[100, 100], [140, 100]]); // canvas y=200
		stroke(svg, [[100, 140], [140, 140]]); // canvas y=280
		expect(get(strokes)).toHaveLength(2);

		annotateTool.set('eraser');
		const e = surfaceAt();
		// Press on the first mark, then drag down onto the second before releasing.
		fireEvent(e, new MouseEvent('pointerdown', { clientX: 120, clientY: 100, bubbles: true, button: 0 }));
		fireEvent(e, new MouseEvent('pointermove', { clientX: 120, clientY: 140, bubbles: true, button: 0 }));
		fireEvent(e, new MouseEvent('pointerup', { clientX: 120, clientY: 140, bubbles: true, button: 0 }));
		expect(get(strokes)).toHaveLength(0);
	});

	it('lights only the TOP-MOST stroke, not the whole stack under the pointer', () => {
		// Two marks stacked on the same spot: the preview lights just the one painted last (on
		// top), because that is the only one a click will take.
		render(AnnotateHost);
		const svg = surfaceAt();
		stroke(svg, [[100, 100], [140, 100]]);
		stroke(svg, [[100, 100], [140, 100]]);

		annotateTool.set('eraser');
		hover(surfaceAt(), [120, 100]);
		expect(document.querySelectorAll('.annot-stroke')).toHaveLength(2);
		expect(document.querySelectorAll('.annot-stroke.erasing')).toHaveLength(1); // just the top one
	});

	it('deletes only the TOP-MOST stroke under a click, leaving the ones beneath', () => {
		// A click takes the mark painted last (on top) and leaves the earlier one, rather than
		// clearing the whole stack in one tap.
		render(AnnotateHost);
		const svg = surfaceAt();
		stroke(svg, [[100, 100], [140, 100]]); // A, drawn first → underneath
		stroke(svg, [[100, 100], [140, 100]]); // B, drawn second → on top
		const [aId, bId] = get(strokes).map((s) => s.id);
		expect(aId).not.toBe(bId);

		annotateTool.set('eraser');
		eraseAt(surfaceAt(), [120, 100]);

		const remaining = get(strokes);
		expect(remaining).toHaveLength(1);
		expect(remaining[0].id).toBe(aId); // B (the top-most) went; A survives
	});

	it('does NOT draw — an eraser gesture over empty canvas leaves the ink untouched', () => {
		// The eraser removes; it never adds. A press-and-release on nothing must not commit a
		// dot the way the pen would.
		render(AnnotateHost);
		stroke(surfaceAt(), [[100, 100], [140, 100]]);
		expect(get(strokes)).toHaveLength(1);

		annotateTool.set('eraser');
		eraseAt(surfaceAt(), [400, 400]); // misses the mark entirely
		expect(get(strokes)).toHaveLength(1); // nothing deleted — and nothing added
	});

	it('steps the colour swatches aside while the eraser is armed', async () => {
		render(AnnotateHost, { props: { inkColors: [null, '#E5484D'] } });
		expect(screen.queryByLabelText('Theme colour')).not.toBeNull();

		await fireEvent.click(screen.getByLabelText('Erase'));
		expect(get(annotateTool)).toBe('eraser');
		expect(screen.getByLabelText('Erase').getAttribute('aria-pressed')).toBe('true');
		expect(screen.queryByLabelText('Theme colour')).toBeNull(); // no colour to pick when deleting
	});

	it('draws a RECTANGLE as a closed box between two corners', () => {
		render(AnnotateHost);
		annotateTool.set('rectangle');
		stroke(surfaceAt(), [[50, 50], [100, 80], [150, 120]]); // drag corner to corner

		const list = get(strokes);
		expect(list).toHaveLength(1);
		expect(list[0].tool).toBe('rectangle');
		expect(list[0].points).toHaveLength(2); // two corners only

		const d = document.querySelector('.annot-stroke')?.getAttribute('d') ?? '';
		expect(d.startsWith('M 100 100')).toBe(true); // top-left corner, canvas px (client 50,50 → 100,100)
		expect(d.endsWith('Z')).toBe(true); // a closed box
		expect(d).not.toContain('C '); // not smoothed
	});

	it('offers the tools as icon buttons with accessible names, and picks on click', async () => {
		render(AnnotateHost);
		for (const label of ['Pen', 'Line', 'Arrow', 'Rectangle', 'Highlight', 'Text', 'Erase']) {
			expect(screen.getByLabelText(label)).not.toBeNull();
		}
		await fireEvent.click(screen.getByLabelText('Rectangle'));
		expect(get(annotateTool)).toBe('rectangle');
	});

	it('places a TEXT label: click, type, Enter commits it as an SVG <text>', async () => {
		render(AnnotateHost);
		annotateTool.set('text');
		await fireEvent(
			surfaceAt(),
			new MouseEvent('pointerdown', { clientX: 100, clientY: 100, bubbles: true, button: 0 })
		);

		const input = document.querySelector('.annot-text-input') as HTMLInputElement;
		expect(input).not.toBeNull();
		await fireEvent.input(input, { target: { value: 'Hello' } });
		await fireEvent.keyDown(input, { key: 'Enter' });

		const list = get(strokes);
		expect(list).toHaveLength(1);
		expect(list[0].tool).toBe('text');
		expect(list[0].text).toBe('Hello');
		expect(list[0].points[0]).toEqual([200, 200]); // client 100,100 → canvas 200,200
		expect(document.querySelector('.annot-text')?.textContent).toBe('Hello');
	});

	it('cancels a half-typed label on Escape, committing nothing', async () => {
		render(AnnotateHost);
		annotateTool.set('text');
		await fireEvent(
			surfaceAt(),
			new MouseEvent('pointerdown', { clientX: 100, clientY: 100, bubbles: true, button: 0 })
		);
		const input = document.querySelector('.annot-text-input') as HTMLInputElement;
		await fireEvent.input(input, { target: { value: 'oops' } });
		await fireEvent.keyDown(input, { key: 'Escape' });

		expect(get(strokes)).toHaveLength(0); // nothing committed
		expect(document.querySelector('.annot-text-input')).toBeNull(); // editor shut
		expect(get(annotationMode)).toBe(true); // …and Escape did NOT also disarm the pen
	});

	it('re-opens an existing label on a tap and re-commits the edit to the same mark', async () => {
		render(AnnotateHost);
		annotateTool.set('text');
		await fireEvent(
			surfaceAt(),
			new MouseEvent('pointerdown', { clientX: 100, clientY: 100, bubbles: true, button: 0 })
		);
		let input = document.querySelector('.annot-text-input') as HTMLInputElement;
		await fireEvent.input(input, { target: { value: 'first' } });
		await fireEvent.keyDown(input, { key: 'Enter' });
		const id = get(strokes)[0].id;

		// Tap the label again (down + up, no travel) → the editor re-opens holding its text.
		await fireEvent(
			surfaceAt(),
			new MouseEvent('pointerdown', { clientX: 100, clientY: 100, bubbles: true, button: 0 })
		);
		await fireEvent(window, new MouseEvent('pointerup', { clientX: 100, clientY: 100, bubbles: true }));
		input = document.querySelector('.annot-text-input') as HTMLInputElement;
		expect(input).not.toBeNull();
		expect(input.value).toBe('first');

		await fireEvent.input(input, { target: { value: 'second' } });
		await fireEvent.keyDown(input, { key: 'Enter' });
		expect(get(strokes)).toHaveLength(1);
		expect(get(strokes)[0].id).toBe(id); // the same mark, patched — not a new one
		expect(get(strokes)[0].text).toBe('second');
	});

	it('drags a label to a new anchor without re-opening the editor', async () => {
		render(AnnotateHost);
		annotateTool.set('text');
		await fireEvent(
			surfaceAt(),
			new MouseEvent('pointerdown', { clientX: 100, clientY: 100, bubbles: true, button: 0 })
		);
		const input = document.querySelector('.annot-text-input') as HTMLInputElement;
		await fireEvent.input(input, { target: { value: 'move me' } });
		await fireEvent.keyDown(input, { key: 'Enter' });
		const id = get(strokes)[0].id;
		expect(get(strokes)[0].points[0]).toEqual([200, 200]);

		// Grab the label and drag it: down on it, move well past the threshold, up.
		await fireEvent(
			surfaceAt(),
			new MouseEvent('pointerdown', { clientX: 100, clientY: 100, bubbles: true, button: 0 })
		);
		await fireEvent(window, new MouseEvent('pointermove', { clientX: 150, clientY: 130, bubbles: true }));
		await fireEvent(window, new MouseEvent('pointerup', { clientX: 150, clientY: 130, bubbles: true }));

		// 50/30 screen px at half scale = 100/60 canvas px, from [200,200] → [300,260].
		expect(get(strokes)[0].id).toBe(id);
		expect(get(strokes)[0].points[0]).toEqual([300, 260]);
		expect(document.querySelector('.annot-text-input')).toBeNull(); // a drag does not open the editor
	});

	it('erases a TEXT label like any other mark', async () => {
		render(AnnotateHost);
		annotateTool.set('text');
		await fireEvent(
			surfaceAt(),
			new MouseEvent('pointerdown', { clientX: 100, clientY: 100, bubbles: true, button: 0 })
		);
		const input = document.querySelector('.annot-text-input') as HTMLInputElement;
		await fireEvent.input(input, { target: { value: 'gone soon' } });
		await fireEvent.keyDown(input, { key: 'Enter' });
		expect(get(strokes)).toHaveLength(1);

		annotateTool.set('eraser');
		eraseAt(surfaceAt(), [100, 100]); // on the label's anchor
		expect(get(strokes)).toHaveLength(0);
	});

	it('renders a lone tap as a dot rather than nothing', () => {
		render(AnnotateHost);
		const svg = surfaceAt();
		fireEvent(svg, new MouseEvent('pointerdown', { clientX: 50, clientY: 50, bubbles: true, button: 0 }));
		fireEvent(svg, new MouseEvent('pointerup', { clientX: 50, clientY: 50, bubbles: true, button: 0 }));

		expect(get(strokes)).toHaveLength(1);
		expect(document.querySelector('.annot-stroke')?.getAttribute('d')).toBe('M 100 100 L 100 100');
	});

	it('takes back one stroke with UNDO and this slide with RESET', async () => {
		render(AnnotateHost);
		const svg = surfaceAt();
		stroke(svg, [[10, 10], [60, 60]]);
		stroke(svg, [[80, 80], [120, 120]]);
		expect(get(strokes)).toHaveLength(2);

		await fireEvent.click(screen.getByText('UNDO'));
		expect(get(strokes)).toHaveLength(1);

		await fireEvent.click(screen.getByText('RESET'));
		expect(get(strokes)).toHaveLength(0);
		expect(document.querySelectorAll('.annot-stroke')).toHaveLength(0);
		// An emptied slide leaves NO entry behind, or the book would accrete a key per slide
		// ever visited and "has this slide got ink?" would stop being answerable by looking.
		expect(get(inkBook)[SLIDE]).toBeUndefined();
	});

	it('RESET ALL wipes every slide, not just this one', async () => {
		render(AnnotateHost);
		stroke(surfaceAt(), [[10, 10], [60, 60]]);
		setInkPath(OTHER);
		stroke(surfaceAt(), [[10, 10], [60, 60]]);
		expect(Object.keys(get(inkBook))).toHaveLength(2);

		await fireEvent.click(screen.getByText('RESET ALL'));
		expect(get(inkBook)).toEqual({});
	});

	it('draws in a picked colour, and the theme swatch means "no colour at all"', async () => {
		render(AnnotateHost, { props: { inkColors: [null, '#E5484D'] } });

		// A picked colour rides on the stroke and lands as an inline style…
		await fireEvent.click(screen.getByLabelText('Colour #E5484D'));
		stroke(surfaceAt(), [[10, 10], [60, 60]]);
		expect(get(strokes)[0].color).toBe('#E5484D');
		expect(document.querySelector('.annot-stroke')?.getAttribute('style')).toContain('#E5484D');

		// …whereas the THEME swatch stores nothing, so the role token paints it and the ink
		// follows a re-theme instead of freezing today's hex.
		await fireEvent.click(screen.getByLabelText('Theme colour'));
		stroke(surfaceAt(), [[200, 10], [260, 60]]);
		const latest = get(strokes)[1];
		expect(latest.color).toBeUndefined();
	});

	it('remembers a colour per tool', async () => {
		render(AnnotateHost, { props: { inkColors: [null, '#E5484D'] } });
		await fireEvent.click(screen.getByLabelText('Colour #E5484D'));
		expect(get(annotateColor).pen).toBe('#E5484D');
		// Switching tools must not drag the pen's colour onto the highlighter.
		annotateTool.set('highlighter');
		expect(get(annotateColor).highlighter).toBe(null);
	});

	it('puts the pen down on the close (×) and on Escape', async () => {
		render(AnnotateHost);

		await fireEvent.click(screen.getByLabelText('Close annotation tools'));
		expect(get(annotationMode)).toBe(false);

		annotationMode.set(true);
		await fireEvent.keyDown(window, { key: 'Escape' });
		expect(get(annotationMode)).toBe(false);

		// The ANNOTATE toggle itself (the other way to put the pen down) now lives in
		// <SlideToolbar>, above the ink surface so an armed pen can't bury it — covered in
		// SlideToolbar.test.ts, not here (this fixture no longer renders the toggle).
	});

	it('undoes on Ctrl+Z', async () => {
		render(AnnotateHost);
		stroke(surfaceAt(), [[10, 10], [60, 60]]);

		await fireEvent.keyDown(window, { key: 'z', ctrlKey: true });
		expect(get(strokes)).toHaveLength(0);
	});

	it('leaves the paging keys alone', async () => {
		// A speaker who cannot advance is worse off than one who lost a scribble. The overlay
		// eats the POINTER, not the keyboard.
		render(AnnotateHost);
		expect(await fireEvent.keyDown(window, { key: 'ArrowRight' })).toBe(true);
		expect(await fireEvent.keyDown(window, { key: ' ' })).toBe(true);
		expect(get(annotationMode)).toBe(true);
	});

	it('takes the pointer only while armed', () => {
		render(AnnotateHost);
		expect(surfaceAt().style.pointerEvents).toBe('auto');
	});

	it('drags the bar by its grip, remembers where, and sends it home on double-click', async () => {
		render(AnnotateHost);
		surfaceAt(); // stub the surface rect: 960px wide for a 1920 canvas → scale 0.5

		const bar = document.querySelector('.annot-bar') as HTMLElement;
		bar.getBoundingClientRect = () =>
			({ left: 100, top: 400, width: 200, height: 30, right: 300, bottom: 430, x: 100, y: 400 }) as DOMRect;

		const grip = document.querySelector('.annot-grip') as HTMLElement;
		await fireEvent(grip, new MouseEvent('pointerdown', { clientX: 0, clientY: 0, bubbles: true, button: 0 }));
		await fireEvent(window, new MouseEvent('pointermove', { clientX: 50, clientY: 25, bubbles: true }));
		await fireEvent(window, new MouseEvent('pointerup', { bubbles: true }));

		// Bar was at canvas (200, 800); the pointer moved 50/25 screen px = 100/50 canvas px.
		expect(get(barPos)).toEqual({ x: 300, y: 850 });
		// …and it is remembered, so it does not need re-parking on the next slide.
		expect(JSON.parse(localStorage.getItem('annotationBarPos')!)).toEqual({ x: 300, y: 850 });

		// The escape hatch: a bar parked somewhere regrettable would otherwise stay there for good.
		await fireEvent.dblClick(grip);
		expect(get(barPos)).toBe(null);
	});

	it('resets the bar position when the pen is closed, so the next arm starts fresh', async () => {
		render(AnnotateHost);
		surfaceAt();

		const bar = document.querySelector('.annot-bar') as HTMLElement;
		bar.getBoundingClientRect = () =>
			({ left: 100, top: 400, width: 200, height: 30, right: 300, bottom: 430, x: 100, y: 400 }) as DOMRect;

		const grip = document.querySelector('.annot-grip') as HTMLElement;
		await fireEvent(grip, new MouseEvent('pointerdown', { clientX: 0, clientY: 0, bubbles: true, button: 0 }));
		await fireEvent(window, new MouseEvent('pointermove', { clientX: 50, clientY: 25, bubbles: true }));
		await fireEvent(window, new MouseEvent('pointerup', { bubbles: true }));
		expect(get(barPos)).toEqual({ x: 300, y: 850 });

		// Closing the pen — annotationMode going true → false — is the new "reset" trigger,
		// the twin of the double-click Home the test above already covers.
		annotationMode.set(false);
		expect(get(barPos)).toBe(null);

		// Re-arming — right back here, or (in the real app) after a full-page slide change,
		// since annotationMode is itself persisted — starts at the default spot either way.
		annotationMode.set(true);
		expect(get(barPos)).toBe(null);
	});

	it('leaves the bar position alone on a live re-arm that never actually closed', () => {
		render(AnnotateHost);
		barPos.set({ x: 111, y: 222 });

		// Re-asserting the SAME (already armed) value is not a close — a writable store
		// notifies on every set() regardless of value, so this is what proves the reset
		// is keyed on an actual true→false transition, not "annotationMode changed".
		annotationMode.set(true);
		expect(get(barPos)).toEqual({ x: 111, y: 222 });
	});

	it('does not draw a stroke while the grip is being dragged', async () => {
		// The grip sits ON the bar, which sits over the ink surface. Without stopPropagation the
		// same gesture that moves the bar would also scribble a line underneath it.
		render(AnnotateHost);
		surfaceAt();
		const grip = document.querySelector('.annot-grip') as HTMLElement;

		await fireEvent(grip, new MouseEvent('pointerdown', { clientX: 10, clientY: 10, bubbles: true, button: 0 }));
		await fireEvent(window, new MouseEvent('pointermove', { clientX: 60, clientY: 40, bubbles: true }));
		await fireEvent(window, new MouseEvent('pointerup', { bubbles: true }));

		expect(get(strokes)).toHaveLength(0);
	});

	it('clamps a bar dragged past the edge back into the canvas', async () => {
		render(AnnotateHost);
		surfaceAt();
		const bar = document.querySelector('.annot-bar') as HTMLElement;
		bar.getBoundingClientRect = () =>
			({ left: 0, top: 0, width: 200, height: 30, right: 200, bottom: 30, x: 0, y: 0 }) as DOMRect;

		const grip = document.querySelector('.annot-grip') as HTMLElement;
		await fireEvent(grip, new MouseEvent('pointerdown', { clientX: 0, clientY: 0, bubbles: true, button: 0 }));
		await fireEvent(window, new MouseEvent('pointermove', { clientX: -9999, clientY: -9999, bubbles: true }));
		await fireEvent(window, new MouseEvent('pointerup', { bubbles: true }));

		// Dragged off the top-left, it stops at the corner — because a bar off the edge is a bar
		// the speaker cannot get back, and the position is persisted.
		expect(get(barPos)).toEqual({ x: 0, y: 0 });
	});
});

describe('Annotate — the stale-ink notice', () => {
	const DAY = 24 * 60 * 60 * 1000;

	it('offers to clear ink drawn before the threshold', async () => {
		// Ink from a previous sitting is exactly what a persisted pen risks putting on stage.
		inkBook.set({ [SLIDE]: { strokes: [{ id: 'a', tool: 'pen', points: [[0, 0], [9, 9]] }], ts: Date.now() - 3 * DAY } });
		render(AnnotateHost);

		expect(screen.getByText(/3 days ago/)).toBeTruthy();

		await fireEvent.click(screen.getByText('RESET SLIDE'));
		expect(get(strokes)).toHaveLength(0);
	});

	it('says nothing about ink you drew today', () => {
		inkBook.set({ [SLIDE]: { strokes: [{ id: 'a', tool: 'pen', points: [[0, 0], [9, 9]] }], ts: Date.now() - 1000 } });
		render(AnnotateHost);
		expect(screen.queryByText('RESET SLIDE')).toBeNull();
	});

	it('says nothing at all about a slide with no ink', () => {
		render(AnnotateHost);
		expect(screen.queryByText('RESET SLIDE')).toBeNull();
	});

	it('KEEP dismisses it for this visit only, not for good', async () => {
		inkBook.set({ [SLIDE]: { strokes: [{ id: 'a', tool: 'pen', points: [[0, 0], [9, 9]] }], ts: Date.now() - 3 * DAY } });
		render(AnnotateHost);

		await fireEvent.click(screen.getByText('KEEP'));
		expect(screen.queryByText('RESET SLIDE')).toBeNull();
		expect(get(strokes)).toHaveLength(1); // the ink is KEPT, not cleared

		// Leave and come back: "not now" was not "never again".
		setInkPath(OTHER);
		setInkPath(SLIDE);
		expect(get(staleDismissed)).toBe(false);
	});
});

describe('Annotate — disarmed', () => {
	it('renders nothing when there is no ink and the pen is down', () => {
		render(AnnotateHost);

		expect(document.querySelector('.annot-surface')).toBeNull();
		expect(screen.queryByLabelText('Pen')).toBeNull();
		// The ANNOTATE toggle (which arms the pen in the first place) now lives in
		// <SlideToolbar>; its presence/absence is asserted there, not on this fixture.
	});

	it('still SHOWS ink it is mirroring, with the pen down and the pointer let through', () => {
		// The audience window: it never arms the pen, but it must draw what the speaker's
		// window wrote — that is how the ink reaches the room.
		inkBook.set({ [SLIDE]: { strokes: [{ id: 'a', tool: 'pen', points: [[0, 0], [100, 100]] }], ts: Date.now() } });
		render(AnnotateHost);

		expect(document.querySelectorAll('.annot-stroke')).toHaveLength(1);
		expect((document.querySelector('.annot-surface') as SVGElement).style.pointerEvents).toBe('none');
		expect(screen.queryByLabelText('Pen')).toBeNull(); // no palette in the audience's window
	});

	// (The "no chrome under ?clean / ?present" case moved to SlideToolbar.test.ts, which now
	//  owns the ANNOTATE toggle and the browser/chrome gating that hides it.)

	it('ignores a gesture when the deck never offered the pen', () => {
		// A stale persisted `annotationMode: true` from another deck must stay inert here.
		canAnnotate.set(false);
		annotationMode.set(true);
		inkBook.set({ [SLIDE]: { strokes: [{ id: 'a', tool: 'pen', points: [[0, 0], [10, 10]] }], ts: Date.now() } });
		render(AnnotateHost);

		const svg = surfaceAt();
		expect(svg.style.pointerEvents).toBe('none');
		stroke(svg, [[10, 10], [60, 60]]);
		expect(get(strokes)).toHaveLength(1); // the existing one, and nothing new
	});
});

// --- FREEZE: keeping a mark ---------------------------------------------------
//
// Ink is transient by design and a Draw shape is source; FREEZE is the bridge. It borrows
// the eraser's interaction (hover lights a mark, the same hitStroke reach) with one
// deliberate divergence: a tap TOGGLES a selection instead of acting at once, because
// freezing is additive and reversible where erasing is neither. The load-bearing claims
// here are that nothing happens before the commit, and that a clipboard copy — which has
// not landed until the author pastes — never destroys the ink.
describe('Annotate — FREEZE', () => {
	let copied: string[] = [];

	beforeEach(() => {
		annotationMode.set(true);
		copied = [];
		Object.defineProperty(navigator, 'clipboard', {
			configurable: true,
			value: { writeText: (t: string) => { copied.push(t); return Promise.resolve(); } }
		});
	});

	/** Draw a mark with the pen, then switch to FREEZE. Svelte 5 flushes on a microtask,
	    so a store set needs a tick before the bar reflects it. */
	async function drawThenFreeze(svg: Element): Promise<void> {
		stroke(svg, [[100, 100], [200, 150], [300, 100]]);
		annotateTool.set('freeze');
		await tick();
	}

	const freezeBtn = () => screen.getByText(/^FREEZE \(/) as HTMLButtonElement;

	it('picks a mark on tap and un-picks it on a second tap', async () => {
		render(AnnotateHost);
		const svg = surfaceAt();
		await drawThenFreeze(svg);

		// Nothing picked yet: the commit is disabled and says so.
		expect(freezeBtn().textContent).toContain('(0)');
		expect(freezeBtn().disabled).toBe(true);

		eraseAt(svg, [200, 150]); // a tap on the stroke — picks it
		await tick();
		expect(freezeBtn().textContent).toContain('(1)');
		expect(freezeBtn().disabled).toBe(false);
		expect(document.querySelector('.annot-stroke.frozen')).not.toBeNull();

		eraseAt(svg, [200, 150]); // tap again — changes your mind
		await tick();
		expect(freezeBtn().textContent).toContain('(0)');
		expect(document.querySelector('.annot-stroke.frozen')).toBeNull();
	});

	it('lights the mark under the pointer without picking it', async () => {
		render(AnnotateHost);
		const svg = surfaceAt();
		await drawThenFreeze(svg);

		hover(svg, [200, 150]);
		await tick();
		expect(document.querySelector('.annot-stroke.freezing')).not.toBeNull();
		// Hovering is not choosing.
		expect(freezeBtn().textContent).toContain('(0)');
	});

	it('does NOTHING to the ink until the commit is pressed', async () => {
		render(AnnotateHost);
		const svg = surfaceAt();
		await drawThenFreeze(svg);
		eraseAt(svg, [200, 150]);
		await tick();

		expect(get(strokes)).toHaveLength(1); // still ink
		expect(copied).toHaveLength(0); // and nothing copied
	});

	it('copies the picked marks as <Draw>-wrapped markup, and KEEPS the ink', async () => {
		// The clipboard is not a landing: a copy has not taken effect until the author
		// pastes it, so destroying the mark here would lose it to a failed paste.
		render(AnnotateHost);
		const svg = surfaceAt();
		await drawThenFreeze(svg);
		eraseAt(svg, [200, 150]);
		await tick();
		await fireEvent.click(freezeBtn());
		await tick();

		expect(copied).toHaveLength(1);
		expect(copied[0]).toContain('<Draw>');
		expect(copied[0]).toContain('<Polyline');
		expect(get(strokes)).toHaveLength(1);
	});

	it('refuses to freeze a TEXT label — it has no Draw counterpart', async () => {
		render(AnnotateHost);
		const svg = surfaceAt();
		annotateTool.set('text');
		await tick();
		fireEvent(svg, new MouseEvent('pointerdown', { clientX: 100, clientY: 100, bubbles: true, button: 0 }));
		await tick();
		const input = document.querySelector('.annot-text-input') as HTMLInputElement;
		await fireEvent.input(input, { target: { value: 'note' } });
		await fireEvent.keyDown(input, { key: 'Enter' });
		expect(get(strokes)).toHaveLength(1);

		annotateTool.set('freeze');
		await tick();
		eraseAt(surfaceAt(), [100, 100]);
		await tick();
		// Neither picked nor even lit — lighting it would promise a shape that never arrives.
		expect(freezeBtn().textContent).toContain('(0)');
		expect(document.querySelector('.annot-stroke.frozen')).toBeNull();
	});

	it('drops the pick when the speaker leaves FREEZE mode', async () => {
		// A selection you cannot see is one you will be surprised by on your way back.
		render(AnnotateHost);
		const svg = surfaceAt();
		await drawThenFreeze(svg);
		eraseAt(svg, [200, 150]);
		await tick();
		expect(freezeBtn().textContent).toContain('(1)');

		annotateTool.set('pen');
		await tick();
		annotateTool.set('freeze');
		await tick();
		expect(freezeBtn().textContent).toContain('(0)');
	});

	it('hides the colour swatches while picking — there is no colour to set', async () => {
		render(AnnotateHost);
		await drawThenFreeze(surfaceAt());
		expect(document.querySelector('.annot-swatch')).toBeNull();
	});
});
