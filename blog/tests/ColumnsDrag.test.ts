import { render } from '@testing-library/svelte';
import { tick } from 'svelte';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { canAdjust, adjustMode } from '../src/lib/stores/adjustMode';
import ColumnsHost from './ColumnsHost.svelte';

// The draggable divider. jsdom has no layout engine, so `getComputedStyle` never
// resolves `grid-template-columns` to used pixels — which is the ONE input the whole
// feature reads. So it is stubbed to a known grid (300px | 500px, no gap) and
// everything downstream is the real code: measure → gutter centre → drag math →
// the fr template that lands back on the element.
//
// That leaves the two claims worth pinning, neither of which a server render or a
// unit test can see:
//   1. a focused handle takes ←/→ back from NavigationBar (which listens on `window`
//      in the bubble phase) — the deck's arrows must NOT fire while it has focus;
//   2. Esc mid-drag restores the tracks, and a drag that never happened leaves the
//      authored template alone.

const TRACKS = '300px 500px';

function stubGrid(tracks = TRACKS) {
	const real = window.getComputedStyle.bind(window);
	vi.spyOn(window, 'getComputedStyle').mockImplementation(((el: Element) => {
		if ((el as HTMLElement).classList?.contains('columns')) {
			return { gridTemplateColumns: tracks, columnGap: '0px' } as CSSStyleDeclaration;
		}
		return real(el as Element);
	}) as typeof window.getComputedStyle);
}

/** A pointer event jsdom will accept — it has no PointerEvent constructor. `detail`
 *  is 0 because that is what a real pointerdown carries (see Terminal.test.ts). */
function pointer(type: string, clientX: number, opts: { button?: number } = {}) {
	const ev = new MouseEvent(type, {
		bubbles: true,
		cancelable: true,
		clientX,
		detail: 0,
		button: opts.button ?? 0
	});
	Object.defineProperty(ev, 'pointerId', { value: 1 });
	return ev;
}

const handles = (root: ParentNode) => Array.from(root.querySelectorAll('.handle')) as HTMLElement[];
const grid = (root: ParentNode) => root.querySelector('.columns') as HTMLElement;
const applied = (root: ParentNode) => grid(root).style.getPropertyValue('--columns-tracks');

/** Grab a handle, move the pointer, and (unless told otherwise) release. */
function drag(handle: HTMLElement, dx: number, opts: { release?: boolean } = {}) {
	handle.dispatchEvent(pointer('pointerdown', 0));
	window.dispatchEvent(pointer('pointermove', dx));
	if (opts.release !== false) window.dispatchEvent(pointer('pointerup', dx));
}

beforeEach(() => {
	stubGrid();
	adjustMode.set(false);
	canAdjust.set(false);
});
afterEach(() => vi.restoreAllMocks());

