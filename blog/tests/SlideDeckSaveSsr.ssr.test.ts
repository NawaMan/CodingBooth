// @vitest-environment node
//
// True server-side render of the deck shell (svelte/server, no DOM). ADJUST is
// authoring chrome, and it is now allowed to survive into a BUILD — a deck can pass
// `adjust` to ship it on purpose (demo mode), and SAVE renders disabled as
// NOT ALLOWED rather than being compiled away. That makes the prerender boundary
// worth pinning: none of that chrome may reach the STATIC HTML.
//
// It can't, because SlideDeck gates its whole content — chrome included — on
// `initialized`, which only flips at onMount. But "it can't" is exactly the kind of
// claim that quietly stops being true, and the failure is silent: a stray ADJUST or
// NOT ALLOWED baked into every prerendered page, visible to a crawler and to anyone
// reading the source of a published deck.
import { render } from 'svelte/server';
import { describe, expect, it } from 'vitest';
import SlideDeck from '../src/lib/components/SlideDeck.svelte';
import { adjustMode, canAdjust, canSave } from '../src/lib/stores/adjustMode';

// A slide that TEACHES adjust — the loudest case, and the one most likely to leak.
const teaches = [{ path: 'stub.html', title: 'Stub', adjust: true }];

describe('ADJUST chrome (SSR)', () => {
	it('prerenders no authoring chrome, even for a slide that offers ADJUST', () => {
		const { body } = render(SlideDeck, { props: { pages: teaches } });
		expect(body).not.toContain('annot-tools');
		expect(body).not.toContain('ADJUST');
	});

	// The worst case, forced: control offered, mode on, save impossible. Even then none
	// of it may be baked into the static page — not the button, not the refusal, not the
	// tooltip that explains it.
	it('prerenders no SAVE button, no refusal, no tooltip', () => {
		canAdjust.set(true);
		adjustMode.set(true);
		canSave.set(false);
		const { body } = render(SlideDeck, { props: { pages: teaches, adjust: true } });
		expect(body).not.toContain('save-btn');
		expect(body).not.toContain('save-tip');
		expect(body).not.toContain('NOT ALLOWED');
		expect(body).not.toContain('Save not allowed in this setup.');
		expect(body).not.toContain('SAVE');
	});

	// The stores must not read localStorage or a URL on the server. If they did,
	// rendering here would have thrown before either assertion above ran — so this
	// records the guarantee rather than re-proving it.
	it('renders at all on the server, so nothing in the ADJUST stores touched the browser', () => {
		expect(() => render(SlideDeck, { props: { pages: teaches, adjust: true } })).not.toThrow();
	});
});
