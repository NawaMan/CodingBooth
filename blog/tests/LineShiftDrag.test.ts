// Line endpoint Shift-drag: holding Shift while dragging a handle locks the
// point to a single axis measured from the GRAB point — X or Y, whichever the
// pointer moved further — matching Block's move. The regression this pins: the
// snap is relative to where you grabbed, NOT the shape's other end, so a
// near-horizontal line's endpoint can still be pulled straight up/down (the old
// `snapToAngles(p, otherEnd)` wiring made the vertical detent unreachable).
import { render } from '@testing-library/svelte';
import { tick } from 'svelte';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { canAdjust, adjustMode } from '../src/lib/stores/adjustMode';
import LineShiftDragHost from './LineShiftDragHost.svelte';

const moveTo = (clientX: number, clientY: number, shiftKey = false) =>
	window.dispatchEvent(new MouseEvent('pointermove', { clientX, clientY, shiftKey }));
const release = () => window.dispatchEvent(new MouseEvent('pointerup'));

async function grab(el: Element, clientX = 0, clientY = 0) {
	const ev = new MouseEvent('pointerdown', { clientX, clientY, bubbles: true });
	Object.defineProperty(ev, 'pointerId', { value: 1 });
	el.dispatchEvent(ev);
	await tick();
}

/** The moving endpoint is the LAST handle (to). jsdom has no layout, so the
 *  handle's cx/cy read back the live point after onmove. */
const toHandle = (root: ParentNode) => {
	const handles = root.querySelectorAll('.draw-handle');
	return handles[handles.length - 1];
};
const at = (h: Element) => [h.getAttribute('cx'), h.getAttribute('cy')];

describe('Line endpoint — Shift-drag axis lock', () => {
	beforeEach(() => {
		canAdjust.set(true);
		adjustMode.set(true);
	});
	afterEach(() => {
		canAdjust.set(false);
		adjustMode.set(false);
	});

	it('Shift + mostly-vertical drag locks to Y from the grab point (x stays put, not the far end)', async () => {
		const { container } = render(LineShiftDragHost);
		await grab(container.querySelector('.draw-hit')!); // select the stroke
		await grab(toHandle(container)); // grab the `to` endpoint at [500, 100]
		moveTo(20, 200, true); // mostly vertical, Shift held
		release();
		await tick();
		// Y reachable: y follows the drag; x pinned to the grab point (500), NOT
		// snapped back to the other end's x (100) as the old ref-relative snap did.
		expect(at(toHandle(container))).toEqual(['500', '300']);
	});

	it('Shift + mostly-horizontal drag locks to X from the grab point', async () => {
		const { container } = render(LineShiftDragHost);
		await grab(container.querySelector('.draw-hit')!);
		await grab(toHandle(container));
		moveTo(200, 20, true); // mostly horizontal, Shift held
		release();
		await tick();
		expect(at(toHandle(container))).toEqual(['700', '100']);
	});

	it('without Shift the endpoint follows the pointer freely on both axes', async () => {
		const { container } = render(LineShiftDragHost);
		await grab(container.querySelector('.draw-hit')!);
		await grab(toHandle(container));
		moveTo(20, 200, false);
		release();
		await tick();
		expect(at(toHandle(container))).toEqual(['520', '300']);
	});
});
