// @vitest-environment node
//
// True server-side render of OverviewPage (svelte/server, no DOM).
//
// The load-bearing fact for this feature is a NEGATIVE one, and it can only be
// proven here. The grid's tiles are live <iframe>s of every slide in the deck —
// so if the grid rendered open, or rendered its tiles eagerly, then EVERY
// prerendered slide would ship one iframe per slide in the deck. A 65-slide deck
// would emit 65 * 65 = 4,225 iframes across the built site, and each slide would
// try to boot 65 documents on load.
//
// It does not, because the grid is closed until a human asks for it: `open` starts
// false, so the server renders the toggle and nothing else. This test is what keeps
// it that way.
import { render } from 'svelte/server';
import { describe, expect, it } from 'vitest';
import OverviewPage from '../src/lib/components/OverviewPage.svelte';
import type { Page } from '../src/lib/utils/navigate';

const deck: Array<Page> = [
	{ path: 'title.html', title: 'Title' },
	{ path: 'intro.html', title: 'Intro' },
	{ path: 'appendix-gc.html', title: 'Appendix — GC', hidden: true },
	{ path: 'outro.html', title: 'Outro' }
];

const html = (currentPath = 'intro.html') =>
	render(OverviewPage, { props: { pages: deck, currentPath, width: 1920, height: 1080 } }).body;

describe('OverviewPage (SSR)', () => {
	it('prerenders NO ELEMENT AT ALL — the grid is a keystroke, not a button', () => {
		// There is no toggle any more. The grid is opened with `o` and closed with Esc, and a
		// deck's corner is not the place to advertise a shortcut a speaker either knows or does
		// not need. So a shut grid puts no ELEMENT in the prerendered page — only Svelte's own
		// hydration anchors, which are comments and paint nothing — and that makes every negative
		// below true by construction rather than by care.
		const elements = html().replace(/<!--.*?-->/g, '').trim();
		expect(elements).toBe('');
	});

	it('prerenders NO iframe — the whole deck is not embedded in every slide', () => {
		const body = html();
		// The one assertion this file exists for.
		expect(body).not.toContain('<iframe');
		expect(body).not.toContain('?clean');
	});

	it('prerenders the grid CLOSED — no scrim, no tiles', () => {
		const body = html();
		expect(body).not.toContain('class="scrim');
		expect(body).not.toContain('class="tile');
		// Not even the cheap cards: a shut grid costs the built page nothing but a
		// button.
		expect(body).not.toContain('3 slides');
		expect(body).not.toContain('Outro');
	});

	it('renders without a browser, a deck context or an IntersectionObserver', () => {
		// There is no window on the server: no keydown listener, no observer, and
		// getViewTransitions() falls back to false with no deck around it. Rendering
		// must simply not throw — a component that reached for any of them would
		// take the whole prerender down with it.
		expect(() => html('')).not.toThrow();
		expect(() => render(OverviewPage, { props: {} }).body).not.toThrow();
	});
});
