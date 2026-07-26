import { render } from '@testing-library/svelte';
import { tick } from 'svelte';
import { get } from 'svelte/store';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import Block from '$lib/components/Block.svelte';
import BlockZHost from './BlockZHost.svelte';
import { adjustMode, canAdjust } from '$lib/stores/adjustMode';
import { blockOrder } from '$lib/stores/blockOrder';

// The live half of the `z` prop: in PRESENTATION a non-zero z becomes the
// wrapper's z-index; in ADJUST mode the Front / Back buttons order a Block
// against its siblings (read from the blockOrder registry). The Save-path half
// is unit-tested in adjustPatch.test.ts; the pure order math in stackingCore.test.ts.

const movable = (root: ParentNode) => root.querySelector('.movable') as HTMLElement;

beforeEach(() => {
	blockOrder.set(new Map());
	adjustMode.set(false);
	canAdjust.set(true); // make ADJUST available; individual tests turn the mode on
});
afterEach(() => adjustMode.set(false));

describe('Block z-index (presentation)', () => {
	it('applies a non-zero z as the wrapper z-index when not editing', () => {
		const { container } = render(Block, { props: { z: 4 } });
		expect(movable(container).style.zIndex).toBe('4');
	});

	it('emits no z-index at z=0 (Blocks stay z-index:auto, painting in DOM order)', () => {
		const { container } = render(Block, { props: { z: 0 } });
		expect(movable(container).style.zIndex).toBe('');
	});

	it('applies a negative z (send-to-back)', () => {
		const { container } = render(Block, { props: { z: -1 } });
		expect(movable(container).style.zIndex).toBe('-1');
	});

});

describe('Block z-index (ADJUST mode — live reorder)', () => {
	beforeEach(() => adjustMode.set(true));

	it('reflects the author z in real time while editing (not just after leaving ADJUST)', async () => {
		const { container } = render(Block, { props: { z: 4 } });
		await tick();
		// A non-grabbed editing Block shows its authored order live, so a reorder is
		// visible as you make it — the confusion the presentation-only version caused.
		expect(movable(container).style.zIndex).toBe('4');
	});

	it('keeps a z=0 Block at z-index:auto so its grip still floats', async () => {
		const { container } = render(Block, { props: { z: 0 } });
		await tick();
		expect(movable(container).style.zIndex).toBe('');
	});

	it('lifts the selected Block above any authored z (grabbability wins)', async () => {
		// A big authored z must not out-stack the Block you are grabbing.
		const { container } = render(Block, { props: { z: 999 } });
		await tick();
		const el = movable(container);
		// jsdom has no PointerEvent; a MouseEvent named 'pointerdown' drives the
		// same handler (the pattern DrawEditing.test.ts uses for Block drags).
		el.dispatchEvent(new MouseEvent('pointerdown', { bubbles: true }));
		await tick();
		// Selected/dragging lift sits in the 44–48 band, above the author-z cap (42).
		expect(Number(el.style.zIndex)).toBeGreaterThanOrEqual(44);
		expect(Number(el.style.zIndex)).toBeLessThan(50);
	});

	it('caps a huge authored z below the grab lift for a non-grabbed Block', async () => {
		const { container } = render(Block, { props: { z: 999 } });
		await tick();
		// Not grabbed → shown, but capped under the lift band so a grabbed peer wins.
		expect(Number(movable(container).style.zIndex)).toBeLessThan(44);
	});
});

describe('Block Front / Back (ADJUST mode)', () => {
	beforeEach(() => adjustMode.set(true));

	it('registers every Block z in the order registry', async () => {
		render(BlockZHost, { props: { aZ: 0, bZ: 2 } });
		await tick();
		expect([...get(blockOrder).values()].sort()).toEqual([0, 2]);
	});

	it('Bring to front raises a Block above its sibling', async () => {
		const { getAllByLabelText } = render(BlockZHost, { props: { aZ: 0, bZ: 2 } });
		await tick();
		// Two Blocks → two Front buttons; index 0 is Block "a".
		await getAllByLabelText('Bring to front')[0].click();
		await tick();
		// frontZ(0, [2]) === 3 — one above the sibling; b stays at 2.
		expect([...get(blockOrder).values()].sort((m, n) => m - n)).toEqual([2, 3]);
	});

	it('Send to back lowers a Block below its sibling', async () => {
		const { getAllByLabelText } = render(BlockZHost, { props: { aZ: 5, bZ: 2 } });
		await tick();
		await getAllByLabelText('Send to back')[0].click();
		await tick();
		// backZ(5, [2]) === 1 — one below the sibling.
		const zs = [...get(blockOrder).values()].sort((m, n) => m - n);
		expect(zs).toEqual([1, 2]);
	});

	it('Send to back floors at 0 — never drops a Block behind the slide content', async () => {
		// a=1 over a default b=0: the raw "one below the lowest" would be -1, which a
		// negative z-index would paint behind in-flow content (text, a code box). The
		// button floors at 0 so Blocks stay above the slide body.
		const { getAllByLabelText } = render(BlockZHost, { props: { aZ: 1, bZ: 0 } });
		await tick();
		await getAllByLabelText('Send to back')[0].click();
		await tick();
		const zs = [...get(blockOrder).values()];
		expect(Math.min(...zs)).toBe(0); // floored, not -1
	});

	it('a repeated Bring to front on an already-top Block is a no-op (no churn)', async () => {
		const { getAllByLabelText } = render(BlockZHost, { props: { aZ: 9, bZ: 2 } });
		await tick();
		await getAllByLabelText('Bring to front')[0].click();
		await tick();
		expect([...get(blockOrder).values()].sort((m, n) => m - n)).toEqual([2, 9]);
	});
});
