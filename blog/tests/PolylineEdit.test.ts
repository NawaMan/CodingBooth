// Polyline ADJUST editor (move-only): the stroke selects, each waypoint grows
// a drag handle, dragging one re-routes the live geometry, and Copy emits a
// <Polyline> tag carrying the edited points. The waypoint COUNT is fixed here
// — add/remove is a tag edit, by design. Undo/redo walk every completed drag.
import { render } from '@testing-library/svelte';
import { tick } from 'svelte';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { undo, redo } from '../src/lib/stores/adjustHistory';
import { canAdjust, adjustMode } from '../src/lib/stores/adjustMode';
import PolylineEditHost from './PolylineEditHost.svelte';

const moveTo = (clientX: number, clientY: number) =>
	window.dispatchEvent(new MouseEvent('pointermove', { clientX, clientY }));
const release = () => window.dispatchEvent(new MouseEvent('pointerup'));

async function grab(el: Element, clientX = 0, clientY = 0) {
	const ev = new MouseEvent('pointerdown', { clientX, clientY, bubbles: true });
	Object.defineProperty(ev, 'pointerId', { value: 1 });
	el.dispatchEvent(ev);
	await tick();
}

describe('Polyline editor (ADJUST)', () => {
	beforeEach(() => {
		canAdjust.set(true);
		adjustMode.set(true);
	});
	afterEach(() => {
		canAdjust.set(false);
		adjustMode.set(false);
	});

	it('shows one handle per waypoint, selecting the stroke marks them selected', async () => {
		const { container } = render(PolylineEditHost);
		expect(container.querySelector('.draw-hit')).not.toBeNull();
		// Like Line/Curve, an editing shape shows its handles inline; selection
		// changes their state, not their presence.
		const handles = container.querySelectorAll('.draw-handle');
		expect(handles).toHaveLength(3);
		expect(handles[0].getAttribute('cx')).toBe('100');
		expect(handles[1].getAttribute('cx')).toBe('500');
		expect(handles[2].getAttribute('cx')).toBe('900');
		expect(handles[0].getAttribute('class')).toContain('quiet'); // unselected = quiet

		await grab(container.querySelector('.draw-hit')!);
		expect(container.querySelectorAll('.draw-handle')[0].getAttribute('class')).not.toContain(
			'quiet'
		);
	});

	it('dragging a waypoint rewrites the stroke and the copied tag; undo/redo walk it', async () => {
		const writeText = vi.fn().mockResolvedValue(undefined);
		Object.defineProperty(navigator, 'clipboard', { value: { writeText }, configurable: true });

		const { container } = render(PolylineEditHost);
		await grab(container.querySelector('.draw-hit')!);
		// Drag the middle waypoint [500, 500] by +50/−50 → [550, 450].
		await grab(container.querySelectorAll('.draw-handle')[1]);
		moveTo(50, -50);
		release();
		await tick();

		(container.querySelector('.draw-toolbar .tb-copy') as HTMLButtonElement).click();
		await tick();
		expect(writeText.mock.calls[0][0]).toBe(
			'<Polyline name="route" points={[[100, 900], [550, 450], [900, 900]]} smooth />'
		);

		undo();
		await tick();
		(container.querySelector('.draw-toolbar .tb-copy') as HTMLButtonElement).click();
		await tick();
		expect(writeText.mock.calls[1][0]).toBe(
			'<Polyline name="route" points={[[100, 900], [500, 500], [900, 900]]} smooth />'
		);

		redo();
		await tick();
		(container.querySelector('.draw-toolbar .tb-copy') as HTMLButtonElement).click();
		await tick();
		expect(writeText.mock.calls[2][0]).toContain('[550, 450]');
	});
});
