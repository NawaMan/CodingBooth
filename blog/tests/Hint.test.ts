// DOM tests for Hint's cross-page position memory (stores/hintPos.ts). The static half —
// markup from props alone — is HintSsr.ssr.test.ts; what only a DOM can show is the part
// that only exists at runtime: a drag, a dismissal, and what survives a fresh mount.
//
// Each slide is its own prerendered document, so a "different page" is, for a component,
// nothing more exotic than an unmount followed by a brand-new render — exactly what a full
// page navigation does to every component's local state. That is simulated here with
// `unmount()` + a second `render()`, while `hintOffset` (a real persisted store, backed by
// the SAME localStorage a navigation leaves untouched) is what is actually under test.
import { render, cleanup, fireEvent } from '@testing-library/svelte';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { get } from 'svelte/store';
import HintHost from './HintHost.svelte';
import { hintOffset } from '../src/lib/stores/hintPos';

const grip = (root: ParentNode) => root.querySelector('.grip') as HTMLElement;
const pill = (root: ParentNode) => root.querySelector('.text') as HTMLElement;
const close = (root: ParentNode) => root.querySelector('.close') as HTMLElement;
const translated = (root: ParentNode) => (pill(root).getAttribute('style') || '').includes('translate(');

/** Drag the grip by a fixed, non-zero screen-px delta. jsdom has no layout (every rect is
    zero-sized), so this only needs to prove SOME drag reached the shared store — the exact
    canvas-px math is Annotate's clampBarPos/barPosCodec territory, already covered there. */
async function drag(root: ParentNode) {
	const g = grip(root);
	await fireEvent(g, new MouseEvent('pointerdown', { clientX: 0, clientY: 0, bubbles: true, button: 0 }));
	await fireEvent(window, new MouseEvent('pointermove', { clientX: 40, clientY: 20, bubbles: true }));
	await fireEvent(window, new MouseEvent('pointerup', { bubbles: true }));
}

beforeEach(() => {
	localStorage.clear();
	hintOffset.set(null);
});
afterEach(cleanup);

describe('Hint — position survives a page change, resets on dismiss', () => {
	it('starts at its resting spot (no stray transform) with nothing stored', () => {
		const { container } = render(HintHost);
		expect(translated(container)).toBe(false);
	});

	it('a drag moves it, and is remembered in the shared store', async () => {
		const { container } = render(HintHost);
		await drag(container);
		expect(get(hintOffset)).not.toBeNull();
		expect(translated(container)).toBe(true);
	});

	it('a NEW instance (a different slide) inherits the position — never dismissed', async () => {
		const first = render(HintHost, { props: { text: 'First slide' } });
		await drag(first.container);
		const moved = get(hintOffset);
		expect(moved).not.toBeNull();

		// A full-page navigation: this instance is gone, a fresh one takes its place.
		first.unmount();
		const second = render(HintHost, { props: { text: 'A different slide entirely' } });
		expect(translated(second.container)).toBe(true);
		expect(get(hintOffset)).toEqual(moved);
	});

	it('dismissing (×) resets the position for the NEXT Hint too', async () => {
		const first = render(HintHost, { props: { text: 'First slide' } });
		await drag(first.container);
		expect(get(hintOffset)).not.toBeNull();

		await fireEvent.click(close(first.container));
		expect(get(hintOffset)).toBeNull();

		first.unmount();
		const second = render(HintHost, { props: { text: 'Next slide' } });
		expect(translated(second.container)).toBe(false);
	});

	it('double-clicking the grip clears the shared position, same as dismissing', async () => {
		hintOffset.set({ x: 30, y: 30 });
		const { container } = render(HintHost);
		expect(translated(container)).toBe(true);

		await fireEvent.dblClick(grip(container));
		expect(get(hintOffset)).toBeNull();
		expect(translated(container)).toBe(false);
	});

	it('movable={false} ignores any inherited position and offers no grip', () => {
		hintOffset.set({ x: 30, y: 30 });
		const { container } = render(HintHost, { props: { movable: false } });
		expect(translated(container)).toBe(false);
		expect(grip(container)).toBeNull();
	});
});
