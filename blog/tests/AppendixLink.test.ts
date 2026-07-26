import { render, screen, cleanup, fireEvent } from '@testing-library/svelte';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { readable } from 'svelte/store';
import AppendixLink from '$lib/components/AppendixLink.svelte';

// AppendixLink — the call site. Two jobs: stamp the CURRENT slide as the return
// address (so the author never types one, and the same appendix returns to whichever
// slide asked), and — when asked — take the navigation over so the jump can animate.

vi.mock('$app/stores', () => ({
	page: readable({ url: new URL('http://localhost/slides/heap.html') }),
	navigating: readable(null),
	updated: readable(false)
}));

const navigate = vi.fn();
vi.mock('$lib/utils/deckNav', () => ({ navigate: (...args: unknown[]) => navigate(...args) }));

beforeEach(() => navigate.mockClear());
afterEach(() => cleanup());

const link = () => screen.getByRole('link');

describe('AppendixLink — the way in', () => {
	it('stamps the slide it sits on as the return address', () => {
		render(AppendixLink, { props: { to: 'appendix-gc.html' } });
		expect(link().getAttribute('href')).toBe('./appendix-gc.html?return=heap.html');
	});

	// A real href, always — so middle-click, "open in new tab" and JS-off all work, and
	// the destination shows in the status bar. `transition` changes how a PLAIN click is
	// handled, never what the link IS.
	it('keeps its href even when it takes the click over', () => {
		render(AppendixLink, { props: { to: 'appendix-gc.html', transition: true } });
		expect(link().getAttribute('href')).toBe('./appendix-gc.html?return=heap.html');
	});
});

describe('AppendixLink — the motion of a detour (transition)', () => {
	it('drops the appendix in from above', async () => {
		render(AppendixLink, { props: { to: 'appendix-gc.html', transition: true } });

		await fireEvent.click(link());
		expect(navigate).toHaveBeenCalledWith(
			'./appendix-gc.html?return=heap.html',
			expect.objectContaining({ kind: 'appendix-in', viewTransitions: true, direction: 'forward' })
		);
	});

	// Without it the browser simply follows the href: a full page load, like the rest of
	// a normal deck. Nothing is intercepted, so nothing can break.
	//
	// (This test prints jsdom's "Not implemented: navigation" to stderr, and that noise
	// IS the assertion's twin: jsdom only complains because the click was left alone and
	// it tried to follow the href for real. A passing run is supposed to print it.)
	it('leaves the click to the browser when not asked to animate', async () => {
		render(AppendixLink, { props: { to: 'appendix-gc.html' } });

		await fireEvent.click(link());
		expect(navigate).not.toHaveBeenCalled();
	});

	// A modified click means "somewhere else" — a new tab, a new window. Hijacking it to
	// animate the current one would be taking away a browser gesture the user owns.
	it('never steals a modified click', async () => {
		render(AppendixLink, { props: { to: 'appendix-gc.html', transition: true } });

		await fireEvent.click(link(), { metaKey: true });
		await fireEvent.click(link(), { ctrlKey: true });
		await fireEvent.click(link(), { shiftKey: true });
		expect(navigate).not.toHaveBeenCalled();
	});
});
