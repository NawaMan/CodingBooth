// Select-to-front for the Draw path shapes: a selected shape's editing chrome
// (guide lines + handles) is re-parented out of its own <g> into a top layer
// that Draw renders LAST inside the surface — so its handles win the pointer
// even where a shape drawn after it lies on top.
//
// SVG has no z-index (paint order IS document order IS hit order), so moving
// the nodes is the only lever. Moving the CHROME rather than the shape's <g>
// is what keeps the author's visible overlap untouched.
import { render } from '@testing-library/svelte';
import { tick } from 'svelte';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { undo } from '../src/lib/stores/adjustHistory';
import { canAdjust, adjustMode } from '../src/lib/stores/adjustMode';
import DrawEditHost from './DrawEditHost.svelte';
import DrawHoistUnmountHost from './DrawHoistUnmountHost.svelte';

const surface = (c: HTMLElement) => c.querySelector('svg.draw')!;
const chrome = (c: HTMLElement, shape: string) =>
	c.querySelectorAll(`g.draw-chrome[data-shape="${shape}"]`);
const handles = (c: HTMLElement, shape: string, kind = '') =>
	c.querySelectorAll(`g.draw-chrome[data-shape="${shape}"] circle.draw-handle${kind}`);

const pointerDown = (el: Element) => {
	const ev = new MouseEvent('pointerdown', { bubbles: true });
	Object.defineProperty(ev, 'pointerId', { value: 1 });
	el.dispatchEvent(ev);
};
const moveTo = (clientX: number, clientY: number) =>
	window.dispatchEvent(new MouseEvent('pointermove', { clientX, clientY }));
const release = () => window.dispatchEvent(new MouseEvent('pointerup'));

async function selectByStroke(c: HTMLElement, group: string) {
	pointerDown(c.querySelector(`g.${group} .draw-hit`)!);
	await tick();
}