describe('Columns — draggable divider', () => {
	it('renders no handle until a group opts in', async () => {
		const { container } = render(ColumnsHost, { props: {} });
		await tick();
		expect(handles(container)).toHaveLength(0);
	});

	it('ADJUST mode makes the gutters draggable without `resizable`', async () => {
		const { container } = render(ColumnsHost, { props: {} });
		canAdjust.set(true);
		adjustMode.set(true);
		await tick();
		await tick();
		expect(handles(container)).toHaveLength(1);
	});

	it('places one handle per gutter, at the gutter’s centre', async () => {
		const { container } = render(ColumnsHost, { props: { resizable: true, columns: 2 } });
		await tick();
		const [handle] = handles(container);
		// tracks 300 | 500, no gap → the single gutter sits on the 300px edge.
		expect(handle.style.left).toBe('300px');
	});

	it('a drag trades width between its two tracks and re-emits them as fr weights', async () => {
		const { container } = render(ColumnsHost, { props: { resizable: true } });
		await tick();

		drag(handles(container)[0], 100);
		await tick();
		// 300 + 100 = 400, and its partner gives up exactly what it gained.
		expect(applied(container)).toBe('minmax(0, 400fr) minmax(0, 400fr)');
	});

	it('floors a drag at minTrack rather than collapsing a column', async () => {
		const { container } = render(ColumnsHost, { props: { resizable: true, minTrack: 40 } });
		await tick();

		drag(handles(container)[0], -1000);
		await tick();
		expect(applied(container)).toBe('minmax(0, 40fr) minmax(0, 760fr)');
	});

	it('Esc mid-drag restores the tracks and the authored template', async () => {
		const { container } = render(ColumnsHost, { props: { resizable: true } });
		await tick();
		const authored = applied(container);

		drag(handles(container)[0], 100, { release: false });
		await tick();
		expect(applied(container)).toBe('minmax(0, 400fr) minmax(0, 400fr)');

		// trackPointer listens for Escape on window, in the capture phase.
		window.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
		await tick();
		expect(applied(container)).toBe(authored);
	});

	it('ignores a secondary button — a right-click is not a grab', async () => {
		const { container } = render(ColumnsHost, { props: { resizable: true } });
		await tick();
		const authored = applied(container);

		handles(container)[0].dispatchEvent(pointer('pointerdown', 0, { button: 2 }));
		window.dispatchEvent(pointer('pointermove', 100));
		await tick();
		expect(applied(container)).toBe(authored);
	});

	it('double-click resets a dragged divider to the authored widths', async () => {
		const { container } = render(ColumnsHost, { props: { resizable: true } });
		await tick();
		const authored = applied(container);

		drag(handles(container)[0], 100);
		await tick();
		expect(applied(container)).not.toBe(authored);

		handles(container)[0].dispatchEvent(new MouseEvent('dblclick', { bubbles: true }));
		await tick();
		await tick();
		expect(applied(container)).toBe(authored);
	});
});

describe('Columns — the divider’s keyboard', () => {
	/** NavigationBar's real listener: `window`, bubble phase, no focus guard. */
	function watchDeckArrows() {
		const seen: string[] = [];
		const listener = (e: Event) => seen.push((e as KeyboardEvent).key);
		window.addEventListener('keydown', listener);
		return { seen, stop: () => window.removeEventListener('keydown', listener) };
	}

	function arrow(handle: HTMLElement, key: string, shiftKey = false) {
		handle.dispatchEvent(new KeyboardEvent('keydown', { key, shiftKey, bubbles: true, cancelable: true }));
	}

	it('a focused handle resizes on ←/→ and keeps them from paging the deck', async () => {
		const { container } = render(ColumnsHost, { props: { resizable: true } });
		await tick();
		const deck = watchDeckArrows();

		arrow(handles(container)[0], 'ArrowRight');
		await tick();
		expect(applied(container)).toBe('minmax(0, 316fr) minmax(0, 484fr)');

		arrow(handles(container)[0], 'ArrowLeft', true); // Shift → the bigger step
		await tick();
		expect(applied(container)).toBe('minmax(0, 252fr) minmax(0, 548fr)');

		// The load-bearing assertion: neither arrow reached the deck's window listener,
		// so NavigationBar never paged away from under the presenter's hand.
		expect(deck.seen).toEqual([]);
		deck.stop();
	});

	it('leaves every other key to the deck — Space still advances', async () => {
		const { container } = render(ColumnsHost, { props: { resizable: true } });
		await tick();
		const deck = watchDeckArrows();

		arrow(handles(container)[0], ' ');
		arrow(handles(container)[0], 'ArrowUp');
		await tick();
		expect(deck.seen).toEqual([' ', 'ArrowUp']);
		deck.stop();
	});

	it('is a splitter to a screen reader, and reports the share it holds', async () => {
		const { container } = render(ColumnsHost, { props: { resizable: true } });
		await tick();
		const [handle] = handles(container);

		expect(handle.getAttribute('role')).toBe('separator');
		expect(handle.getAttribute('aria-orientation')).toBe('vertical');
		expect(handle.getAttribute('tabindex')).toBe('0');
		// 300 of 800 → 38%.
		expect(handle.getAttribute('aria-valuenow')).toBe('38');
	});
});
