// @vitest-environment node
//
// True server-side render of the Table of Contents (svelte/server, no DOM). The
// TOC opens only on a click, so on the server the menu is CLOSED — and full-deck
// search is a client affordance that must not leak into every prerendered page.
// The slide sources are now globbed into a build-time index; a stray line of that
// index (or the search box itself) baked into static HTML would be the failure
// mode, so this pins that it stays out until the menu is opened.
import { render } from 'svelte/server';
import { describe, expect, it } from 'vitest';
import TableOfContent from '../src/lib/components/TableOfContent.svelte';

const pages = [
	{ path: 'a.html', title: 'Intro' },
	{ path: 'b.html', title: 'Backpressure' }
];
const docs = [{ path: 'a.html', title: 'Intro', text: 'SENTINEL-BODY-TEXT' }];

describe('TOC search (SSR)', () => {
	it('prerenders the TOC toggle', () => {
		const { body } = render(TableOfContent, { props: { pages, deck: 'slides', docs } });
		// Mnemonic underlines the T, so the raw HTML splits the word; the visible
		// label (tags stripped) is still "Table of Contents".
		expect(body).toContain('chrome-mn');
		expect(body.replace(/<[^>]+>/g, '')).toContain('Table of Contents');
	});

	it('does NOT prerender the search box (menu is closed on the server)', () => {
		const { body } = render(TableOfContent, { props: { pages, deck: 'slides', docs } });
		expect(body).not.toContain('Search slides');
		expect(body).not.toContain('input class="search"');
	});

	it('does NOT leak indexed slide body text into the static page', () => {
		const { body } = render(TableOfContent, { props: { pages, deck: 'slides', docs } });
		expect(body).not.toContain('SENTINEL-BODY-TEXT');
	});
});