describe('select-to-front (ADJUST mode)', () => {
	beforeEach(() => {
		canAdjust.set(true);
		adjustMode.set(true);
	});
	afterEach(() => {
		canAdjust.set(false);
		adjustMode.set(false);
	});

	it('an unselected shape keeps its chrome at home, inside its own <g>', () => {
		const { container } = render(DrawEditHost);
		expect(chrome(container, 'main')).toHaveLength(1);
		expect(chrome(container, 'main')[0].closest('g.draw-line')).not.toBeNull();
		// nothing is selected, so the surface hosts no chrome of its own
		expect(surface(container).querySelector(':scope > g.draw-chrome')).toBeNull();
	});

	it('selecting hoists that shape’s chrome to the LAST child of the surface', async () => {
		const { container } = render(DrawEditHost);
		await selectByStroke(container, 'draw-line'); // the "main" Line

		const g = chrome(container, 'main')[0];
		expect(g.parentElement).toBe(surface(container));
		expect(surface(container).lastElementChild).toBe(g);
		// …which is what puts it after every shape group, the whole point:
		expect(g.compareDocumentPosition(container.querySelector('g.draw-path')!)).toBe(
			Node.DOCUMENT_POSITION_PRECEDING
		);
		// it left home rather than being copied — chrome exists in exactly ONE place
		expect(chrome(container, 'main')).toHaveLength(1);
		// (the host has three Lines; only the selected one's <g> is emptied)
		expect(container.querySelectorAll('g.draw-line')[0].querySelector('g.draw-chrome')).toBeNull();
	});

	it('only the selected shape hoists; the others keep quiet chrome at home', async () => {
		const { container } = render(DrawEditHost);
		await selectByStroke(container, 'draw-curve'); // "hop"

		expect(chrome(container, 'hop')[0].parentElement).toBe(surface(container));
		for (const other of ['main', 'loop', 'route']) {
			expect(chrome(container, other)[0].parentElement).not.toBe(surface(container));
		}
		// exactly one shape's chrome is ever in the top layer
		expect(surface(container).querySelectorAll(':scope > g.draw-chrome')).toHaveLength(1);
	});

	it('the hit stroke stays HOME — raising it would seal off a crossing band', async () => {
		const { container } = render(DrawEditHost);
		await selectByStroke(container, 'draw-line');
		const hit = container.querySelector('g.draw-line .draw-hit')!;
		expect(hit.closest('g.draw-line')).not.toBeNull();
		expect(hit.closest('g.draw-chrome')).toBeNull();
		// so a neighbour's stroke is still the topmost hit target where they cross
		expect(container.querySelectorAll('svg.draw > g.draw-chrome .draw-hit')).toHaveLength(0);
	});

	it('deselecting brings the chrome home again', async () => {
		const { container } = render(DrawEditHost);
		await selectByStroke(container, 'draw-arc'); // "loop"
		expect(chrome(container, 'loop')[0].parentElement).toBe(surface(container));

		document.body.dispatchEvent(new MouseEvent('pointerdown', { bubbles: true }));
		await tick();
		expect(chrome(container, 'loop')[0].closest('g.draw-arc')).not.toBeNull();
		expect(surface(container).querySelector(':scope > g.draw-chrome')).toBeNull();
	});

	// The safety property the whole design turns on. A drag that begins on an
	// UNSELECTED handle selects and grabs in one gesture — so hoisting on
	// selection would re-create the very node under the pointer, and a node that
	// leaves the document drops the pointer capture trackPointer just took (after
	// which a release outside the window is never delivered and the drag sticks to
	// the cursor). Draw therefore HOLDS the hoist until the gesture ends.
	it('a drag that selects does not re-home the knob under the pointer', async () => {
		const { container } = render(DrawEditHost);
		const knob = handles(container, 'loop', '.bend')[0]; // arc apex, unselected
		expect(knob.closest('g.draw-arc')).not.toBeNull();

		pointerDown(knob);
		await tick();

		// selected already (the toolbar proves it) …
		expect(container.querySelector('.draw-toolbar .tb-shape')?.textContent).toBe('loop');
		// … yet the knob is the SAME live node, still at home: the hoist is held
		expect(knob.isConnected).toBe(true);
		expect(handles(container, 'loop', '.bend')[0]).toBe(knob);
		expect(knob.closest('g.draw-arc')).not.toBeNull();
		expect(surface(container).querySelector(':scope > g.draw-chrome')).toBeNull();

		// the drag itself still tracks…
		moveTo(0, 200);
		await tick();
		expect(knob.isConnected).toBe(true);

		// …and the hoist lands the moment the pointer is released
		release();
		await tick();
		expect(chrome(container, 'loop')[0].parentElement).toBe(surface(container));
		undo();
	});

	// A second finger cannot strand the freeze on. trackPointer's pointerup rides
	// the WINDOW and filters no pointerId, so one release ends every gesture in
	// flight — overlapping drags always end together, and the hold releases with
	// them. That is why a flag suffices where a count looks tempting.
	it('a second grab mid-drag still leaves the hoist held, then landed on release', async () => {
		const { container } = render(DrawEditHost);
		pointerDown(handles(container, 'main')[0]);
		await tick();
		const second = handles(container, 'hop')[0]; // a second handle, first still down
		pointerDown(second);
		await tick();

		// both are held at home — neither knob was re-homed under its pointer
		expect(second.isConnected).toBe(true);
		expect(surface(container).querySelector(':scope > g.draw-chrome')).toBeNull();

		release(); // ends BOTH gestures, so the hold lifts exactly once
		await tick();
		expect(chrome(container, 'hop')[0].parentElement).toBe(surface(container));
		expect(surface(container).querySelectorAll(':scope > g.draw-chrome')).toHaveLength(1);
	});

	it('a plain click on a handle hoists as soon as the pointer is up', async () => {
		const { container } = render(DrawEditHost);
		pointerDown(handles(container, 'main')[0]);
		await tick();
		expect(surface(container).querySelector(':scope > g.draw-chrome')).toBeNull(); // held
		release();
		await tick();
		expect(chrome(container, 'main')[0].parentElement).toBe(surface(container));
	});

	// Teardown. The chrome snippet is owned by the shape but RENDERED by Draw, so
	// a shape that unmounts while hoisted leaves Draw holding markup whose owner
	// is being destroyed. The shape's onDestroy clears the selection and Draw's
	// unregister clears the frozen hoist; these pin that they actually cover it.
	it('a shape that unmounts while hoisted takes its chrome with it', async () => {
		const { container, rerender } = render(DrawHoistUnmountHost, { show: true });
		pointerDown(container.querySelectorAll('g.draw-line')[1].querySelector('.draw-hit')!);
		await tick();
		expect(chrome(container, 'going')[0].parentElement).toBe(surface(container));

		await rerender({ show: false });
		await tick();
		expect(chrome(container, 'going')).toHaveLength(0);
		expect(surface(container).querySelector(':scope > g.draw-chrome')).toBeNull();
		expect(container.querySelector('.draw-toolbar')).toBeNull(); // selection cleared too

		// and the surface still works: the survivor selects and hoists as normal
		pointerDown(container.querySelector('g.draw-line .draw-hit')!);
		await tick();
		expect(chrome(container, 'stay')[0].parentElement).toBe(surface(container));
	});

	it('a shape that unmounts MID-DRAG does not strand the frozen hoist', async () => {
		const { container, rerender } = render(DrawHoistUnmountHost, { show: true });
		pointerDown(handles(container, 'going')[0]); // grabs + selects; hoist now frozen on it
		await tick();

		await rerender({ show: false }); // the shape leaves with the gesture still live
		await tick();
		release(); // the window listeners outlive the component, so this still lands
		await tick();

		// the freeze released and the layer is not pinned to a departed editor
		expect(surface(container).querySelector(':scope > g.draw-chrome')).toBeNull();
		pointerDown(container.querySelector('g.draw-line .draw-hit')!);
		await tick();
		expect(chrome(container, 'stay')[0].parentElement).toBe(surface(container));
	});

	it('no chrome layer at all outside ADJUST mode, or in a published build', async () => {
		const { container } = render(DrawEditHost);
		await selectByStroke(container, 'draw-line');
		expect(container.querySelectorAll('g.draw-chrome')).not.toHaveLength(0);

		adjustMode.set(false);
		await tick();
		expect(container.querySelectorAll('g.draw-chrome')).toHaveLength(0);

		// canAdjust false is the published deck: ADJUST can't be forced back on
		adjustMode.set(true);
		canAdjust.set(false);
		await tick();
		expect(container.querySelectorAll('g.draw-chrome')).toHaveLength(0);
	});
});
