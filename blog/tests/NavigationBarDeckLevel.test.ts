// DOM tests for the deck-level pager seam. SlideDeck's ControlBar mounts ONE NavigationBar with
// `deckLevel`, which owns paging for every ordinary slide — but must yield to a slide that brings
// its own bar (an AppendixPage's RETURN pager, a bespoke route). A NON-deckLevel bar registers
// itself in `localNav`; the deckLevel bar goes DORMANT (hidden, key handler inert) while any such
// registration stands, and stays MOUNTED so a client-side slide change can't flicker it.
import { render, cleanup } from '@testing-library/svelte';
import { afterEach, describe, expect, it } from 'vitest';
import { get } from 'svelte/store';
import { tick } from 'svelte';
import NavigationBar from '../src/lib/components/NavigationBar.svelte';
import { localNav, registerNav } from '../src/lib/stores/localChrome';

afterEach(() => {
	cleanup();
	localNav.set(new Set());
});

describe('NavigationBar deckLevel', () => {
	it('is active (not dormant) while no slide owns its own pager', () => {
		render(NavigationBar, { props: { deckLevel: true, nextLink: 'b.html', prevLink: 'a.html' } });
		const nav = document.querySelector('.nav.bar');
		expect(nav).toBeTruthy();
		expect(nav?.classList.contains('dormant')).toBe(false);
		expect(document.body.textContent).toContain('NEXT');
	});

	it('mounting the deckLevel bar does NOT register — only slide-local bars do', () => {
		render(NavigationBar, { props: { deckLevel: true } });
		expect(get(localNav).size).toBe(0);
	});

	it('goes dormant the moment a slide-local pager registers', async () => {
		render(NavigationBar, { props: { deckLevel: true, nextLink: 'b.html' } });
		const nav = document.querySelector('.nav.bar');
		expect(nav?.classList.contains('dormant')).toBe(false);

		registerNav(Symbol('appendix'));
		await tick();
		expect(nav?.classList.contains('dormant')).toBe(true);
	});

	it('a non-deckLevel bar publishes itself so the deck pager can yield', () => {
		render(NavigationBar, { props: { nextLink: 'b.html' } });
		expect(get(localNav).size).toBe(1);
		// It is a normal in-slide bar, not the bar-hosted one.
		const nav = document.querySelector('.nav');
		expect(nav?.classList.contains('bar')).toBe(false);
	});
});
