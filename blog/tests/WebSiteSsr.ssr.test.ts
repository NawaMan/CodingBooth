// @vitest-environment node
//
// True server-side render of WebSite / WebPage (svelte/server, no DOM). The
// contract a server render must honour:
//
//   - A LAZY embed (the default) emits NO iframe — nothing fetches a third party
//     until a reader's viewport reaches it — but DOES emit a plain <a href> to the
//     site, so a JS-less reader still finds the link. (A SlideDeck withholds slide
//     markup from the prerendered HTML anyway; this is what a `text` artifact and
//     any non-gated host get.)
//   - `lazy={false}` emits the iframe, and emits it SHIELDED and inert. The shield
//     is server-rendered alongside the frame rather than added on hydrate, so there
//     is no first-paint window in which the iframe can steal the pointer.
import { render } from 'svelte/server';
import { describe, expect, it } from 'vitest';
import WebSite from '../src/lib/components/WebSite.svelte';
import WebPage from '../src/lib/components/WebPage.svelte';

const SRC = 'https://svelte.dev/docs';

/** The `live` class on the iframe — the one thing that lets it take pointer events.
    Matched on the tag, since Svelte emits its scope class alongside it. */
const LIVE_FRAME = /<iframe[^>]*\blive\b/;

describe('WebSite (SSR)', () => {
	it('lazy (default): no iframe, but a crawlable link to the site', () => {
		const { body } = render(WebSite, { props: { src: SRC } });
		expect(body).not.toContain('<iframe');
		expect(body).toContain('class="placeholder');
		expect(body).toContain(`href="${SRC}"`);
	});

	it('lazy={false}: the iframe is prerendered, sandboxed, titled — and shielded', () => {
		const { body } = render(WebSite, { props: { src: SRC, lazy: false } });
		expect(body).toContain('<iframe');
		expect(body).toContain(`src="${SRC}"`);
		expect(body).toContain('sandbox="allow-scripts allow-same-origin allow-popups allow-forms"');
		expect(body).toContain('title="svelte.dev"'); // default title = the URL's host
		// Shield in the FIRST paint, not bolted on at hydrate: no window in which
		// the frame is live. `live` is what would make it so; it is absent.
		expect(body).toContain('class="shield');
		expect(body).not.toMatch(LIVE_FRAME);
	});

	it('interactive={true} renders a live frame with no shield', () => {
		const { body } = render(WebSite, { props: { src: SRC, lazy: false, interactive: true } });
		expect(body).not.toContain('class="shield');
		expect(body).toMatch(LIVE_FRAME);
	});

	it('sandbox="" locks the frame down; sandbox={false} drops the attribute', () => {
		const locked = render(WebSite, { props: { src: SRC, lazy: false, sandbox: '' } });
		expect(locked.body).toContain('sandbox=""');

		const open = render(WebSite, { props: { src: SRC, lazy: false, sandbox: false } });
		expect(open.body).not.toContain('sandbox'); // NOT the string "false"
	});

	it('chrome bar carries the label and an escape hatch; chrome={false} drops it', () => {
		const withBar = render(WebSite, { props: { src: SRC, title: 'Svelte docs' } });
		expect(withBar.body).toContain('>Svelte docs</span>');
		expect(withBar.body).toContain('Open ↗');

		const bare = render(WebSite, { props: { src: SRC, chrome: false } });
		expect(bare.body).not.toContain('class="bar"');
	});

	it('zoom scales the frame up then down; zoom=1 emits no transform', () => {
		const half = render(WebSite, { props: { src: SRC, lazy: false, zoom: 0.5 } });
		expect(half.body).toContain('width: 200%');
		expect(half.body).toContain('scale(0.5)');

		const one = render(WebSite, { props: { src: SRC, lazy: false } });
		expect(one.body).not.toContain('scale(');
	});

	it('a zero or NaN zoom falls back to 1:1 rather than an infinite frame', () => {
		for (const zoom of [0, -2, NaN]) {
			const { body } = render(WebSite, { props: { src: SRC, lazy: false, zoom } });
			expect(body).not.toContain('scale(');
			expect(body).not.toContain('Infinity');
		}
	});

	it('a malformed src degrades to showing the src verbatim, not an empty label', () => {
		const { body } = render(WebSite, { props: { src: '/local/page.html' } });
		expect(body).toContain('>/local/page.html</a>');
	});
});

describe('WebPage (SSR)', () => {
	it('renders the embed; paging is the deck ControlBar\'s job, not a bar of its own', () => {
		const { body } = render(WebPage, { props: { src: SRC } });
		expect(body).toContain('class="webpage');
		expect(body).toContain(`href="${SRC}"`); // the lazy placeholder's link
		// The pager moved to SlideDeck's ControlBar — WebPage no longer ships one.
		expect(body).not.toContain('NEXT');
	});
});
