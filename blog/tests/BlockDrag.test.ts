import { render } from '@testing-library/svelte';
import { tick } from 'svelte';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { canAdjust, adjustMode } from '../src/lib/stores/adjustMode';
import { selectedBlock } from '../src/lib/stores/selectedBlock';
import BlockDragHost from './BlockDragHost.svelte';

// jsdom has no layout engine and no PointerEvent constructor. trackPointer reads
// the live scale from `el.getBoundingClientRect().width / el.offsetWidth`, both 0
// here → NaN → its `|| 1` guard falls back to scale 1, so a screen-px move IS a
// canvas-px move. That is exactly what we want: the numbers below are 1:1.

/** A pointer event jsdom will accept (no PointerEvent ctor). `detail: 0` mirrors a
 *  real pointerdown; `shiftKey` rides along so Block's onMove can read it. */
function pointer(type: string, clientX: number, clientY: number, opts: { shiftKey?: boolean } = {}) {
	const ev = new MouseEvent(type, {
		bubbles: true,
		cancelable: true,
		clientX,
		clientY,
		detail: 0,
		shiftKey: opts.shiftKey ?? false
	});
	Object.defineProperty(ev, 'pointerId', { value: 1 });
	return ev;
}

const box = (root: ParentNode) => root.querySelector('.movable') as HTMLElement;

/** Grab the block body at (0,0), move the pointer to (dx,dy), release. */
function drag(root: ParentNode, dx: number, dy: number, opts: { shiftKey?: boolean } = {}) {
	box(root).dispatchEvent(pointer('pointerdown', 0, 0));
	window.dispatchEvent(pointer('pointermove', dx, dy, opts));
	window.dispatchEvent(pointer('pointerup', dx, dy, opts));
}

beforeEach(() => {
	canAdjust.set(true);
	adjustMode.set(true);
	selectedBlock.set(null);
});
afterEach(() => {
	vi.restoreAllMocks();
	adjustMode.set(false);
	canAdjust.set(false);
});

describe('Block — Shift-drag axis lock', () => {
	it('a free move (no Shift) shifts both x and y', async () => {
		const { container } = render(BlockDragHost, { props: { x: 100, y: 100 } });
		await tick();

		drag(container, 120, 40);
		await tick();
		expect(box(container).style.left).toBe('220px');
		expect(box(container).style.top).toBe('140px');
	});

	it('Shift locks to X when the pointer has travelled further horizontally', async () => {
		const { container } = render(BlockDragHost, { props: { x: 100, y: 100 } });
		await tick();

		drag(container, 120, 40, { shiftKey: true });
		await tick();
		expect(box(container).style.left).toBe('220px'); // 100 + 120
		expect(box(container).style.top).toBe('100px'); // y pinned to start
	});

	it('Shift locks to Y when the pointer has travelled further vertically', async () => {
		const { container } = render(BlockDragHost, { props: { x: 100, y: 100 } });
		await tick();

		drag(container, 40, 120, { shiftKey: true });
		await tick();
		expect(box(container).style.left).toBe('100px'); // x pinned to start
		expect(box(container).style.top).toBe('220px'); // 100 + 120
	});

	it('X-lock holds even with a large upward component, as long as X dominates', async () => {
		const { container } = render(BlockDragHost, { props: { x: 100, y: 100 } });
		await tick();

		// Moving up (dy < 0) must NOT flip to a diagonal — X still dominates here.
		drag(container, 200, -120, { shiftKey: true });
		await tick();
		expect(box(container).style.left).toBe('300px'); // 100 + 200
		expect(box(container).style.top).toBe('100px'); // y pinned to start
	});

	it('a tie keeps the horizontal axis (>= favours X, matching aspect resize)', async () => {
		const { container } = render(BlockDragHost, { props: { x: 100, y: 100 } });
		await tick();

		drag(container, 60, -60, { shiftKey: true });
		await tick();
		expect(box(container).style.left).toBe('160px'); // 100 + 60
		expect(box(container).style.top).toBe('100px'); // y pinned
	});

	it('the axis is measured from the drag start, not the last move', async () => {
		const { container } = render(BlockDragHost, { props: { x: 100, y: 100 } });
		await tick();

		// Live re-evaluation: cross the diagonal within one gesture and the locked
		// axis follows the CUMULATIVE delta from start — here Y wins by the end.
		box(container).dispatchEvent(pointer('pointerdown', 0, 0));
		window.dispatchEvent(pointer('pointermove', 80, 20, { shiftKey: true })); // X dominant
		await tick();
		expect(box(container).style.left).toBe('180px');
		expect(box(container).style.top).toBe('100px');

		window.dispatchEvent(pointer('pointermove', 30, 150, { shiftKey: true })); // now Y dominant
		await tick();
		expect(box(container).style.left).toBe('100px'); // snaps back to start x
		expect(box(container).style.top).toBe('250px'); // 100 + 150
		window.dispatchEvent(pointer('pointerup', 30, 150));
	});
});
